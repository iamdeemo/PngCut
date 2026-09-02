import AppKit
import SwiftUI

struct SettingsDrawerView: View {
    @ObservedObject var model: AppModel
    let accent: Color
    @State private var customFrameRateText = ""
    @State private var customFrameRateError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 14) {
                settingsSection("保存位置") {
                    radio(title: "原文件旁边", isSelected: model.settings.outputPolicy == .adjacent) {
                        model.settings.outputPolicy = .adjacent
                    }
                    radio(title: "指定输出文件夹", isSelected: model.settings.outputPolicy == .customDirectory) {
                        chooseOutputDirectory()
                    }
                    radio(title: "覆盖原文件", isSelected: model.settings.outputPolicy == .overwrite) {
                        model.settings.outputPolicy = .overwrite
                    }
                }

                Divider()

                settingsSection("压缩方式") {
                    radio(title: "无损", isSelected: model.settings.mode == .lossless) {
                        model.setCompressionMode(.lossless)
                    }
                    radio(title: "平衡", isSelected: model.settings.mode == .balanced) {
                        model.setCompressionMode(.balanced)
                    }
                    .accessibilityIdentifier("balancedMode")
                    Text("本地有损压缩")
                        .font(.system(size: 10))
                        .foregroundStyle(.secondary)
                }

                Divider()

                settingsSection("GIF 设置") {
                    Toggle("PNG 序列转 GIF", isOn: pngSequenceGIFEnabled)
                        .toggleStyle(.checkbox)
                        .font(.system(size: 12))
                        .accessibilityIdentifier("pngSequenceGIFEnabled")

                    Text("帧率")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 8) {
                        ForEach(GIFFrameRate.presetValues, id: \.self) { frameRate in
                            radio(
                                title: "\(frameRate) 帧/秒",
                                isSelected: model.settings.gif.frameRate == .preset(frameRate),
                                expandsToFill: false
                            ) {
                                updateGIFSettings { $0.frameRate = .preset(frameRate) }
                                customFrameRateError = nil
                            }
                            .accessibilityIdentifier("gifFrameRate\(frameRate)")
                        }
                        radio(
                            title: "自定义",
                            isSelected: isCustomFrameRateSelected,
                            expandsToFill: false,
                            action: commitCustomFrameRate
                        )
                        .accessibilityIdentifier("gifFrameRateCustom")

                        TextField("1–50", text: $customFrameRateText)
                            .textFieldStyle(.roundedBorder)
                            .frame(width: 58)
                            .accessibilityIdentifier("gifCustomFrameRate")
                            .onSubmit(commitCustomFrameRate)
                        Spacer()
                    }
                    if let customFrameRateError {
                        Text(customFrameRateError)
                            .font(.system(size: 10))
                            .foregroundStyle(.red)
                    }

                    Text("循环")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                    HStack(spacing: 18) {
                        radio(
                            title: "无限循环",
                            isSelected: model.settings.gif.loop == .forever,
                            expandsToFill: false
                        ) {
                            updateGIFSettings { $0.loop = .forever }
                        }
                        .accessibilityIdentifier("gifLoopForever")
                        radio(
                            title: "播放一次",
                            isSelected: model.settings.gif.loop == .once,
                            expandsToFill: false
                        ) {
                            updateGIFSettings { $0.loop = .once }
                        }
                        .accessibilityIdentifier("gifLoopOnce")
                        Spacer()
                    }
                }
            }
            .padding(16)
        }
        .frame(maxHeight: 340)
        .background(AppPalette.drawerColor)
        .overlay(alignment: .top) { Divider() }
        .onAppear {
            if case let .custom(frameRate) = model.settings.gif.frameRate {
                customFrameRateText = String(frameRate)
            }
        }
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .semibold))
            content()
        }
    }

    private func radio(
        title: String,
        isSelected: Bool,
        isEnabled: Bool = true,
        expandsToFill: Bool = true,
        action: @escaping () -> Void
    ) -> some View {
        Button(action: action) {
            HStack(spacing: 8) {
                Circle()
                    .stroke(isSelected ? accent : Color.secondary.opacity(0.55), lineWidth: 1.5)
                    .frame(width: 14, height: 14)
                    .overlay {
                        if isSelected {
                            Circle().fill(accent).padding(3)
                        }
                }
                Text(title)
                    .font(.system(size: 12))
                if expandsToFill {
                    Spacer()
                }
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.5))
        .disabled(!isEnabled)
    }

    private var pngSequenceGIFEnabled: Binding<Bool> {
        Binding(
            get: { model.settings.gif.isPNGSequenceConversionEnabled },
            set: { isEnabled in
                updateGIFSettings { $0.isPNGSequenceConversionEnabled = isEnabled }
            }
        )
    }

    private var isCustomFrameRateSelected: Bool {
        if case .custom = model.settings.gif.frameRate {
            return true
        }
        return false
    }

    private func commitCustomFrameRate() {
        guard let value = Int(customFrameRateText),
              let frameRate = GIFFrameRate.custom(validating: value) else {
            customFrameRateError = "请输入 1–50 的整数"
            return
        }
        updateGIFSettings { $0.frameRate = frameRate }
        customFrameRateError = nil
    }

    private func updateGIFSettings(_ update: (inout GIFSettings) -> Void) {
        var settings = model.settings
        update(&settings.gif)
        model.settings = settings
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择输出文件夹"
        panel.message = "请选择压缩后的 PNG/JPG/GIF 保存位置"
        panel.prompt = "选择"
        panel.canChooseFiles = false
        panel.canChooseDirectories = true
        panel.allowsMultipleSelection = false
        panel.begin { response in
            guard response == .OK, let url = panel.url else { return }
            model.settings.outputPolicy = .customDirectory
            model.settings.customOutputDirectory = url
        }
    }
}
