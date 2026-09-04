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
                Text(task.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .lineLimit(1)
                Text("压缩方式：\(task.displayMode.title)")
                    .font(.system(size: 11))
                    .foregroundStyle(.secondary)
                if let sequenceFrameCount {
                    Text("\(sequenceFrameCount) 张 PNG · \(sourceSize)")
                        .font(.system(size: 11))
                        .foregroundStyle(.secondary)
                }
                if sequenceFrameCount == nil || task.state.isFailed || task.state == .completed {
                    taskDetail
                }
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
        .accessibilityLabel("\(task.displayName)，\(task.displayMode.title)")
        .accessibilityValue("压缩引擎：\(task.engine.rawValue)")
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
            if task.isRetryable {
                Button("重试", action: retry)
                    .buttonStyle(.borderless)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(accent)
            } else {
                Text("无法转换")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(.red)
            }
        }
    }

    private var sequenceFrameCount: Int? {
        guard case let .pngSequence(frameCount) = task.inputKind else {
            return nil
        }
        return frameCount
    }

    private var sourceSize: String {
        return ByteCountFormatter.string(
            fromByteCount: sourceByteCount,
            countStyle: .file
        )
    }

    private var sourceByteCount: Int64 {
        if let originalFileSize = task.originalFileSize {
            return originalFileSize
        }
        if sequenceFrameCount != nil {
            return task.sourceURLs.reduce(into: 0) { total, sourceURL in
                total += fileSize(at: sourceURL)
            }
        }
        return fileSize(at: task.sourceURL)
    }

    private var sizeSummary: String {
        guard let compressedFileSize = task.compressedFileSize else { return sourceSize }
        return "\(sourceSize) → \(ByteCountFormatter.string(fromByteCount: compressedFileSize, countStyle: .file))"
    }

    private var savingsPercent: Int {
        guard let source = task.originalFileSize,
              let compressed = task.compressedFileSize else { return 0 }
        guard source > 0 else { return 0 }
        let saved = max(0, source - compressed)
        return Int((Double(saved) / Double(source) * 100).rounded())
    }

    private func fileSize(at url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func message(for failure: CompressionFailure) -> String {
        FailureCatalog.message(for: failure.code)
    }
}
