import SwiftUI
import AppKit

@main
struct HPD15App: App {
    @StateObject private var model = AppModel()

    init() {
        // Nécessaire quand l'exécutable est lancé par `swift run` : fenêtre au premier plan, menu visible.
        NSApplication.shared.setActivationPolicy(.regular)
        NSApplication.shared.activate(ignoringOtherApps: true)
    }

    var body: some Scene {
        WindowGroup(L("Editeur HPD-15")) {
            ContentView()
                .environmentObject(model)
                .frame(minWidth: 1100, minHeight: 720)
                .preferredColorScheme(.dark)
        }
    }
}
