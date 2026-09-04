import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let importInteractionLogger = Logger(subsystem: "com.pngcut.app", category: "import")

enum AppPalette {
    static let workspace = NSColor(
        calibratedRed: 244 / 255,
        green: 244 / 255,
        blue: 244 / 255,
        alpha: 1
    )
    static let workspaceColor = Color(nsColor: workspace)
    static let drawer = NSColor(
        calibratedRed: 252 / 255,
        green: 252 / 255,
        blue: 252 / 255,
        alpha: 1
    )
    static let drawerColor = Color(nsColor: drawer)
}

enum AppControlMetrics {
    static let buttonCornerRadius: CGFloat = 5
    static let iconHitSize: CGFloat = 44
    static let modeSegmentWidth: CGFloat = 64
    static let modeVisualHeight: CGFloat = 30
}

private enum AppMotion {
    static var responsive: Animation {
        if #available(macOS 14.0, *) {
            return .smooth(duration: 0.2, extraBounce: 0)
        }
        return .easeInOut(duration: 0.2)
    }
}

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @State private var isSettingsPresented = false
    @State private var isDropTargeted = false

    private let accent = Color(red: 36 / 255, green: 130 / 255, blue: 241 / 255)

    var body: some View {
        VStack(spacing: 0) {
            workspace
            bottomBar
        }
        .background(Color.white)
        .background(WindowAppearanceConfigurator())
        .preferredColorScheme(.light)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard !model.isImportDecisionPresented else {
                return false
            }
            return acceptDrop(providers)
        }
        .overlay(importDecisionOverlay)
    }

    @ViewBuilder
    private var importDecisionOverlay: some View {
        if let decision = model.activeImportDecision {
            ImportDecisionOverlay(
                model: model,
                decision: decision,
                accent: accent
            )
            .transition(.opacity)
            .zIndex(10)
        }
    }

    private var workspace: some View {
        ZStack {
            Group {
                if model.tasks.isEmpty {
                    EmptyDropView(
                        accent: accent,
                        isTargeted: isDropTargeted,
                        skippedNonImageCount: model.skippedNonPNGCount,
                        isImportDecisionPresented: model.isImportDecisionPresented
                    ) {
                        chooseFiles()
                    }
                } else {
                    taskList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(AppPalette.workspaceColor)

            if isSettingsPresented {
                ZStack(alignment: .bottom) {
                Button {
                    dismissSettings()
                } label: {
                    Rectangle()
                        .fill(Color.black.opacity(0.001))
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .accessibilityIdentifier("settingsDismissArea")

                SettingsDrawerView(model: model, accent: accent)
                    .zIndex(1)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity)
                .transition(.move(edge: .bottom))
                .zIndex(1)
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                Text("\(model.tasks.count) 个文件")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(.primary)
                Spacer()
                Button("添加文件", action: chooseFiles)
                    .buttonStyle(.borderless)
                    .foregroundStyle(accent)
                    .disabled(model.isImportDecisionPresented)
                    .accessibilityIdentifier("addFilesButton")
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.tasks) { task in
                        TaskRowView(task: task, accent: accent) {
                            model.retryFailed()
                        }
                    }
                }
            }

            if model.skippedNonPNGCount > 0 {
                Text("\(model.skippedNonPNGCount) 个非图片文件未添加")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("skippedNonPNGCount")
            }
        }
        .padding(18)
    }

    private var bottomBar: some View {
        HStack {
            CompressionModeShortcut(model: model, accent: accent)
            Spacer()
            IconButton(assetName: "FolderOpen", label: "打开输出文件夹") {
                model.revealOutput()
            }
                .disabled(!model.hasCompletedOutput)
                .accessibilityIdentifier("revealOutputButton")
            IconButton(assetName: "Settings", label: "设置", isActive: isSettingsPresented) {
                toggleSettings()
            }
            .accessibilityIdentifier("settingsButton")
        }
        .padding(.horizontal, 14)
        .frame(maxWidth: .infinity)
        .frame(height: 52)
        .background(Color.white.opacity(0.92))
        .overlay(alignment: .top) {
            Divider()
        }
    }

    private func chooseFiles() {
        guard !model.isImportDecisionPresented else {
            return
        }
        importInteractionLogger.notice("Import picker opened")
        let panel = NSOpenPanel()
        panel.title = "选择 PNG/JPG/GIF 文件或文件夹"
        panel.message = "请选择要压缩的 PNG/JPG/GIF 文件或文件夹"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .folder]
        panel.begin { response in
            guard response == .OK else {
                importInteractionLogger.notice("Import picker cancelled")
                return
            }
            let extensions = Set(panel.urls.map { $0.pathExtension.lowercased() })
                .sorted()
                .joined(separator: ",")
            importInteractionLogger.notice(
                "Import picker accepted: selected=\(panel.urls.count, privacy: .public), extensions=\(extensions, privacy: .public)"
            )
            guard !model.isImportDecisionPresented else {
                return
            }
            model.add(urls: panel.urls)
        }
    }

    private func toggleSettings() {
        withAnimation(AppMotion.responsive) {
            isSettingsPresented.toggle()
        }
    }

    private func dismissSettings() {
        withAnimation(AppMotion.responsive) {
            isSettingsPresented = false
        }
    }

    private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
        guard !model.isImportDecisionPresented else {
            return false
        }
        importInteractionLogger.notice("Import drop accepted: providers=\(providers.count, privacy: .public)")
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else {
                    importInteractionLogger.error("Import drop provider did not supply a file URL")
                    return
                }
                Task { @MainActor in
                    guard !model.isImportDecisionPresented else {
                        return
                    }
                    importInteractionLogger.notice("Import drop URL decoded: extension=\(url.pathExtension.lowercased(), privacy: .public)")
                    model.add(urls: [url])
                }
            }
        }
        return !providers.isEmpty
    }

}

