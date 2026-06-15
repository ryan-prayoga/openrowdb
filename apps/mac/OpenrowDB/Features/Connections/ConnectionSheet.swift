// ConnectionSheet.swift
import OpenrowDBCore
import SwiftUI

/// Create or edit a connection. Password goes to the Keychain; metadata to the
/// connection store. In edit mode, leaving the password blank keeps the stored one.
struct ConnectionSheet: View {
    @Environment(ConnectionManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    /// The connection being edited, or nil when creating a new one.
    let existing: Connection?

    @State private var name: String
    @State private var driver: Connection.Driver
    @State private var host: String
    @State private var port: Int
    @State private var user: String
    @State private var password = ""
    @State private var revealPassword = false
    @State private var database: String
    @State private var sslMode: Connection.SSLMode

    @State private var errorMessage: String?
    @State private var testState: TestState = .idle

    private enum TestState: Equatable {
        case idle, testing, success, failure(String)
    }

    init(existing: Connection? = nil) {
        self.existing = existing
        _name = State(initialValue: existing?.name ?? "")
        _driver = State(initialValue: existing?.driver ?? .postgres)
        _host = State(initialValue: existing?.host ?? "127.0.0.1")
        _port = State(initialValue: existing?.port ?? Connection.Driver.postgres.defaultPort)
        _user = State(initialValue: existing?.user ?? "")
        _database = State(initialValue: existing?.database ?? "")
        _sslMode = State(initialValue: existing?.sslMode ?? .prefer)
    }

    private var isEditing: Bool { existing != nil }

    private var canSave: Bool {
        !name.trimmingCharacters(in: .whitespaces).isEmpty
            && !host.trimmingCharacters(in: .whitespaces).isEmpty
            && !user.trimmingCharacters(in: .whitespaces).isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            Form {
                Section("Connection") {
                    TextField("Name", text: $name)
                    Picker("Driver", selection: $driver) {
                        ForEach(Connection.Driver.allCases, id: \.self) { driver in
                            Text(driver.rawValue.capitalized).tag(driver)
                        }
                    }
                    .onChange(of: driver) { old, new in
                        if port == old.defaultPort { port = new.defaultPort }
                    }
                }

                Section("Server") {
                    TextField("Host", text: $host)
                    TextField("Port", value: $port, format: .number.grouping(.never))
                    TextField("Database", text: $database)
                }

                Section("Authentication") {
                    TextField("User", text: $user)
                    passwordField
                    Picker("SSL", selection: $sslMode) {
                        ForEach(Connection.SSLMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                }

                if let errorMessage {
                    Label(errorMessage, systemImage: "exclamationmark.triangle")
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)

            Divider()
            footer
        }
        .frame(width: 460, height: 520)
    }

    @ViewBuilder
    private var passwordField: some View {
        HStack {
            if revealPassword {
                TextField(passwordPrompt, text: $password)
            } else {
                SecureField(passwordPrompt, text: $password)
            }
            Button {
                revealPassword.toggle()
            } label: {
                Image(systemName: revealPassword ? "eye.slash" : "eye")
            }
            .buttonStyle(.borderless)
            .help(revealPassword ? "Hide password" : "Show password")
        }
    }

    private var passwordPrompt: String {
        isEditing ? "Password (leave blank to keep)" : "Password"
    }

    private var footer: some View {
        HStack(spacing: 10) {
            Button("Cancel", role: .cancel) { dismiss() }
                .keyboardShortcut(.cancelAction)
                .buttonStyle(.glass)

            testButton

            Spacer()

            Button(isEditing ? "Save Changes" : "Save") { save() }
                .keyboardShortcut(.defaultAction)
                .buttonStyle(.glassProminent)
                .disabled(!canSave)
        }
        .padding()
    }

    @ViewBuilder
    private var testButton: some View {
        HStack(spacing: 6) {
            Button("Test") { test() }
                .buttonStyle(.glass)
                .disabled(!canSave || testState == .testing)

            switch testState {
            case .idle:
                EmptyView()
            case .testing:
                ProgressView().controlSize(.small)
            case .success:
                Label("OK", systemImage: "checkmark.circle.fill")
                    .foregroundStyle(.green)
                    .labelStyle(.iconOnly)
                    .help("Connection succeeded")
            case .failure(let message):
                Label("Failed", systemImage: "xmark.circle.fill")
                    .foregroundStyle(.red)
                    .labelStyle(.iconOnly)
                    .help(message)
            }
        }
    }

    // MARK: - Actions

    /// Build a Connection from the current form. Reuses the existing id +
    /// Keychain key when editing so the stored secret stays addressable.
    private func makeConnection() -> Connection {
        let id = existing?.id ?? UUID()
        return Connection(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            driver: driver,
            host: host.trimmingCharacters(in: .whitespaces),
            port: port,
            user: user.trimmingCharacters(in: .whitespaces),
            passwordKeychainKey: existing?.passwordKeychainKey ?? "com.openrowdb.connection.\(id.uuidString)",
            database: database.trimmingCharacters(in: .whitespaces),
            sslMode: sslMode
        )
    }

    private func save() {
        let connection = makeConnection()
        do {
            if isEditing {
                // Blank password in edit mode means "keep the stored one".
                try manager.update(connection, password: password.isEmpty ? nil : password)
            } else {
                try manager.add(connection, password: password)
            }
            dismiss()
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }

    private func test() {
        testState = .testing
        let connection = makeConnection()
        let pw = password
        Task {
            let failure = await manager.test(connection, password: pw.isEmpty ? nil : pw)
            testState = failure.map(TestState.failure) ?? .success
        }
    }
}
