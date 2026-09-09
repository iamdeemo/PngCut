import AppKit
import SwiftUI

enum PngCutMetrics {
    static let windowSize = CGSize(width: 720, height: 540)
    static let titleBarHeight: CGFloat = 44
    static let toolbarHeight: CGFloat = 56
    static let contentPadding: CGFloat = 24
    static let dropZoneSize = CGSize(width: 520, height: 320)
    static let dropZoneCornerRadius: CGFloat = 18
    static let modeHeight: CGFloat = 36
    static let iconHitSize: CGFloat = 44
}

enum PngCutPalette {
    static let accent = Color(red: 0.23, green: 0.50, blue: 0.96)
    static let windowTop = Color(red: 0.94, green: 0.94, blue: 0.96)
    static let windowBottom = Color(red: 0.91, green: 0.91, blue: 0.93)
    static let workspace = Color(red: 0.97, green: 0.97, blue: 0.98)
    static let toolbarTop = Color(red: 0.92, green: 0.92, blue: 0.94)
    static let toolbarBottom = Color(red: 0.89, green: 0.89, blue: 0.92)
    static let primaryText = Color(red: 0.20, green: 0.21, blue: 0.24)
    static let secondaryText = Color(red: 0.56, green: 0.57, blue: 0.62)
    static let separator = Color.black.opacity(0.14)
    static let dropStroke = Color(red: 0.78, green: 0.79, blue: 0.83)
}

enum PngCutMotion {
    static func settingsSurface(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeInOut(duration: 0.12) : .timingCurve(0.4, 0, 0.2, 1, duration: 0.24)
    }

    static func homeYield(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeInOut(duration: 0.12) : .timingCurve(0.4, 0, 0.2, 1, duration: 0.22)
    }

    static func modeSelection(reduceMotion: Bool) -> Animation? {
        reduceMotion ? .easeInOut(duration: 0.12) : .timingCurve(0.34, 1.56, 0.64, 1, duration: 0.22)
    }

    static func controlFeedback(reduceMotion: Bool) -> Animation? {
        .easeInOut(duration: reduceMotion ? 0.12 : 0.15)
    }

    static func textSelection(reduceMotion: Bool) -> Animation? {
        .easeInOut(duration: reduceMotion ? 0.12 : 0.18)
    }
}

// Compatibility for the existing settings drawer, whose layout remains outside this task.
enum AppPalette {
    static let workspace = NSColor(calibratedRed: 244 / 255, green: 244 / 255, blue: 244 / 255, alpha: 1)
    static let drawer = NSColor(calibratedRed: 252 / 255, green: 252 / 255, blue: 252 / 255, alpha: 1)
    static let drawerColor = Color(nsColor: drawer)
}

struct PngCutWindowChrome: View {
    var body: some View {
        ZStack {
            LinearGradient(
                colors: [PngCutPalette.windowTop, PngCutPalette.windowBottom],
                startPoint: .top,
                endPoint: .bottom
            )

            HStack(spacing: 0) {
                Color.clear.frame(width: 76)
                Spacer(minLength: 0)
                HStack(spacing: 7) {
                    Image("ImageFile")
                        .renderingMode(.template)
                        .resizable()
                        .scaledToFit()
                        .frame(width: 16, height: 16)
                        .foregroundStyle(PngCutPalette.primaryText)
                    Text("图片压缩")
                        .font(.system(size: 13, weight: .semibold))
                        .foregroundStyle(PngCutPalette.primaryText)
                        .accessibilityIdentifier("windowTitle")
                }
                Spacer(minLength: 0)
                Color.clear.frame(width: 76)
            }
        }
        .frame(height: PngCutMetrics.titleBarHeight)
        .overlay(alignment: .bottom) {
            Rectangle().fill(PngCutPalette.separator).frame(height: 1)
        }
    }
}

struct PngCutPrimaryButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .semibold))
            .padding(.horizontal, 18)
            .frame(minHeight: 34)
            .foregroundStyle(.white)
            .background(PngCutPalette.accent.opacity(configuration.isPressed ? 0.82 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.98 : 1)
            .animation(PngCutMotion.controlFeedback(reduceMotion: reduceMotion), value: configuration.isPressed)
    }
}

struct PngCutToolbarIconButton: View {
    let assetName: String
    let label: String
    let isActive: Bool
    let action: () -> Void

    @Environment(\.isEnabled) private var isEnabled
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isHovered = false

