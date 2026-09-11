import AppKit
import SwiftUI

@main
struct PngCutApp: App {
    #if DEBUG
    private static let uiTestDefaultsSuite = "com.ffpng.app.uitests"
    #endif

    @StateObject private var model: AppModel

    init() {
        #if DEBUG
        let arguments = ProcessInfo.processInfo.arguments
        if arguments.contains("--ui-test-isolated-preferences") {
            guard let preferences = UserDefaults(suiteName: Self.uiTestDefaultsSuite) else {
                fatalError("Unable to create UI test defaults suite: \(Self.uiTestDefaultsSuite)")
            }
            preferences.removePersistentDomain(forName: Self.uiTestDefaultsSuite)
            if let testModel = AppModel.uiTestModel(arguments: arguments, preferences: preferences) {
                _model = StateObject(wrappedValue: testModel)
            } else {
                _model = StateObject(wrappedValue: AppModel(
                    preferences: preferences,
                    loadPersistedSettings: false
                ))
            }
        } else if let testModel = AppModel.uiTestModel(arguments: arguments) {
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
                .frame(minWidth: PngCutMetrics.windowSize.width, minHeight: PngCutMetrics.windowSize.height)
                .preferredColorScheme(.light)
        }
        .defaultSize(width: PngCutMetrics.windowSize.width, height: PngCutMetrics.windowSize.height)
        .windowStyle(.hiddenTitleBar)
    }
}
