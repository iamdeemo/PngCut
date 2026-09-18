import AppKit
import OSLog
import SwiftUI
import UniformTypeIdentifiers

private let importInteractionLogger = Logger(subsystem: "com.pngcut.app", category: "import")

struct MainWindowView: View {
    @ObservedObject var model: AppModel
    @State private var isSettingsPresented = false
    @State private var isDropTargeted = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(spacing: 0) {
            PngCutWindowChrome()
            workspace
            bottomBar
        }
        .background(PngCutWindowConfigurator())
        .preferredColorScheme(.light)
        .onDrop(of: [.fileURL], isTargeted: $isDropTargeted) { providers in
            guard !model.isImportDecisionPresented else {
                return false
            }
            return acceptDrop(providers)
        }
        .overlay(importDecisionOverlay)
        // Keep the window chrome and modal hit regions in the same full-window coordinate space.
        .ignoresSafeArea(.container, edges: .top)
    }

    @ViewBuilder
    private var importDecisionOverlay: some View {
        if let decision = model.activeImportDecision {
            ImportDecisionOverlay(
                model: model,
                decision: decision,
                accent: PngCutPalette.accent
            )
            .transition(.opacity)
            .zIndex(10)
        }
    }

    private var workspace: some View {
        ZStack {
            homeOrTaskWorkspace
                .opacity(isSettingsPresented ? 0 : 1)
                .scaleEffect(isSettingsPresented && !reduceMotion ? 0.97 : 1)
                .allowsHitTesting(!isSettingsPresented)
                .animation(PngCutMotion.homeYield(reduceMotion: reduceMotion), value: isSettingsPresented)

            if isSettingsPresented {
                ZStack {
                    Color.clear
                        .accessibilityElement()
                        .accessibilityIdentifier("settingsSurface")
                    SettingsDrawerView(model: model, accent: PngCutPalette.accent)
                }
                    .transition(settingsSurfaceTransition)
                    .accessibilityElement(children: .contain)
                    .zIndex(1)
            }
        }
        .animation(PngCutMotion.settingsSurface(reduceMotion: reduceMotion), value: isSettingsPresented)
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .clipped()
    }

    private var homeOrTaskWorkspace: some View {
        Group {
            if model.tasks.isEmpty {
                EmptyDropView(
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
            .background(PngCutPalette.workspace)
    }

    private var settingsSurfaceTransition: AnyTransition {
        .asymmetric(
            insertion: .offset(y: 18).combined(with: .opacity),
            removal: .offset(y: 18).combined(with: .opacity)
        )
    }

    private var taskList: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack {
                VStack(alignment: .leading, spacing: 3) {
                    Text("任务列表")
                        .font(.system(size: 17, weight: .semibold))
                        .foregroundStyle(PngCutPalette.primaryText)
                        .accessibilityIdentifier("任务列表")
                    Text("\(model.tasks.count) 个文件")
                        .font(.system(size: 12, weight: .medium))
                        .foregroundStyle(PngCutPalette.secondaryText)
                }
                Spacer()
                Button("添加文件", action: chooseFiles)
                    .buttonStyle(.borderless)
                    .foregroundStyle(PngCutPalette.accent)
                    .disabled(model.isImportDecisionPresented)
                    .accessibilityIdentifier("addFilesButton")
            }

            ScrollView {
                LazyVStack(spacing: 8) {
                    ForEach(model.tasks) { task in
                        TaskRowView(task: task) {
                            model.retryFailed()
                        }
                    }
                }
                .padding(10)
            }
            .background(Color.white.opacity(0.72))
            .overlay {
                RoundedRectangle(cornerRadius: 12, style: .continuous)
                    .stroke(PngCutPalette.separator, lineWidth: 0.5)
            }
            .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))

            if model.skippedNonPNGCount > 0 {
                Text("\(model.skippedNonPNGCount) 个非图片文件未添加")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("skippedNonPNGCount")
            }
        }
        .padding(PngCutMetrics.contentPadding)
    }

    private var bottomBar: some View {
        HStack {
            PngCutModeSelector(model: model)
            Spacer()
            PngCutToolbarIconButton(assetName: "FolderOpen", label: "打开输出文件夹", isActive: false) {
                model.revealOutput()
            }
                .disabled(!model.hasCompletedOutput)
                .accessibilityIdentifier("revealOutputButton")
            PngCutToolbarIconButton(assetName: "Settings", label: "设置", isActive: isSettingsPresented) {
                toggleSettings()
            }
            .accessibilityIdentifier("settingsButton")
        }
        .padding(.horizontal, PngCutMetrics.contentPadding)
        .frame(maxWidth: .infinity)
        .frame(height: PngCutMetrics.toolbarHeight)
        .background(
            LinearGradient(
                colors: [PngCutPalette.toolbarTop, PngCutPalette.toolbarBottom],
                startPoint: .top,
                endPoint: .bottom
            )
        )
        .overlay(alignment: .top) {
            Rectangle().fill(PngCutPalette.separator).frame(height: 1)
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
        withAnimation(PngCutMotion.settingsSurface(reduceMotion: reduceMotion)) {
            isSettingsPresented.toggle()
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
    let isTargeted: Bool
    let skippedNonImageCount: Int
    let isImportDecisionPresented: Bool
    let chooseFiles: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        GeometryReader { geometry in
            dropZone
                .frame(
                    width: geometry.size.width * PngCutMetrics.dropZoneWidthRatio,
                    height: geometry.size.height * PngCutMetrics.dropZoneHeightRatio
                )
                .frame(maxWidth: .infinity, maxHeight: .infinity)
        }
    }

    private var dropZone: some View {
        VStack(spacing: 13) {
            Image("ImageAdd")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: PngCutMetrics.dropIconSize, height: PngCutMetrics.dropIconSize)
                .foregroundStyle(PngCutPalette.accent)
                .accessibilityHidden(true)
                .frame(width: 80, height: 80)
            Text("拖入图片或文件夹")
                .font(.system(size: 18, weight: .semibold))
                .foregroundStyle(PngCutPalette.primaryText)
            Button("选择文件", action: chooseFiles)
                .buttonStyle(PngCutPrimaryButtonStyle())
                .disabled(isImportDecisionPresented)
                .accessibilityIdentifier("chooseFilesButton")
            HStack(spacing: 8) {
                formatTag("PNG", identifier: "formatPNG")
                formatTag("JPG", identifier: "formatJPG")
                formatTag("GIF", identifier: "formatGIF")
            }
            if skippedNonImageCount > 0 {
                Text("\(skippedNonImageCount) 个非图片文件未添加")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                    .accessibilityIdentifier("skippedNonPNGCount")
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(
            ZStack {
                RoundedRectangle(cornerRadius: PngCutMetrics.dropZoneCornerRadius, style: .continuous)
                    .fill(isTargeted ? PngCutPalette.accent.opacity(0.07) : Color.clear)
                    .animation(PngCutMotion.controlFeedback(reduceMotion: reduceMotion), value: isTargeted)
                Color.clear
                    .accessibilityIdentifier("figmaDropZone")
            }
        )
        .overlay {
            RoundedRectangle(cornerRadius: PngCutMetrics.dropZoneCornerRadius, style: .continuous)
                .stroke(
                    isTargeted ? PngCutPalette.accent.opacity(0.68) : PngCutPalette.dropStroke,
                    style: StrokeStyle(lineWidth: 1.5, dash: [7, 5])
                )
                .animation(PngCutMotion.controlFeedback(reduceMotion: reduceMotion), value: isTargeted)
        }
    }

    private func formatTag(_ title: String, identifier: String) -> some View {
        Text(title)
            .font(.system(size: 11, weight: .semibold))
            .foregroundStyle(PngCutPalette.secondaryText)
            .padding(.horizontal, 9)
            .frame(height: 24)
            .background(Color.black.opacity(0.05))
            .clipShape(Capsule())
            .accessibilityIdentifier(identifier)
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
            .buttonStyle(PngCutSecondaryButtonStyle())
            .accessibilityIdentifier("importDecisionCompress")

            Button("转 GIF") {
                model.resolveSequenceDecision(convertSequence: true)
            }
            .buttonStyle(PngCutPrimaryButtonStyle())
            .accessibilityIdentifier("importDecisionConvert")

        case .noSequenceDetected:
            Button("不压缩") {
                model.resolveNoSequenceDecision(compressInstead: false)
            }
            .buttonStyle(PngCutSecondaryButtonStyle())
            .accessibilityIdentifier("importDecisionDecline")

            Button("常规压缩") {
                model.resolveNoSequenceDecision(compressInstead: true)
            }
            .buttonStyle(PngCutPrimaryButtonStyle())
            .accessibilityIdentifier("importDecisionCompress")

        case .noSequenceNotice:
            Button("好") {
                model.dismissNoSequenceNotice()
            }
            .buttonStyle(PngCutPrimaryButtonStyle())
            .accessibilityIdentifier("importDecisionAcknowledge")
        }
    }
}
