// OpenrowDBApp.swift
import SwiftUI

@main
struct OpenrowDBApp: App {
    var body: some Scene {
        WindowGroup {
            ContentView()
                .frame(minWidth: 1000, minHeight: 640)
        }
        .windowStyle(.hiddenTitleBar)
        .commands {
            CommandGroup(replacing: .newItem) {
                Button("New Connection…") {
                    // wired up in Phase 1
                }
                .keyboardShortcut("n", modifiers: [.command])
            }
        }
    }
}
