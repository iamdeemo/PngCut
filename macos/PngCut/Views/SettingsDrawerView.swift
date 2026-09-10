import AppKit
import SwiftUI

struct SettingsDrawerView: View {
    @ObservedObject var model: AppModel
    let accent: Color
    @State private var customFrameRateText = ""
    @State private var customFrameRateError: String?

    var body: some View {
        ScrollView(showsIndicators: false) {
            VStack(alignment: .leading, spacing: 24) {
                outputSettings
                settingsDivider
                compressionSettings
                settingsDivider
                gifSettings
            }
            .frame(maxWidth: 620, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 24)
            .padding(.vertical, 28)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(PngCutPalette.workspace)
        .onAppear {
            if case let .custom(frameRate) = model.settings.gif.frameRate {
                customFrameRateText = String(frameRate)
            }
        }
    }

    private var settingsDivider: some View {
        Rectangle()
            .fill(PngCutPalette.separator)
            .frame(height: 1)
    }

    private var outputSettings: some View {
        settingsSection("保存位置") {
            HStack(alignment: .top, spacing: 12) {
                PngCutRadioChoice(
                    title: "原文件旁边",
                    detail: nil,
                    isSelected: model.settings.outputPolicy == .adjacent,
                    isEnabled: true
                ) {
                    model.settings.outputPolicy = .adjacent
                }
                PngCutRadioChoice(
                    title: "指定输出文件夹",
                    detail: nil,
                    isSelected: model.settings.outputPolicy == .customDirectory,
                    isEnabled: true
                ) {
                    chooseOutputDirectory()
                }
                PngCutRadioChoice(
                    title: "覆盖原文件",
                    detail: nil,
                    isSelected: model.settings.outputPolicy == .overwrite,
                    isEnabled: true
                ) {
                    model.settings.outputPolicy = .overwrite
                }
            }
        }
    }

    private var compressionSettings: some View {
        settingsSection("压缩方式") {
            HStack(alignment: .top, spacing: 12) {
                PngCutRadioChoice(
                    title: "无损",
                    detail: "文件较大，质量完整保留",
                    isSelected: model.settings.mode == .lossless,
                    isEnabled: true
                ) {
                    model.setCompressionMode(.lossless)
                }
                PngCutRadioChoice(
                    title: "平衡",
                    detail: "文件较小，轻微质量损失",
                    isSelected: model.settings.mode == .balanced,
                    isEnabled: true
                ) {
                    model.setCompressionMode(.balanced)
                }
                .accessibilityIdentifier("balancedMode")
            }
            Text("本地有损压缩")
                .font(.system(size: 11))
                .foregroundStyle(PngCutPalette.secondaryText)
        }
    }

    private var gifSettings: some View {
        settingsSection("GIF 设置") {
            PngCutCheckbox(
                title: "PNG 序列转 GIF",
                isOn: model.settings.gif.isPNGSequenceConversionEnabled,
                isEnabled: true
            ) {
                updateGIFSettings { $0.isPNGSequenceConversionEnabled.toggle() }
            }
            .accessibilityRepresentation {
                Toggle("PNG 序列转 GIF", isOn: pngSequenceGIFEnabled)
                    .accessibilityIdentifier("pngSequenceGIFEnabled")
            }

            VStack(alignment: .leading, spacing: 6) {
                Text("帧率")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PngCutPalette.secondaryText)
                frameRateControls
            }
            .disabled(!model.settings.gif.isPNGSequenceConversionEnabled)

            VStack(alignment: .leading, spacing: 6) {
                Text("循环")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(PngCutPalette.secondaryText)
                HStack(spacing: 12) {
                    gifChoice(
                        title: "无限循环",
                        identifier: "gifLoopForever",
                        isSelected: model.settings.gif.loop == .forever
                    ) {
                        updateGIFSettings { $0.loop = .forever }
                    }
                    gifChoice(
                        title: "播放一次",
                        identifier: "gifLoopOnce",
                        isSelected: model.settings.gif.loop == .once
                    ) {
                        updateGIFSettings { $0.loop = .once }
                    }
                }
            }
            .disabled(!model.settings.gif.isPNGSequenceConversionEnabled)

            if let customFrameRateError {
                Text(customFrameRateError)
                    .font(.system(size: 11))
                    .foregroundStyle(.red)
            }
        }
    }

    private var frameRateControls: some View {
        HStack(alignment: .center, spacing: 12) {
            HStack(spacing: 8) {
                ForEach(GIFFrameRate.presetValues, id: \.self) { frameRate in
                    frameRateButton(for: frameRate)
                }
            }
            customFrameRateControl
        }
    }

    private func frameRateButton(for frameRate: Int) -> some View {
        gifChoice(
            title: "\(frameRate)",
            identifier: "gifFrameRate\(frameRate)",
            isSelected: model.settings.gif.frameRate == .preset(frameRate)
        ) {
            updateGIFSettings { $0.frameRate = .preset(frameRate) }
            customFrameRateError = nil
        }
        .frame(width: 58)
    }

    private var customFrameRateControl: some View {
        HStack(spacing: 8) {
            gifChoice(
                title: "自定义",
                identifier: "gifFrameRateCustom",
                isSelected: isCustomFrameRateSelected,
                action: commitCustomFrameRate
            )
            .frame(width: 88)

            TextField("1–50", text: $customFrameRateText)
                .textFieldStyle(.roundedBorder)
                .frame(width: 58)
                .accessibilityIdentifier("gifCustomFrameRate")
                .onSubmit(commitCustomFrameRate)
                .disabled(!model.settings.gif.isPNGSequenceConversionEnabled)
                .opacity(gifControlsOpacity)
        }
    }

    private func gifChoice(
        title: String,
        identifier: String,
        isSelected: Bool,
        action: @escaping () -> Void
    ) -> some View {
        PngCutRadioChoice(
            title: title,
            detail: nil,
            isSelected: isSelected,
            isEnabled: model.settings.gif.isPNGSequenceConversionEnabled,
            action: action
        )
        .accessibilityIdentifier(identifier)
    }

    private var gifControlsOpacity: Double {
        model.settings.gif.isPNGSequenceConversionEnabled ? 1 : 0.48
    }

    private func settingsSection<Content: View>(
        _ title: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(title)
                .font(.system(size: 17, weight: .semibold))
                .foregroundStyle(PngCutPalette.primaryText)
            content()
        }
        .frame(maxWidth: .infinity, alignment: .leading)
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
