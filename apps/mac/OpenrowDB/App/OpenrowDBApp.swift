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
    @State private var showingNewConnection = false

    var body: some Scene {
        WindowGroup {
            ContentView(showingNewConnection: $showingNewConnection)
                .environment(manager)
                .task {
                    try? manager.reload()
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
