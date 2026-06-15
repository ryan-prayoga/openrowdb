// NewConnectionSheet.swift
import OpenrowDBCore
import SwiftUI

/// Form to create and persist a new connection. Password goes to the Keychain;
/// metadata to the connection store. Both via `ConnectionManager.add`.
struct NewConnectionSheet: View {
    @Environment(ConnectionManager.self) private var manager
    @Environment(\.dismiss) private var dismiss

    @State private var name = ""
    @State private var driver: Connection.Driver = .postgres
    @State private var host = "127.0.0.1"
    @State private var port = Connection.Driver.postgres.defaultPort
    @State private var user = ""
    @State private var password = ""
    @State private var database = ""
    @State private var sslMode: Connection.SSLMode = .prefer
    @State private var errorMessage: String?

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
                    .onChange(of: driver) { _, newValue in
                        port = newValue.defaultPort
                    }
                }

                Section("Server") {
                    TextField("Host", text: $host)
                    TextField("Port", value: $port, format: .number.grouping(.never))
                    TextField("Database", text: $database)
                }

                Section("Authentication") {
                    TextField("User", text: $user)
                    SecureField("Password", text: $password)
                    Picker("SSL", selection: $sslMode) {
                        ForEach(Connection.SSLMode.allCases, id: \.self) { mode in
                            Text(mode.rawValue.capitalized).tag(mode)
                        }
                    }
                }

                if let errorMessage {
                    Text(errorMessage)
                        .foregroundStyle(.red)
                        .font(.callout)
                }
            }
            .formStyle(.grouped)

            Divider()

            HStack {
                Button("Cancel", role: .cancel) { dismiss() }
                    .keyboardShortcut(.cancelAction)
                    .buttonStyle(.glass)
                Spacer()
                Button("Save") { save() }
                    .keyboardShortcut(.defaultAction)
                    .buttonStyle(.glassProminent)
                    .disabled(!canSave)
            }
            .padding()
        }
        .frame(width: 440, height: 460)
    }

    private func save() {
        let id = UUID()
        let connection = Connection(
            id: id,
            name: name.trimmingCharacters(in: .whitespaces),
            driver: driver,
            host: host.trimmingCharacters(in: .whitespaces),
            port: port,
            user: user.trimmingCharacters(in: .whitespaces),
            passwordKeychainKey: "com.openrowdb.connection.\(id.uuidString)",
            database: database.trimmingCharacters(in: .whitespaces),
            sslMode: sslMode
        )
        do {
            try manager.add(connection, password: password)
            dismiss()
        } catch {
            errorMessage = "Could not save: \(error.localizedDescription)"
        }
    }
}
