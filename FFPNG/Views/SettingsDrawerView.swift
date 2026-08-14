import AppKit
import SwiftUI

struct SettingsDrawerView: View {
    @ObservedObject var model: AppModel
    let accent: Color

    var body: some View {
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
                radio(title: "平衡", isSelected: model.settings.mode == .balanced, isEnabled: model.isTinifyValidated) {
                    model.setCompressionMode(.balanced)
                }
                .accessibilityIdentifier("balancedMode")

            }

            VStack(alignment: .leading, spacing: 8) {
                TextField("Tinify API Key", text: $model.apiKey)
                    .textFieldStyle(.roundedBorder)
                    .accessibilityIdentifier("tinifyAPIKeyField")
                HStack {
                    Button(model.isTinifyValidated ? "重新验证" : "验证") {
                        model.validateTinifyKey()
                    }
                        .buttonStyle(DrawerButtonStyle(accent: accent))
                        .accessibilityIdentifier("validateTinifyKeyButton")
                    if let message = model.validationMessage {
                        Text(message)
                            .font(.system(size: 11))
                            .foregroundStyle(.secondary)
                    }
                }
                Text("平衡模式会将图片上传至 Tinify，并消耗你的账户额度。")
                    .font(.system(size: 10))
                    .foregroundStyle(.secondary)
            }
        }
        .padding(16)
        .background(Color(nsColor: .controlBackgroundColor))
        .overlay(alignment: .top) { Divider() }
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
                Spacer()
            }
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .foregroundStyle(isEnabled ? Color.primary : Color.secondary.opacity(0.5))
        .disabled(!isEnabled)
    }

    private func chooseOutputDirectory() {
        let panel = NSOpenPanel()
        panel.title = "选择输出文件夹"
        panel.message = "请选择压缩后的 PNG 保存位置"
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

private struct DrawerButtonStyle: ButtonStyle {
    let accent: Color

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .font(.system(size: 11, weight: .medium))
            .foregroundStyle(.white)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(accent.opacity(configuration.isPressed ? 0.75 : 1))
            .clipShape(RoundedRectangle(cornerRadius: 4))
    }
}
