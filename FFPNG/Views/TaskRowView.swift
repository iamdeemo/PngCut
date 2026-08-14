import SwiftUI

struct TaskRowView: View {
    let task: CompressionTask
    let accent: Color
    let retry: () -> Void

    var body: some View {
        HStack(spacing: 12) {
            Image("ImageFile")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.sourceURL.lastPathComponent)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                taskDetail
                if task.state == .processing {
                    ProgressView(value: task.progress)
                        .tint(accent)
                        .frame(maxWidth: .infinity)
                }
            }

            Spacer(minLength: 10)
            taskState
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .background(Color.white)
        .overlay {
            RoundedRectangle(cornerRadius: 7)
                .stroke(Color(nsColor: .separatorColor), lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 7))
        .accessibilityElement(children: .contain)
    }

    @ViewBuilder
    private var taskDetail: some View {
        switch task.state {
        case let .failed(error):
            Text(message(for: error))
                .font(.system(size: 11))
                .foregroundStyle(.red)
                .lineLimit(2)
        case .completed:
            Text(sizeSummary)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
                .lineLimit(1)
        case .queued, .processing:
            Text(sourceSize)
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        }
    }

    @ViewBuilder
    private var taskState: some View {
        switch task.state {
        case .queued:
            Text("等待")
                .font(.system(size: 11))
                .foregroundStyle(.secondary)
        case .processing:
            Text("处理中")
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accent)
        case .completed:
            VStack(alignment: .trailing, spacing: 2) {
                Text("节省 \(savingsPercent)%")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundStyle(.green)
                Text("完成")
                    .font(.system(size: 10))
                    .foregroundStyle(accent)
            }
        case .failed:
            Button("重试", action: retry)
                .buttonStyle(.borderless)
                .font(.system(size: 11, weight: .medium))
                .foregroundStyle(accent)
        }
    }

    private var sourceSize: String {
        ByteCountFormatter.string(
            fromByteCount: task.originalFileSize ?? fileSize(at: task.sourceURL),
            countStyle: .file
        )
    }

    private var sizeSummary: String {
        guard let outputURL = task.outputURL else { return sourceSize }
        return "\(sourceSize) → \(ByteCountFormatter.string(fromByteCount: fileSize(at: outputURL), countStyle: .file))"
    }

    private var savingsPercent: Int {
        guard let outputURL = task.outputURL else { return 0 }
        let source = task.originalFileSize ?? fileSize(at: task.sourceURL)
        guard source > 0 else { return 0 }
        let saved = max(0, source - fileSize(at: outputURL))
        return Int((Double(saved) / Double(source) * 100).rounded())
    }

    private func fileSize(at url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func message(for failure: CompressionFailure) -> String {
        switch failure {
        case .invalidAPIKey: "API Key 无效"
        case .quotaExceeded: "本月额度已用完"
        case let .transport(message), let .localExecution(message), let .outputValidation(message): message
        case let .apiResponse(_, message): message ?? "服务暂时不可用"
        }
    }
}
