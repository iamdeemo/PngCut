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

            settingsSection("PNG 压缩方式") {
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
        }
        .padding(16)
        .background(AppPalette.drawerColor)
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
        panel.message = "请选择压缩后的 PNG/JPG 保存位置"
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