private struct EmptyDropView: View {
    let accent: Color
    let isTargeted: Bool
    let skippedNonImageCount: Int
    let isImportDecisionPresented: Bool
    let chooseFiles: () -> Void

    var body: some View {
        VStack(spacing: 15) {
            Image("ImageAdd")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 48, height: 48)
                .foregroundStyle(accent)
                .accessibilityHidden(true)
            Text("拖入 PNG/JPG/GIF 文件或文件夹")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
            Button("选择文件", action: chooseFiles)
                .buttonStyle(PrimaryButtonStyle(accent: accent))
                .disabled(isImportDecisionPresented)
                .accessibilityIdentifier("chooseFilesButton")
            if skippedNonImageCount > 0 {
                Text("\(skippedNonImageCount) 个非图片文件未添加")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("skippedNonPNGCount")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(isTargeted ? accent.opacity(0.07) : .clear)
    }
}

private struct ImportDecisionOverlay: View {
    @ObservedObject var model: AppModel
    let decision: ImportDecision
    let accent: Color

    var body: some View {
        ZStack {
            Color.black.opacity(0.28)
                .ignoresSafeArea()
                .contentShape(Rectangle())

            VStack(alignment: .leading, spacing: 16) {
                Text(title)
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundStyle(.primary)

                Text(message)
                    .font(.system(size: 13))
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityIdentifier(message)

                HStack(spacing: 10) {
                    Spacer()
                    buttons
                }
            }
            .padding(22)
            .frame(width: 360)
            .background(Color.white)
            .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
            .shadow(color: .black.opacity(0.18), radius: 18, y: 8)
        }
        .accessibilityIdentifier("importDecisionOverlay")
        .accessibilityElement(children: .contain)
    }

    private var title: String {
        switch decision {
        case .sequenceDetected:
            "发现 PNG 序列"
        case .noSequenceDetected:
            "未发现 PNG 序列"
        case .noSequenceNotice:
            "无法转 GIF"
        }
    }

    private var message: String {
        switch decision {
        case let .sequenceDetected(resolution):
            resolution.convertMessage
        case .noSequenceDetected:
            "是否按常规方式压缩当前文件？"
        case .noSequenceNotice:
            "当前文件夹没有 PNG 序列，无法转 GIF"
        }
    }

