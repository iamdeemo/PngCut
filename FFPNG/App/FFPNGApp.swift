import AppKit
import SwiftUI

@main
struct FFPNGApp: App {
    @StateObject private var model = AppModel()

    init() {
        NSApplication.shared.appearance = NSAppearance(named: .aqua)
    }

    var body: some Scene {
        WindowGroup {
            MainWindowView(model: model)
                .frame(minWidth: 560, minHeight: 430)
                .preferredColorScheme(.light)
        }
        .windowStyle(.hiddenTitleBar)
    }
}
