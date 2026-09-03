import AppKit
import SwiftUI

@main
struct CodexModelManagerApp: App {
    @StateObject private var store = CatalogStore()

    var body: some Scene {
        WindowGroup {
            ContentView()
                .environmentObject(store)
                .preferredColorScheme(nil)
        }
        .windowStyle(.hiddenTitleBar)
        .defaultSize(width: 1180, height: 760)
        .commands {
            CommandGroup(after: .newItem) {
                Button("重新載入模型清單") { store.load() }
                    .keyboardShortcut("r", modifiers: .command)
            }
        }
    }
}