    @ViewBuilder
    private var buttons: some View {
        switch decision {
        case .sequenceDetected:
            Button("常规压缩") {
                model.resolveSequenceDecision(convertSequence: false)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("importDecisionCompress")

            Button("转 GIF") {
                model.resolveSequenceDecision(convertSequence: true)
            }
            .buttonStyle(PrimaryButtonStyle(accent: accent))
            .accessibilityIdentifier("importDecisionConvert")

        case .noSequenceDetected:
            Button("不压缩") {
                model.resolveNoSequenceDecision(compressInstead: false)
            }
            .buttonStyle(.bordered)
            .accessibilityIdentifier("importDecisionDecline")

            Button("常规压缩") {
                model.resolveNoSequenceDecision(compressInstead: true)
            }
            .buttonStyle(PrimaryButtonStyle(accent: accent))
            .accessibilityIdentifier("importDecisionCompress")

        case .noSequenceNotice:
            Button("好") {
                model.dismissNoSequenceNotice()
            }
            .buttonStyle(PrimaryButtonStyle(accent: accent))
            .accessibilityIdentifier("importDecisionAcknowledge")
        }
    }
}

private struct IconButton: View {
    let assetName: String
    let label: String
    var isActive = false
    let action: () -> Void
    @State private var isHovered = false

    private let accent = Color(red: 36 / 255, green: 130 / 255, blue: 241 / 255)

    var body: some View {
        Button(action: action) {
            Image(assetName)
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 20, height: 20)
                .frame(
                    width: AppControlMetrics.iconHitSize,
                    height: AppControlMetrics.iconHitSize
                )
                .contentShape(
                    RoundedRectangle(
                        cornerRadius: AppControlMetrics.buttonCornerRadius,
                        style: .continuous
                    )
                )
        }
        .buttonStyle(.plain)
        .frame(
            width: AppControlMetrics.iconHitSize,
            height: AppControlMetrics.iconHitSize
        )
        .foregroundStyle(isHovered || isActive ? accent : Color(red: 0.15, green: 0.19, blue: 0.23))
        .onHover { isHovered = $0 }
        .accessibilityLabel(label)
    }
}

private struct WindowAppearanceConfigurator: NSViewRepresentable {
    func makeNSView(context: Context) -> NSView { NSView() }

    func updateNSView(_ view: NSView, context: Context) {
        DispatchQueue.main.async {
            guard let window = view.window else { return }
            window.backgroundColor = .white
            window.titlebarAppearsTransparent = true
        }
    }
}

private struct CompressionModeShortcut: View {
    @ObservedObject var model: AppModel
    let accent: Color

    var body: some View {
        ZStack {
            RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                .fill(Color.black.opacity(0.045))
                .frame(width: controlWidth, height: AppControlMetrics.modeVisualHeight)

            GeometryReader { geometry in
                RoundedRectangle(cornerRadius: cornerRadius, style: .continuous)
                    .fill(accent)
                    .frame(width: geometry.size.width / 2, height: geometry.size.height)
                    .offset(x: model.settings.mode == .lossless ? 0 : geometry.size.width / 2)
                    .accessibilityIdentifier("modeSlider")
            }
            .frame(width: controlWidth, height: AppControlMetrics.modeVisualHeight)

            HStack(spacing: 0) {
                modeButton(.lossless)
                modeButton(.balanced)
            }
            .accessibilityElement(children: .contain)
        }
        .frame(width: controlWidth, height: AppControlMetrics.iconHitSize)
        .animation(AppMotion.responsive, value: model.settings.mode)
    }

    private func modeButton(_ mode: CompressionMode) -> some View {
        let selected = model.settings.mode == mode
        return Button {
            model.setCompressionMode(mode)
        } label: {
            Text(mode.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selected ? Color.white : Color.primary)
                .frame(
                    width: AppControlMetrics.modeSegmentWidth,
                    height: AppControlMetrics.iconHitSize
                )
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .frame(
            width: AppControlMetrics.modeSegmentWidth,
            height: AppControlMetrics.iconHitSize
        )
        .accessibilityIdentifier(mode == .lossless ? "modeShortcutLossless" : "modeShortcutBalanced")
    }

    private var controlWidth: CGFloat {
        AppControlMetrics.modeSegmentWidth * 2
    }

    private var cornerRadius: CGFloat {
        AppControlMetrics.buttonCornerRadius
    }
}

private struct PrimaryButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 13, weight: .medium))
            .padding(.horizontal, 16)
            .padding(.vertical, 7)
            .foregroundStyle(.white)
            .background(accent.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(
                RoundedRectangle(
                    cornerRadius: AppControlMetrics.buttonCornerRadius,
                    style: .continuous
                )
            )
    }
}
