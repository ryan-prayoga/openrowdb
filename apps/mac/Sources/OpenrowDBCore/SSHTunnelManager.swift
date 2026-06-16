// SSHTunnelManager.swift
import Foundation

public enum SSHTunnelError: Error, Sendable, Equatable {
    case invalidConfiguration(String)
    case launchFailed(String)
    case noFreePort
}

/// Manages per-connection SSH local port forwards via the system `ssh` binary.
public actor SSHTunnelManager {
    private struct ActiveTunnel {
        let process: Process
        let localPort: Int
        var askpassScript: URL?
    }

    private var tunnels: [UUID: ActiveTunnel] = [:]

    /// Open a tunnel for `connectionID` and return the local port to connect to.
    public func open(
        connectionID: UUID,
        config: SSHTunnelConfig,
        targetHost: String,
        targetPort: Int,
        password: String?
    ) throws -> Int {
        if let existing = tunnels[connectionID] {
            return existing.localPort
        }

        guard config.enabled else {
            throw SSHTunnelError.invalidConfiguration("SSH tunnel is not enabled.")
        }
        guard !config.host.isEmpty, !config.user.isEmpty else {
            throw SSHTunnelError.invalidConfiguration("SSH host and user are required.")
        }

        let localPort = try allocateLocalPort()
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/usr/bin/ssh")
        process.standardOutput = FileHandle.nullDevice
        process.standardError = Pipe()

        var args = [
            "-N",
            "-o", "ExitOnForwardFailure=yes",
            "-o", "StrictHostKeyChecking=accept-new",
            "-L", "\(localPort):\(targetHost):\(targetPort)",
            "-p", "\(config.port)",
        ]

        var askpassScript: URL?
        if let password, !password.isEmpty {
            askpassScript = try writeAskpassScript(password: password)
            var env = ProcessInfo.processInfo.environment
            env["SSH_ASKPASS"] = askpassScript?.path
            env["SSH_ASKPASS_REQUIRE"] = "force"
            env["DISPLAY"] = env["DISPLAY"] ?? ":0"
            process.environment = env
            args.insert(contentsOf: ["-o", "BatchMode=no"], at: 0)
        } else {
            args.insert(contentsOf: ["-o", "BatchMode=yes"], at: 0)
        }

        if !config.privateKeyPath.isEmpty {
            let expanded = NSString(string: config.privateKeyPath).expandingTildeInPath
            args.insert(contentsOf: ["-i", expanded], at: args.count - 2)
        }

        args.append("\(config.user)@\(config.host)")
        process.arguments = args

        do {
            try process.run()
        } catch {
            throw SSHTunnelError.launchFailed(error.localizedDescription)
        }

        // Brief pause so a bad config fails fast before we hand back the port.
        Thread.sleep(forTimeInterval: 0.35)
        if !process.isRunning {
            let message = readPipe(process.standardError as? Pipe) ?? "SSH tunnel exited immediately."
            throw SSHTunnelError.launchFailed(message)
        }

        tunnels[connectionID] = ActiveTunnel(process: process, localPort: localPort, askpassScript: askpassScript)
        return localPort
    }

    public func close(connectionID: UUID) {
        guard let tunnel = tunnels.removeValue(forKey: connectionID) else { return }
        if tunnel.process.isRunning {
            tunnel.process.terminate()
        }
        if let script = tunnel.askpassScript {
            try? FileManager.default.removeItem(at: script)
        }
    }

    public func closeAll() {
        let ids = Array(tunnels.keys)
        for id in ids { close(connectionID: id) }
    }

    // MARK: - Helpers

    private func allocateLocalPort() throws -> Int {
        for port in 33_000...34_000 {
            let fd = socket(AF_INET, SOCK_STREAM, 0)
            guard fd >= 0 else { continue }
            defer { Darwin.close(fd) }

            var yes: Int32 = 1
            setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &yes, socklen_t(MemoryLayout.size(ofValue: yes)))

            var addr = sockaddr_in()
            addr.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
            addr.sin_family = sa_family_t(AF_INET)
            addr.sin_port = in_port_t(port).bigEndian
            addr.sin_addr.s_addr = inet_addr("127.0.0.1")

            let bindResult = withUnsafePointer(to: &addr) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
            if bindResult == 0 { return port }
        }
        throw SSHTunnelError.noFreePort
    }

    private func writeAskpassScript(password: String) throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("openrowdb-ssh-askpass-\(UUID().uuidString).sh")
        let escaped = password.replacingOccurrences(of: "'", with: "'\\''")
        let script = "#!/bin/sh\nprintf '%s' '\(escaped)'\n"
        try script.write(to: url, atomically: true, encoding: .utf8)
        try FileManager.default.setAttributes([.posixPermissions: 0o700], ofItemAtPath: url.path)
        return url
    }

    private func readPipe(_ pipe: Pipe?) -> String? {
        guard let data = try? pipe?.fileHandleForReading.readToEnd() else { return nil }
        let text = String(data: data, encoding: .utf8)?.trimmingCharacters(in: .whitespacesAndNewlines)
        return text?.isEmpty == false ? text : nil
    }
}