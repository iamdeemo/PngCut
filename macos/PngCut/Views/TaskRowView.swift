import SwiftUI

struct TaskRowView: View {
    let task: CompressionTask
    let retry: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        HStack(spacing: 12) {
            Image("ImageFile")
                .renderingMode(.template)
                .resizable()
                .scaledToFit()
                .frame(width: 24, height: 24)
                .foregroundStyle(PngCutPalette.accent)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 5) {
                Text(task.displayName)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundStyle(PngCutPalette.primaryText)
                    .lineLimit(1)
                Text("压缩方式：\(task.displayMode.title)")
                    .font(.system(size: 11))
                    .foregroundStyle(PngCutPalette.secondaryText)
                if let sequenceFrameCount {
                    Text("\(sequenceFrameCount) 张 PNG · \(sourceSize)")
                        .font(.system(size: 11))
                        .foregroundStyle(PngCutPalette.secondaryText)
                }
                if sequenceFrameCount == nil || task.state.isFailed || task.state == .completed {
                    taskDetail
                }
                if task.state == .processing {
                    ProgressView(value: task.progress)
                        .tint(PngCutPalette.accent)
                        .frame(maxWidth: .infinity)
                        .animation(progressAnimation, value: task.progress)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)

            taskState
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .background(Color.white)
        .overlay {
            RoundedRectangle(cornerRadius: 12, style: .continuous)
                .stroke(PngCutPalette.separator, lineWidth: 0.5)
        }
        .clipShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(task.displayName)，\(task.displayMode.title)")
        .accessibilityValue("压缩引擎：\(task.engine.rawValue)")
    }

    @ViewBuilder
    private var taskDetail: some View {
        switch task.state {
        case let .failed(error):
            VStack(alignment: .leading, spacing: 2) {
                Text(sourceSize)
                    .font(.system(size: 11))
                    .foregroundStyle(PngCutPalette.secondaryText)
                Text(message(for: error))
                    .font(.system(size: 11))
                    .foregroundStyle(failureColor)
                    .lineLimit(2)
            }
        case .completed:
            Text(sizeSummary)
                .font(.system(size: 11))
                .foregroundStyle(PngCutPalette.secondaryText)
                .lineLimit(1)
        case .queued, .processing:
            Text(sourceSize)
                .font(.system(size: 11))
                .foregroundStyle(PngCutPalette.secondaryText)
        }
    }

    @ViewBuilder
    private var taskState: some View {
        switch task.state {
        case .queued:
            Text("等待")
                .font(.system(size: 11))
                .foregroundStyle(PngCutPalette.secondaryText)
        case .processing:
            stateContainer(identifier: "taskStateProcessing") {
                Text("处理中 \(progressPercent)%")
                    .font(.system(size: 11, weight: .medium))
                    .foregroundStyle(PngCutPalette.accent)
                    .animation(progressAnimation, value: progressPercent)
            }
        case .completed:
            stateContainer(identifier: "taskStateCompleted") {
                VStack(alignment: .trailing, spacing: 2) {
                    Text("节省 \(savingsPercent)%")
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundStyle(savingsColor)
                    Text("完成")
                        .font(.system(size: 10))
                        .foregroundStyle(PngCutPalette.accent)
                }
            }
        case .failed:
            stateContainer(identifier: "taskStateFailed") {
                if task.isRetryable {
                    Button("重试", action: retry)
                        .buttonStyle(.borderless)
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(PngCutPalette.accent)
                        .accessibilityIdentifier("retryFailedButton")
                } else {
                    Text("无法转换")
                        .font(.system(size: 11, weight: .medium))
                        .foregroundStyle(failureColor)
                }
            }
        }
    }

    private func stateContainer<Content: View>(
        identifier: String,
        @ViewBuilder content: () -> Content
    ) -> some View {
        ZStack {
            Color.clear
                .frame(width: 1, height: 1)
                .accessibilityElement()
                .accessibilityIdentifier(identifier)
            content()
        }
        .fixedSize()
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

    private var progressPercent: Int {
        Int((task.progress * 100).rounded())
    }

    private var progressAnimation: Animation? {
        reduceMotion ? nil : .linear(duration: 0.15)
    }

    private var savingsPercent: Int {
        guard let source = task.originalFileSize,
              let compressed = task.compressedFileSize else { return 0 }
        guard source > 0 else { return 0 }
        let saved = max(0, source - compressed)
        return Int((Double(saved) / Double(source) * 100).rounded())
    }

    private var savingsColor: Color {
        Color(red: 0.12, green: 0.58, blue: 0.32)
    }

    private var failureColor: Color {
        Color(red: 0.82, green: 0.18, blue: 0.18)
    }

    private func fileSize(at url: URL) -> Int64 {
        Int64((try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0)
    }

    private func message(for failure: CompressionFailure) -> String {
        FailureCatalog.message(for: failure.code)
    }
}
