import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
            acceptDrop(providers)
        }
        .alert(item: importPromptBinding) { prompt in
            switch prompt {
            case .convertSequences:
                Alert(
                    title: Text("发现 PNG 序列"),
                    message: Text(prompt.message),
                    primaryButton: .default(Text("转 GIF")) {
                        model.resolvePendingImport(convertSequence: true)
                    },
                    secondaryButton: .cancel(Text("常规压缩")) {
                        model.resolvePendingImport(convertSequence: false)
                    }
                )
            case .compressWithoutSequence:
                Alert(
                    title: Text("未发现 PNG 序列"),
                    message: Text("是否按常规方式压缩当前文件？"),
                    primaryButton: .default(Text("压缩")) {
                        model.resolvePendingImport(compressInstead: true)
                    },
                    secondaryButton: .cancel(Text("不压缩")) {
                        model.resolvePendingImport(compressInstead: false)
                    }
                )
            }
        }
        .alert(item: importNoticeBinding) { notice in
            Alert(
                title: Text("无法转 GIF"),
                message: Text(notice.message),
                dismissButton: .default(Text("好")) {
                    model.dismissImportNotice()
                }
            )
        }
    }

    private var workspace: some View {
        ZStack {
            Group {
                if model.tasks.isEmpty {
                    EmptyDropView(
                        accent: accent,
                        isTargeted: isDropTargeted,
                        skippedNonImageCount: model.skippedNonPNGCount
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
        let panel = NSOpenPanel()
        panel.title = "选择 PNG/JPG/GIF 文件或文件夹"
        panel.message = "请选择要压缩的 PNG/JPG/GIF 文件或文件夹"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .jpeg, .gif, .folder]
        panel.begin { response in
            guard response == .OK else { return }
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
        for provider in providers {
            provider.loadItem(forTypeIdentifier: UTType.fileURL.identifier, options: nil) { item, _ in
                let url: URL?
                if let data = item as? Data {
                    url = URL(dataRepresentation: data, relativeTo: nil)
                } else {
                    url = item as? URL
                }
                guard let url else { return }
                Task { @MainActor in
                    model.add(urls: [url])
                }
            }
        }
        return !providers.isEmpty
    }

    private var importPromptBinding: Binding<ImportPrompt?> {
        Binding(
            get: { model.pendingImportPrompt },
            set: { prompt in
                guard prompt == nil else { return }
                switch model.pendingImportPrompt {
                case .convertSequences:
                    model.resolvePendingImport(convertSequence: false)
                case .compressWithoutSequence:
                    model.resolvePendingImport(compressInstead: false)
                case nil:
                    break
                }
            }
        )
    }

    private var importNoticeBinding: Binding<ImportNotice?> {
        Binding(
            get: { model.importNotice },
            set: { notice in
                if notice == nil {
                    model.dismissImportNotice()
                }
            }
        )
    }
}

private struct EmptyDropView: View {
    let accent: Color
    let isTargeted: Bool
    let skippedNonImageCount: Int
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
