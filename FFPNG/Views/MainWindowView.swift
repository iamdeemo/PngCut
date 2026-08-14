import AppKit
import SwiftUI
import UniformTypeIdentifiers

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
    }

    private var workspace: some View {
        ZStack {
            Group {
                if model.tasks.isEmpty {
                    EmptyDropView(
                        accent: accent,
                        isTargeted: isDropTargeted,
                        skippedNonPNGCount: model.skippedNonPNGCount
                    ) {
                        chooseFiles()
                    }
                } else {
                    taskList
                }
            }
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .background(Color(nsColor: .windowBackgroundColor))

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
                Text("\(model.skippedNonPNGCount) 个非 PNG 文件未添加")
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
        panel.title = "选择 PNG 文件或文件夹"
        panel.message = "请选择要压缩的 PNG 文件或文件夹"
        panel.prompt = "选择"
        panel.canChooseFiles = true
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = true
        panel.allowedContentTypes = [.png, .folder]
        panel.begin { response in
            guard response == .OK else { return }
            model.add(urls: panel.urls)
        }
    }

    private func toggleSettings() {
        withAnimation(.default) {
            isSettingsPresented.toggle()
        }
    }

    private func dismissSettings() {
        withAnimation(.default) {
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
}

private struct EmptyDropView: View {
    let accent: Color
    let isTargeted: Bool
    let skippedNonPNGCount: Int
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
            Text("拖入 PNG 文件或文件夹")
                .font(.system(size: 15, weight: .medium))
                .foregroundStyle(.primary)
            Button("选择文件", action: chooseFiles)
                .buttonStyle(PrimaryButtonStyle(accent: accent))
                .accessibilityIdentifier("chooseFilesButton")
            if skippedNonPNGCount > 0 {
                Text("\(skippedNonPNGCount) 个非 PNG 文件未添加")
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
                .frame(width: 34, height: 34)
        }
        .buttonStyle(.plain)
        .frame(width: 34, height: 34)
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
        HStack(spacing: 0) {
            modeButton(.lossless)
            Rectangle()
                .fill(Color.black.opacity(0.08))
                .frame(width: 1, height: 16)
            modeButton(.balanced)
        }
        .padding(2)
        .background(Color.black.opacity(0.045))
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .accessibilityIdentifier("compressionModeShortcut")
    }

    private func modeButton(_ mode: CompressionMode) -> some View {
        let enabled = mode == .lossless || model.isTinifyValidated
        let selected = model.settings.mode == mode
        return Button {
            model.setCompressionMode(mode)
        } label: {
            Text(mode.title)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(selected ? Color.white : (enabled ? Color.primary : Color.secondary.opacity(0.5)))
                .frame(minWidth: 36)
                .padding(.vertical, 5)
                .background(selected ? accent : Color.clear)
                .clipShape(RoundedRectangle(cornerRadius: 4))
        }
        .buttonStyle(.plain)
        .disabled(!enabled)
        .accessibilityIdentifier(mode == .lossless ? "modeShortcutLossless" : "modeShortcutBalanced")
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
            .clipShape(RoundedRectangle(cornerRadius: 5))
    }
}
