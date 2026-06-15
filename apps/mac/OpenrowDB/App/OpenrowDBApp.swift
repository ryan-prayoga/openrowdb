// OpenrowDBApp.swift
import OpenrowDBCore
import SwiftUI

@main
struct OpenrowDBApp: App {
    @State private var manager = OpenrowDBApp.makeManager()
    @State private var showingNewConnection = false

    var body: some Scene {
        WindowGroup {
            ContentView(showingNewConnection: $showingNewConnection)
                .environment(manager)
                .frame(minWidth: 1000, minHeight: 640)
                .task {
                    try? manager.reload()
                }
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection…") {
                    showingNewConnection = true
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }

    /// Build the app's `ConnectionManager` with Keychain-backed secrets and
    /// on-disk connection storage. Falls back to a temp file if Application
    /// Support is somehow unavailable, so the app never fails to launch.
    @MainActor
    private static func makeManager() -> ConnectionManager {
        let store: ConnectionStore
        do {
            store = try ConnectionStore()
        } catch {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpenrowDB/connections.json")
            // Force is safe: temporaryDirectory + explicit path cannot fail validation here.
            store = try! ConnectionStore(fileURL: fallback)
        }
        return ConnectionManager(store: store, secrets: KeychainSecretStore())
    }
}
