import AppKit
import SwiftUI

@main
struct PngCutApp: App {
    @StateObject private var model: AppModel

    init() {
        #if DEBUG
        if let testModel = AppModel.uiTestModel(arguments: ProcessInfo.processInfo.arguments) {
            _model = StateObject(wrappedValue: testModel)
        } else {
            _model = StateObject(wrappedValue: AppModel())
        }
        #else
        _model = StateObject(wrappedValue: AppModel())
        #endif
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