    var body: some View {
        Button(action: action) {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .frame(width: PngCutMetrics.iconHitSize, height: PngCutMetrics.iconHitSize)
                .contentShape(RoundedRectangle(cornerRadius: 8, style: .continuous))
        }
        .buttonStyle(.plain)
        .frame(width: PngCutMetrics.iconHitSize, height: PngCutMetrics.iconHitSize)
        .foregroundStyle(isEnabled ? (isHovered || isActive ? PngCutPalette.accent : PngCutPalette.primaryText) : PngCutPalette.secondaryText)
        .opacity(isEnabled ? 1 : 0.42)
        .onHover { isHovered = $0 }
        .animation(PngCutMotion.controlFeedback(reduceMotion: reduceMotion), value: isHovered)
        .accessibilityLabel(label)
    }
}

struct PngCutModeSelector: View {
    @ObservedObject var model: AppModel
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack(alignment: .leading) {
            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.black.opacity(0.08))

            RoundedRectangle(cornerRadius: 10, style: .continuous)
                .fill(Color.white)
                .frame(width: 110, height: PngCutMetrics.modeHeight)
                .shadow(color: .black.opacity(0.13), radius: 4, y: 1)
                .offset(x: model.settings.mode == .lossless ? 0 : 110)

            HStack(spacing: 0) {
                modeButton(.lossless)
                modeButton(.balanced)
            }
        }
        .frame(width: 220, height: PngCutMetrics.modeHeight)
        .animation(PngCutMotion.modeSelection(reduceMotion: reduceMotion), value: model.settings.mode)
    }

    private func modeButton(_ mode: CompressionMode) -> some View {
        let selected = model.settings.mode == mode
        return Button {
            model.setCompressionMode(mode)
        } label: {
            Text(mode.title)
                .font(.system(size: 12, weight: .semibold))
                .foregroundStyle(selected ? PngCutPalette.primaryText : PngCutPalette.secondaryText)
                .frame(width: 110, height: PngCutMetrics.modeHeight)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier(mode == .lossless ? "modeShortcutLossless" : "modeShortcutBalanced")
    }
}

struct PngCutRadioChoice: View {
    let title: String
    let detail: String?
    let isSelected: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 9) {
                Circle()
                    .stroke(isSelected ? PngCutPalette.accent : PngCutPalette.dropStroke, lineWidth: 1.5)
                    .frame(width: 16, height: 16)
                    .overlay {
                        if isSelected {
                            Circle().fill(PngCutPalette.accent).padding(4)
                        }
                    }
                VStack(alignment: .leading, spacing: 2) {
                    Text(title).font(.system(size: 13, weight: .medium))
                    if let detail {
                        Text(detail).font(.system(size: 11)).foregroundStyle(PngCutPalette.secondaryText)
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? PngCutPalette.primaryText : PngCutPalette.secondaryText)
        .opacity(isEnabled ? 1 : 0.48)
        .disabled(!isEnabled)
    }
}

struct PngCutCheckbox: View {
    let title: String
    let isOn: Bool
    let isEnabled: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                RoundedRectangle(cornerRadius: 4, style: .continuous)
                    .fill(isOn ? PngCutPalette.accent : Color.white)
                    .overlay {
                        RoundedRectangle(cornerRadius: 4, style: .continuous)
                            .stroke(isOn ? PngCutPalette.accent : PngCutPalette.dropStroke, lineWidth: 1.5)
                        if isOn {
                            Image(systemName: "checkmark")
                                .font(.system(size: 10, weight: .bold))
                                .foregroundStyle(.white)
                        }
                    }
                    .frame(width: 16, height: 16)
                Text(title).font(.system(size: 13, weight: .medium))
                Spacer(minLength: 0)
            }
            .frame(minHeight: 32)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? PngCutPalette.primaryText : PngCutPalette.secondaryText)
        .opacity(isEnabled ? 1 : 0.48)
        .disabled(!isEnabled)
    }
}

struct PngCutWindowConfigurator: NSViewRepresentable {
    final class Coordinator {
        var hasAppliedWideTestSize = false
    }

    func makeCoordinator() -> Coordinator { Coordinator() }
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.backgroundColor = .white
            window.titleVisibility = .hidden
            window.titlebarAppearsTransparent = true
            window.isMovableByWindowBackground = true
            window.minSize = NSSize(width: PngCutMetrics.windowSize.width, height: PngCutMetrics.windowSize.height)
#if DEBUG
            if ProcessInfo.processInfo.arguments.contains("--ui-test-wide-window"),
               !context.coordinator.hasAppliedWideTestSize {
                window.setContentSize(NSSize(width: 1_280, height: 720))
                window.center()
                context.coordinator.hasAppliedWideTestSize = true
            }
#endif
        }
    }
}
