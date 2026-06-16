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
    @State private var refreshCoordinator = RefreshCoordinator()
    @State private var showingNewConnection = false
    @State private var showingOnboarding = !UserDefaults.standard.bool(forKey: "hasSeenOnboarding")
    @State private var showingShortcuts = false
    @Environment(\.scenePhase) private var scenePhase

    var body: some Scene {
        WindowGroup {
            ContentView(showingNewConnection: $showingNewConnection)
                .environment(manager)
                .environment(history)
                .environment(snippets)
                .environment(tabs)
                .environment(refreshCoordinator)
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
                    // onDismiss fires after the sheet animation completes —
                    // safe to present another sheet here with no race condition.
                    showingNewConnection = true
                }) {
                    OnboardingView {
                        UserDefaults.standard.set(true, forKey: "hasSeenOnboarding")
                        showingOnboarding = false
                    }
                }
                .sheet(isPresented: $showingShortcuts) {
                    ShortcutsHelpView()
                }
        }
        .windowStyle(.hiddenTitleBar)
        // Drive the window min size from column widths, not a content frame, so the
        // sidebar toggle animates smoothly. (Apple DTS: forums/thread/775713)
        .windowResizability(.contentSize)
        .defaultSize(width: 1100, height: 700)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection…") {
                    showingNewConnection = true
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
            CommandGroup(replacing: .help) {
                Button("Keyboard Shortcuts…") {
                    showingShortcuts = true
                }
                .keyboardShortcut("/", modifiers: .command)
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

    /// Build the app's `QueryHistoryStore`. Falls back to a temp file so the app
    /// never fails to launch even if Application Support is unavailable.
    @MainActor
    private static func makeHistory() -> QueryHistoryStore {
        do {
            return try QueryHistoryStore()
        } catch {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpenrowDB/history.sqlite")
            return try! QueryHistoryStore(fileURL: fallback)
        }
    }

    @MainActor
    private static func makeSessionStore() -> WorkspaceSessionStore {
        do {
            return try WorkspaceSessionStore()
        } catch {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpenrowDB/workspace.json")
            return try! WorkspaceSessionStore(fileURL: fallback)
        }
    }

    @MainActor
    private static func makeSnippets() -> QuerySnippetStore {
        do {
            return try QuerySnippetStore()
        } catch {
            let fallback = FileManager.default.temporaryDirectory
                .appendingPathComponent("OpenrowDB/snippets.sqlite")
            return try! QuerySnippetStore(fileURL: fallback)
        }
    }
}
