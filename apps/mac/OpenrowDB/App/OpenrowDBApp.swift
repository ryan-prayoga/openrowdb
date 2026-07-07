// OpenrowDBApp.swift
import AppKit
import OpenrowDBCore
import SwiftUI

/// Without a packaged `.app` bundle, a SwiftPM executable launches as an
/// accessory process: its window can't become key, so it accepts no keyboard
/// input and shows no menu bar. Forcing a regular activation policy on launch
/// restores normal app behaviour until the Phase 5 Xcode bundle lands.
final class AppDelegate: NSObject, NSApplicationDelegate {
    func applicationDidFinishLaunching(_ notification: Notification) {
        NSApp.setActivationPolicy(.regular)
        NSApp.activate(ignoringOtherApps: true)
    }

    func applicationShouldTerminateAfterLastWindowClosed(_ sender: NSApplication) -> Bool {
        true
    }
}

@main
struct OpenrowDBApp: App {
    @NSApplicationDelegateAdaptor(AppDelegate.self) private var appDelegate
    @State private var manager = OpenrowDBApp.makeManager()
    @State private var history = OpenrowDBApp.makeHistory()
    @State private var snippets = OpenrowDBApp.makeSnippets()
    @State private var tabs = WorkspaceTabsState()
    @State private var sessionStore = OpenrowDBApp.makeSessionStore()
    @State private var preferences = AppPreferences.shared
    @State private var showingOnboarding = !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
    @State private var openConnectionAfterOnboarding = !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
    @Environment(\.openWindow) private var openWindow
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup(id: "main") {
            ContentView()
                .environment(manager)
                .environment(history)
                .environment(snippets)
                .environment(tabs)
                .environment(preferences)
                .task {
                    try? manager.reload()
                    tabs.sessionStore = sessionStore
                }
                .onChange(of: scenePhase) { _, phase in
                    if phase == .background {
                        for connection in manager.connections {
                            tabs.persistNow(for: connection.id)
                        }
                    }
                }
                .sheet(isPresented: $showingOnboarding, onDismiss: {
                    if openConnectionAfterOnboarding {
                        WindowCommandRouter.shared.presentNewConnection()
                        openConnectionAfterOnboarding = false
                    }
                }) {
                    OnboardingView(
                        onDismiss: {
                            UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                            showingOnboarding = false
                        },
                        onSamplePostgres: {
                            finishOnboardingWithSample(.localPostgres)
                        },
                        onSampleMySQL: {
                            finishOnboardingWithSample(.localMySQL)
                        }
                    )
                }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 700)

        WindowGroup(id: "connection", for: UUID.self) { $connectionID in
            if let connectionID {
                ConnectionWindowView(connectionID: connectionID)
                    .environment(manager)
                    .environment(history)
                    .environment(snippets)
                    .environment(tabs)
                    .environment(preferences)
            }
        }
        .windowStyle(.hiddenTitleBar)
        .windowResizability(.contentSize)
        .defaultSize(width: 960, height: 640)

        Settings {
            PreferencesView()
                .environment(preferences)
        }

        .commands {
            CommandGroup(replacing: .appSettings) {
                Button("Settings…") {
                    NSApp.sendAction(Selector(("showSettingsWindow:")), to: nil, from: nil)
                }
                .keyboardShortcut(",", modifiers: .command)
            }
            CommandGroup(replacing: .newItem) {
                Button("New Connection…") {
                    WindowCommandRouter.shared.presentNewConnection()
                }
                .keyboardShortcut("n", modifiers: [.command])
                Button("New Window") {
                    openWindow(id: "main")
                }
                .keyboardShortcut("n", modifiers: [.command, .shift])
            }
            CommandGroup(replacing: .undoRedo) {
                Button("Undo") { EditorCommandCenter.shared.undo() }
                    .keyboardShortcut("z", modifiers: .command)
                Button("Redo") { EditorCommandCenter.shared.redo() }
                    .keyboardShortcut("z", modifiers: [.command, .shift])
            }
            CommandGroup(after: .pasteboard) {
                Button("Find…") { EditorCommandCenter.shared.find() }
                    .keyboardShortcut("f", modifiers: .command)
            }
            CommandGroup(before: .help) {
                Button("Search…") {
                    WindowCommandRouter.shared.presentSearch()
                }
                .keyboardShortcut("k", modifiers: .command)
            }
            CommandGroup(replacing: .help) {
                Button("Welcome to OpenrowDB…") {
                    openConnectionAfterOnboarding = false
                    showingOnboarding = true
                }
                Button("Keyboard Shortcuts…") {
                    WindowCommandRouter.shared.presentShortcuts()
                }
                .keyboardShortcut("/", modifiers: .command)
                Divider()
                Button("OpenrowDB on GitHub…") {
                    openURL("https://github.com/ryan-prayoga/openrowdb")
                }
                Button("Report an Issue…") {
                    openURL("https://github.com/ryan-prayoga/openrowdb/issues/new")
                }
            }
        }
    }

    private func openURL(_ string: String) {
        guard let url = URL(string: string) else { return }
        NSWorkspace.shared.open(url)
    }

    private func finishOnboardingWithSample(_ preset: ConnectionFormPreset) {
        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
        openConnectionAfterOnboarding = false
        showingOnboarding = false
        WindowCommandRouter.shared.presentNewConnection(preset: preset)
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
            do {
                let fallback = FileManager.default.temporaryDirectory
                    .appendingPathComponent("OpenrowDB/connections.json")
                store = try ConnectionStore(fileURL: fallback)
            } catch {
                fatalError("OpenrowDB: cannot initialize connection store in Application Support or temp directory: \(error)")
            }
        }
        return ConnectionManager(store: store, secrets: KeychainSecretStore())
    }

    /// Build the app's `QueryHistoryStore`. Falls back to a temp file so the app
    /// never fails to launch even if Application Support is unavailable.
    @MainActor
    private static func makeHistory() -> QueryHistoryStore {
        do {
            return try QueryHistoryStore()
        } catch {
            do {
                let fallback = FileManager.default.temporaryDirectory
                    .appendingPathComponent("OpenrowDB/history.sqlite")
                return try QueryHistoryStore(fileURL: fallback)
            } catch {
                fatalError("OpenrowDB: cannot initialize query history in Application Support or temp directory: \(error)")
            }
        }
    }

    @MainActor
    private static func makeSessionStore() -> WorkspaceSessionStore {
        do {
            return try WorkspaceSessionStore()
        } catch {
            do {
                let fallback = FileManager.default.temporaryDirectory
                    .appendingPathComponent("OpenrowDB/workspace.json")
                return try WorkspaceSessionStore(fileURL: fallback)
            } catch {
                fatalError("OpenrowDB: cannot initialize workspace store in Application Support or temp directory: \(error)")
            }
        }
    }

    @MainActor
    private static func makeSnippets() -> QuerySnippetStore {
        do {
            return try QuerySnippetStore()
        } catch {
            do {
                let fallback = FileManager.default.temporaryDirectory
                    .appendingPathComponent("OpenrowDB/snippets.sqlite")
                return try QuerySnippetStore(fileURL: fallback)
            } catch {
                fatalError("OpenrowDB: cannot initialize snippet store in Application Support or temp directory: \(error)")
            }
        }
    }
}