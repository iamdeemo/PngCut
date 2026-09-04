import Foundation
import ImageIO

protocol PNGSequenceDetecting: Sendable {
    func detect(in images: [DiscoveredImage]) -> [PNGSequence]
    func validateFrameDimensions(_ sequence: PNGSequence) throws
}

struct PNGSequenceDetector: PNGSequenceDetecting {
    private static let terminalDigitsPattern = try! NSRegularExpression(pattern: "^(.*?)([0-9]+)$")
    private static let invalidDimensionsMessage = "帧尺寸不一致，无法转 GIF"

    func detect(in images: [DiscoveredImage]) -> [PNGSequence] {
        var groups: [SequenceKey: [Frame]] = [:]

        for image in images where image.format == .png {
            guard let frame = frame(from: image) else {
                continue
            }
            groups[frame.key, default: []].append(frame)
        }

        return groups.values.compactMap(makeSequence(from:)).sorted {
            $0.frameURLs.first?.path ?? "" < $1.frameURLs.first?.path ?? ""
        }
    }

    func validateFrameDimensions(_ sequence: PNGSequence) throws {
        var expectedDimensions: FrameDimensions?

        for frameURL in sequence.frameURLs {
            guard let dimensions = dimensions(of: frameURL) else {
                throw invalidDimensionsFailure()
            }
            guard let expectedDimensions else {
                expectedDimensions = dimensions
                continue
            }
            guard dimensions == expectedDimensions else {
                throw invalidDimensionsFailure()
            }
        }
    }

    private func frame(from image: DiscoveredImage) -> Frame? {
        let basename = image.fileURL.deletingPathExtension().lastPathComponent
        let range = NSRange(basename.startIndex..., in: basename)
        guard let match = Self.terminalDigitsPattern.firstMatch(in: basename, range: range),
              let prefixRange = Range(match.range(at: 1), in: basename),
              let digitsRange = Range(match.range(at: 2), in: basename),
              let frameNumber = Int(basename[digitsRange]) else {
            return nil
        }

        let parentDirectory = image.fileURL.deletingLastPathComponent().standardizedFileURL
        let prefix = String(basename[prefixRange])
        return Frame(
            image: image,
            key: SequenceKey(parentDirectory: parentDirectory, prefix: prefix),
            number: frameNumber
        )
    }

    private func makeSequence(from frames: [Frame]) -> PNGSequence? {
        let orderedFrames = frames.sorted {
            $0.number == $1.number
                ? $0.image.fileURL.path < $1.image.fileURL.path
                : $0.number < $1.number
        }
        guard orderedFrames.count >= 10,
              let firstNumber = orderedFrames.first?.number,
              let lastNumber = orderedFrames.last?.number,
              lastNumber - firstNumber + 1 == orderedFrames.count,
              let firstFrame = orderedFrames.first else {
            return nil
        }

        let importedFolderRoot = commonImportedFolderRoot(for: orderedFrames)
        let trimmedPrefix = firstFrame.key.prefix.trimmingTrailingGIFSeparators()
        let outputBaseName = trimmedPrefix.isEmpty ? "sequence" : trimmedPrefix
        return PNGSequence(
            frameURLs: orderedFrames.map(\.image.fileURL),
            importedFolderRoot: importedFolderRoot,
            outputFileName: "\(outputBaseName).gif"
        )
    }

    private func commonImportedFolderRoot(for frames: [Frame]) -> URL? {
        let firstRoot = frames.first?.image.importedFolderRoot?.standardizedFileURL
        guard frames.allSatisfy({ $0.image.importedFolderRoot?.standardizedFileURL == firstRoot }) else {
            return nil
        }
        return firstRoot
    }

    private func dimensions(of url: URL) -> FrameDimensions? {
        guard let source = CGImageSourceCreateWithURL(url as CFURL, nil),
              let properties = CGImageSourceCopyPropertiesAtIndex(source, 0, nil) as? [CFString: Any],
              let width = (properties[kCGImagePropertyPixelWidth] as? NSNumber)?.intValue,
              let height = (properties[kCGImagePropertyPixelHeight] as? NSNumber)?.intValue,
              width > 0,
              height > 0 else {
            return nil
        }
        return FrameDimensions(width: width, height: height)
    }

    private func invalidDimensionsFailure() -> CompressionFailure {
        CompressionFailure(code: .outputInvalid, technicalMessage: Self.invalidDimensionsMessage)
    }
}

private struct SequenceKey: Hashable {
    let parentDirectory: URL
    let prefix: String
}

private struct Frame {
    let image: DiscoveredImage
    let key: SequenceKey
    let number: Int
}

private struct FrameDimensions: Equatable {
    let width: Int
    let height: Int
}

private extension String {
    func trimmingTrailingGIFSeparators() -> String {
        String(reversed().drop { "_-. ".contains($0) }.reversed())
    }
}
