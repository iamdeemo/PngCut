# GIF Compression and PNG Sequence Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Add offline GIF compression with Gifsicle and PNG-sequence-to-GIF conversion with Gifski to the macOS pngcut app, while preserving its existing modes, queue safety, output policy, and settings style.

**Architecture:** Extend discovery to include GIF files, keep PNG sequence grouping and frame validation in a pure service, and represent a sequence as one queue task with many source URLs. Reuse the current local-executable, temporary-output, atomic-commit path by adding Gifsicle and Gifski adapters; keep all import decisions and settings state in `AppModel` and render them with the existing settings-drawer controls.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, ImageIO, XCTest/XCUITest, Xcode project resources, Gifsicle 1.96, Gifski 1.34.0, Bash, Cargo/Rust.

---

## File structure

| File | Responsibility |
| --- | --- |
| `PngCut/Domain/GIFSettings.swift` | Persistable GIF checkbox, FPS selection, loop selection, and Gifski argument mapping. |
| `PngCut/Domain/PNGSequence.swift` | One validated candidate sequence and its generated output name. |
| `PngCut/Services/PNGSequenceDetector.swift` | Pure filename grouping, numeric sorting, threshold logic, and ImageIO frame-size validation. |
| `PngCut/Services/GifsicleCompressor.swift` | Bundled Gifsicle resolution and GIF size-safe compression. |
| `PngCut/Services/GifskiSequenceEncoder.swift` | Bundled Gifski resolution and one-output encoding of an ordered PNG sequence. |
| `PngCut/App/AppModel.swift` | Import analysis, pending user decisions, setting persistence, engine routing, and queue preparation. |
| `PngCut/Domain/CompressionTask.swift` | One-file versus sequence task metadata, display name, and total input size. |
| `PngCut/Services/ImageCompressor.swift` | Common `CompressionOperation` abstraction for one-file compressors and sequence encoders. |
| `PngCut/Services/CompressionQueue.swift` | Runs either operation while retaining the existing serial, atomic, retryable lifecycle. |
| `PngCut/Domain/OutputPolicy.swift` | Plans an explicitly named generated GIF without permitting source-frame overwrite. |
| `PngCut/Views/MainWindowView.swift` | GIF import types, import-decision alerts, and copy updates. |
| `PngCut/Views/SettingsDrawerView.swift` | GIF checkbox, FPS radios/custom input, loop radios, and stable accessibility identifiers. |
| `PngCut/Views/TaskRowView.swift` | Shows sequence output name, frame count, and total source size in the existing row layout. |
| `PngCutTests/*` / `PngCutUITests/PngCutUITests.swift` | Unit, queue, model, adapter, output-policy, and UI regression coverage. |
| `scripts/build-gifsicle.sh`, `scripts/build-gifski.sh` | Reproducibly build pinned universal-resource pairs. |
| `PngCut/Resources/gifsicle`, `PngCut/Resources/gifski` | The two architecture-specific executables and their license texts. |
| `README.md`, `THIRD_PARTY_NOTICES.md`, `scripts/check-release-content.sh` | User-facing format contract, license/source notices, and DMG resource verification. |

### Task 1: Add GIF configuration and sequence detection domain types

**Files:**
- Create: `PngCut/Domain/GIFSettings.swift`
- Create: `PngCut/Domain/PNGSequence.swift`
- Create: `PngCut/Services/PNGSequenceDetector.swift`
- Create: `PngCutTests/GIFSettingsTests.swift`
- Create: `PngCutTests/PNGSequenceDetectorTests.swift`
- Modify: `PngCut/Services/FileDiscovery.swift`
- Modify: `PngCut.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing GIF-configuration tests.**

  Add `GIFSettingsTests` cases that lock down defaults, user-visible FPS choices, persistence-ready values, and Gifski repeat values:

  ```swift
  func testDefaultsKeepSequenceConversionOffAt30FPSAndLoopForever() {
      XCTAssertEqual(GIFSettings(), GIFSettings(
          pngSequenceConversionEnabled: false,
          frameRate: .preset(30),
          loop: .forever
      ))
  }

  func testCustomFrameRateMustBeBetweenOneAndFifty() {
      XCTAssertEqual(GIFFrameRate.custom(validating: 1), .custom(1))
      XCTAssertEqual(GIFFrameRate.custom(validating: 50), .custom(50))
      XCTAssertNil(GIFFrameRate.custom(validating: 0))
      XCTAssertNil(GIFFrameRate.custom(validating: 51))
  }

  func testLoopArgumentsMatchGifskiCLI() {
      XCTAssertEqual(GIFLoop.forever.gifskiRepeatArgument, 0)
      XCTAssertEqual(GIFLoop.once.gifskiRepeatArgument, -1)
  }
  ```

- [ ] **Step 2: Run the new configuration test target and verify it fails to compile.**

  Run:

  ```bash
  xcodebuild -project PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutTests/GIFSettingsTests test
  ```

  Expected: compilation fails because `GIFSettings`, `GIFFrameRate`, and `GIFLoop` do not yet exist.

- [ ] **Step 3: Implement the configuration types.**

  Add the following public domain surface in `GIFSettings.swift`:

  ```swift
  import Foundation

  enum GIFFrameRate: Equatable, Sendable {
      case preset(Int)
      case custom(Int)

      static let presetValues = [20, 25, 30]

      var value: Int {
          switch self {
          case let .preset(value), let .custom(value): value
          }
      }

      static func custom(validating value: Int) -> Self? {
          (1...50).contains(value) ? .custom(value) : nil
      }
  }

  enum GIFLoop: String, Equatable, Sendable {
      case forever
      case once

      var gifskiRepeatArgument: Int {
          self == .forever ? 0 : -1
      }
  }

  struct GIFSettings: Equatable, Sendable {
      var pngSequenceConversionEnabled = false
      var frameRate: GIFFrameRate = .preset(30)
      var loop: GIFLoop = .forever
  }
  ```

  Add both Swift files and their test files to the app/test targets in `project.pbxproj`, using new unique `PBXFileReference`, `PBXBuildFile`, group-child, and source-phase entries following the existing `B000…` entries.

- [ ] **Step 4: Write failing discovery and detector tests.**

  In `FileDiscoveryTests`, add GIF case-insensitive discovery assertions. In `PNGSequenceDetectorTests`, construct `DiscoveredImage` values and cover at least these cases:

  ```swift
  func testDetectsTenContiguousFramesAndOrdersByNumericSuffix() throws {
      let frames = [10, 1, 2, 3, 4, 5, 6, 7, 8, 9].map {
          discovered("walk_\($0).png")
      }
      let detected = PNGSequenceDetector().detect(in: frames)
      XCTAssertEqual(detected.count, 1)
      let sequence = try XCTUnwrap(detected.first)
      XCTAssertEqual(sequence.frameURLs.map(\.lastPathComponent), [
          "walk_1.png", "walk_2.png", "walk_3.png", "walk_4.png", "walk_5.png",
          "walk_6.png", "walk_7.png", "walk_8.png", "walk_9.png", "walk_10.png"
      ])
      XCTAssertEqual(sequence.outputFileName, "walk.gif")
  }

  func testRejectsNineFramesAGapAndCrossDirectoryGrouping() {
      XCTAssertTrue(PNGSequenceDetector().detect(in: nineFrames).isEmpty)
      XCTAssertTrue(PNGSequenceDetector().detect(in: framesWithMissingFive).isEmpty)
      XCTAssertTrue(PNGSequenceDetector().detect(in: sameNamesInTwoDirectories).isEmpty)
  }
  ```

  Make `discovered(_:)` create URLs in a unique temporary directory; include one group with `walk_0001.png` through `walk_0010.png` to prove zero-filled names work.

- [ ] **Step 5: Run the detector tests and verify they fail.**

  Run:

  ```bash
  xcodebuild -project PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutTests/PNGSequenceDetectorTests \
    -only-testing:PngCutTests/FileDiscoveryTests test
  ```

  Expected: failure because `ImageFormat.gif`, `PNGSequence`, and `PNGSequenceDetector` are absent.

- [ ] **Step 6: Implement file discovery and pure sequence grouping.**

  Extend `ImageFormat` without changing its PNG/JPEG behavior:

  ```swift
  enum ImageFormat: String, Equatable, Sendable {
      case png
      case jpeg
      case gif

      init?(url: URL) {
          switch url.pathExtension.lowercased() {
          case "png": self = .png
          case "jpg", "jpeg": self = .jpeg
          case "gif": self = .gif
          default: return nil
          }
      }
  }
  ```

  Make `DiscoveredImage`, `FileDiscoveryResult`, and `PNGSequence` conform to `Sendable` as well as their existing equality conformance, because the immutable discovery result crosses from the utility task back to the main actor. Make `PNGSequence` hold `frameURLs`, `importedFolderRoot`, and `outputFileName`. Declare an injectable detector boundary before the concrete detector so `AppModel` tests can supply deterministic candidates:

  ```swift
  protocol PNGSequenceDetecting: Sendable {
      func detect(in images: [DiscoveredImage]) -> [PNGSequence]
      func validateFrameDimensions(_ sequence: PNGSequence) throws
  }

  ```

  Make `PNGSequenceDetector` conform to that protocol. In `detect(in:)`, parse only a terminal digit run using `NSRegularExpression(pattern: "^(.*?)([0-9]+)$")`; group by standardized parent path plus the nonnumeric prefix; sort the parsed integers; accept only groups with `count >= 10` and `last - first + 1 == count`; derive the output by trimming trailing separators (`_`, `-`, `.`, space) from the prefix and appending `.gif`. Do not inspect image bytes in `detect(in:)`.

- [ ] **Step 7: Add header-only size validation tests and implementation.**

  Add a test helper using `CGImageDestinationCreateWithURL` to create valid 1×1 and 2×1 PNGs. Assert that validation returns the shared size for equal frames and throws `.outputValidation("帧尺寸不一致，无法转 GIF")` for a candidate with one 2×1 frame.

  Implement `PNGSequenceDetector.validateFrameDimensions(_:)` with `CGImageSourceCreateWithURL` and `kCGImagePropertyPixelWidth` / `kCGImagePropertyPixelHeight`:

  ```swift
  func validateFrameDimensions(_ sequence: PNGSequence) throws {
      let sizes = try sequence.frameURLs.map(readPixelSize)
      guard Set(sizes).count == 1 else {
          throw CompressionFailure.outputValidation("帧尺寸不一致，无法转 GIF")
      }
  }
  ```

  `readPixelSize(_:)` must translate an unreadable header or absent width/height into that same `CompressionFailure.outputValidation` message. Call validation only after filename detection has established a candidate and the selected import action is conversion.

- [ ] **Step 8: Run focused tests and commit the completed domain slice.**

  Run:

  ```bash
  xcodebuild -project PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutTests/GIFSettingsTests \
    -only-testing:PngCutTests/PNGSequenceDetectorTests \
    -only-testing:PngCutTests/FileDiscoveryTests test
  ```

  Expected: PASS.

  Commit only the listed domain/service/test/project files:

  ```bash
  git add PngCut/Domain/GIFSettings.swift PngCut/Domain/PNGSequence.swift \
    PngCut/Services/PNGSequenceDetector.swift PngCut/Services/FileDiscovery.swift \
    PngCutTests/GIFSettingsTests.swift PngCutTests/PNGSequenceDetectorTests.swift \
    PngCutTests/FileDiscoveryTests.swift PngCut.xcodeproj/project.pbxproj
  git commit -m "feat: detect PNG frame sequences"
  ```

### Task 2: Extend task and output models for generated GIFs

**Files:**
- Modify: `PngCut/Domain/CompressionTask.swift`
- Modify: `PngCut/Domain/OutputPolicy.swift`
- Modify: `PngCutTests/OutputPolicyTests.swift`
- Modify: `PngCutTests/CompressionQueueTests.swift`

- [ ] **Step 1: Write failing task-metadata and output-planner tests.**

  Add tests for a sequence task’s display information and total input size, and for the safe output exception:

  ```swift
  func testSequenceTaskUsesGeneratedNameAndTotalInputSize() {
      let task = CompressionTask(
          sourceURL: frameURLs[0],
          sourceURLs: frameURLs,
          displayName: "walk.gif",
          inputKind: .pngSequence(frameCount: 10),
          originalFileSize: 420
      )
      XCTAssertEqual(task.displayName, "walk.gif")
      XCTAssertEqual(task.inputKind, .pngSequence(frameCount: 10))
      XCTAssertEqual(task.originalFileSize, 420)
  }

  func testGeneratedGIFNeverUsesOverwriteSourcePolicy() throws {
      var planner = OutputPlanner(policy: .overwrite, customDirectory: nil, reservedFinalURLs: [])
      let output = try planner.prepareGeneratedGIF(
          representativeSource: source.appendingPathComponent("walk_0001.png"),
          outputFileName: "walk.gif",
          importedFolderRoot: nil
      )
      XCTAssertEqual(output.finalURL.lastPathComponent, "walk.gif")
      XCTAssertFalse(output.allowsReplacingExistingFile)
  }
  ```

- [ ] **Step 2: Run the new tests and verify their initial failure.**

  Run:

  ```bash
  xcodebuild -project PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutTests/OutputPolicyTests \
    -only-testing:PngCutTests/CompressionQueueTests test
  ```

  Expected: compilation failure for `sourceURLs`, `displayName`, `CompressionTaskInputKind`, and `prepareGeneratedGIF`.

- [ ] **Step 3: Implement sequence-safe task metadata.**

  Add these fields while retaining `sourceURL` as the representative URL used by existing one-file callers:

  ```swift
  enum CompressionTaskInputKind: Equatable, Sendable {
      case file
      case pngSequence(frameCount: Int)
  }

  struct CompressionTask: Identifiable, Equatable {
      let sourceURL: URL
      let sourceURLs: [URL]
      let displayName: String
      let inputKind: CompressionTaskInputKind
      let isRetryable: Bool
      // Keep all existing fields unchanged.
  }
  ```

  In the initializer, standardize every source URL, default `sourceURLs` to `[sourceURL]`, default `displayName` to `sourceURL.lastPathComponent`, default `inputKind` to `.file`, and default `isRetryable` to `true`. Extend `CompressionEngine` with `.gifsicle` and `.gifski`.

- [ ] **Step 4: Implement generated-GIF planning without changing regular outputs.**

  Add this dedicated `OutputPlanner` API:

  ```swift
  mutating func prepareGeneratedGIF(
      representativeSource: URL,
      outputFileName: String,
      importedFolderRoot: URL?
  ) throws -> PreparedOutput
  ```

  For `.adjacent`, use the representative frame’s parent for direct imports and the existing folder-output convention (a sibling directory named after the selected root plus `_pngcut`) for folder imports. For `.customDirectory`, use that directory. For `.overwrite`, use the same `.adjacent` destination rule. Reserve `walk.gif`, then `walk-2.gif`, etc.; always set `allowsReplacingExistingFile` to `false`. Keep `prepare(source:...)` byte-for-byte compatible for PNG/JPEG/GIF file compression.

- [ ] **Step 5: Add collision and folder-path regression tests.**

  Add one test that precreates `walk.gif` and expects `walk-2.gif`, and one folder-import test that expects the selected-root sibling output directory followed by `nested/walk.gif`. Keep all existing output tests unchanged and passing.

- [ ] **Step 6: Run model and output tests, then commit.**

  Run:

  ```bash
  xcodebuild -project PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutTests/OutputPolicyTests \
    -only-testing:PngCutTests/CompressionQueueTests test
  ```

  Expected: PASS.

  Commit:

  ```bash
  git add PngCut/Domain/CompressionTask.swift PngCut/Domain/OutputPolicy.swift \
    PngCutTests/OutputPolicyTests.swift PngCutTests/CompressionQueueTests.swift
  git commit -m "feat: plan safe generated GIF outputs"
  ```

### Task 3: Add Gifsicle and Gifski local processors

**Files:**
- Create: `PngCut/Services/GifsicleCompressor.swift`
- Create: `PngCut/Services/GifskiSequenceEncoder.swift`
- Create: `PngCutTests/GifsicleCompressorTests.swift`
- Create: `PngCutTests/GifskiSequenceEncoderTests.swift`
- Modify: `PngCut/Services/ImageCompressor.swift`
- Modify: `PngCut/Services/CompressionQueue.swift`
- Modify: `PngCut.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing Gifsicle command and no-growth tests.**

  Use the existing executable-shell-script pattern from `PngquantCompressorTests`. Assert exact mode arguments and output behavior:

  ```swift
  func testBalancedGifsicleUsesO3AndLossy200() async throws {
      let executable = try fakeExecutable(asserting: ["-O3", "--lossy=200", "--output"])
      let outcome = try await GifsicleCompressor(
          mode: .balanced,
          resolver: FixedResolver(url: executable)
      ).compress(source: sourceGIF, temporaryDestination: destination, progress: { _ in })
      XCTAssertEqual(outcome, .compressed)
  }

  func testGifsicleReturnsNoChangeWhenTemporaryOutputIsNotSmaller() async throws {
      let outcome = try await compressorWriting(bytes: 100)
          .compress(source: sourceGIFWith100Bytes, temporaryDestination: destination, progress: { _ in })
      XCTAssertEqual(outcome, .noChange)
      XCTAssertFalse(FileManager.default.fileExists(atPath: destination.path))
  }
  ```

- [ ] **Step 2: Write failing Gifski ordering and argument tests.**

  Create a fake `gifski` executable that validates arguments and writes the path passed after `--output`:

  ```swift
  func testGifskiUsesQuality100ThirtyFPSAndInfiniteLoop() async throws {
      let encoder = GifskiSequenceEncoder(resolver: FixedResolver(url: executable))
      try await encoder.encode(
          frames: orderedFrames,
          quality: 100,
          frameRate: 30,
          loop: .forever,
          temporaryDestination: destination,
          progress: { _ in }
      )
      XCTAssertEqual(capturedArguments, [
          "--quality", "100", "--fps", "30", "--repeat", "0", "--output", destination.path,
          "--no-sort"
      ] + orderedFrames.map(\.path))
  }

  func testGifskiMapsPlaybackOnceToRepeatMinusOne() async throws {
      // Same fake executable; assert `--repeat`, `-1`.
  }
  ```

- [ ] **Step 3: Run the two new test classes and verify they fail.**

  Run:

  ```bash
  xcodebuild -project PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutTests/GifsicleCompressorTests \
    -only-testing:PngCutTests/GifskiSequenceEncoderTests test
  ```

  Expected: compilation failure because neither processor nor resolver protocol exists.

- [ ] **Step 4: Implement the Gifsicle adapter.**

  Mirror the `PngquantBinaryResolver` shape with resource folder `gifsicle` and base executable name `gifsicle`. Make the mode-to-argument mapping exact:

  ```swift
  private var optimizationArguments: [String] {
      switch mode {
      case .lossless: ["-O3"]
      case .balanced: ["-O3", "--lossy=200"]
      }
  }
  ```

  Run `LocalProcessRunner`, map nonzero status plus trimmed stderr to `.localExecution`, validate a nonempty temporary output, compare its size with the source, and remove it before returning `.noChange` when `temporarySize >= sourceSize`.

- [ ] **Step 5: Implement the Gifski adapter.**

  Create `GifskiBinaryResolving` and `GifskiSequenceEncoding` protocols. `GifskiSequenceEncoder` must call the architecture-specific bundled binary from `Resources/gifski`, preserve the detector’s numeric frame order with `--no-sort`, and use these arguments:

  ```swift
  let arguments = [
      "--quality", "\(quality)",
      "--fps", "\(frameRate)",
      "--repeat", "\(loop.gifskiRepeatArgument)",
      "--output", temporaryDestination.path,
      "--no-sort"
  ] + frames.map(\.path)
  ```

  Validate `quality` in `1...100`, `frameRate` in `1...50`, `frames.count >= 10`, a nonempty output, and map process diagnostics exactly as the other local tools do.

- [ ] **Step 6: Generalize queue work without changing existing compressors.**

  Add this operation wrapper in `ImageCompressor.swift`:

  ```swift
  enum CompressionOperation: Sendable {
      case file(any ImageCompressor)
      case pngSequence(any GifskiSequenceEncoding, quality: Int, frameRate: Int, loop: GIFLoop)

      func run(
          task: CompressionTask,
          temporaryDestination: URL,
          progress: @escaping @Sendable (Double) -> Void
      ) async throws -> CompressionOutcome {
          switch self {
          case let .file(compressor):
              return try await compressor.compress(
                  source: task.sourceURL,
                  temporaryDestination: temporaryDestination,
                  progress: progress
              )
          case let .pngSequence(encoder, quality, frameRate, loop):
              try await encoder.encode(
                  frames: task.sourceURLs,
                  quality: quality,
                  frameRate: frameRate,
                  loop: loop,
                  temporaryDestination: temporaryDestination,
                  progress: progress
              )
              return .compressed
          }
      }
  }
  ```

  Change `CompressionQueue.WorkItem` and `QueuedTask` to store `operation`; call `operation.run` in the worker. Keep `.noChange` behavior restricted to `.file` tasks, because Gifski always returns `.compressed`.

  Keep invalid preflight failures honest: modify `retryFailed()` to enqueue only `task.isRetryable == true`, and make the task-row failed state show `无法转换` instead of a retry button when `isRetryable` is false. Add a queue regression test proving a non-retryable failed task stays failed after `retryFailed()`.

- [ ] **Step 7: Run processor and queue tests, then commit.**

  Run:

  ```bash
  xcodebuild -project PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutTests/GifsicleCompressorTests \
    -only-testing:PngCutTests/GifskiSequenceEncoderTests \
    -only-testing:PngCutTests/CompressionQueueTests test
  ```

  Expected: PASS.

  Commit:

  ```bash
  git add PngCut/Services/GifsicleCompressor.swift PngCut/Services/GifskiSequenceEncoder.swift \
    PngCut/Services/ImageCompressor.swift PngCut/Services/CompressionQueue.swift \
    PngCutTests/GifsicleCompressorTests.swift PngCutTests/GifskiSequenceEncoderTests.swift \
    PngCutTests/CompressionQueueTests.swift PngCut.xcodeproj/project.pbxproj
  git commit -m "feat: add local GIF processors"
  ```

### Task 4: Integrate import analysis, decisions, settings persistence, and routing

**Files:**
- Modify: `PngCut/App/AppModel.swift`
- Modify: `PngCut/Domain/CompressionTask.swift`
- Modify: `PngCutTests/PngCutTests.swift`

- [ ] **Step 1: Write failing persistence and route-selection tests.**

  Add tests that use a unique `UserDefaults` suite:

  ```swift
  func testGIFSettingsAreRestoredOnRelaunch() {
      preferences.set(true, forKey: "pngcut.gif.sequence-enabled")
      preferences.set(25, forKey: "pngcut.gif.frame-rate")
      preferences.set("preset", forKey: "pngcut.gif.frame-rate-kind")
      preferences.set("once", forKey: "pngcut.gif.loop")

      let model = AppModel(preferences: preferences)

      XCTAssertEqual(model.settings.gif.pngSequenceConversionEnabled, true)
      XCTAssertEqual(model.settings.gif.frameRate, .preset(25))
      XCTAssertEqual(model.settings.gif.loop, .once)
  }

  func testGIFRoutesToGifsicleUsingCurrentDisplayMode() async throws {
      let model = makeModel(mode: .balanced, compressorFactory: recordingFactory)
      model.add(urls: [sourceGIF])
      await waitUntil { model.tasks.first?.state == .completed }
      XCTAssertEqual(model.tasks.first?.engine, .gifsicle)
      XCTAssertEqual(model.tasks.first?.displayMode, .balanced)
  }
  ```

- [ ] **Step 2: Write failing import-decision tests.**

  Inject a `PNGSequenceDetecting` test double and a `GifskiSequenceEncoding` test double. Cover the confirmed matrix exactly:

  ```swift
  func testClosedCheckboxAndAcceptedSequencePromptEncodesAndChecksTheBox() async throws { /* 10 frames */ }
  func testClosedCheckboxAndDeclinedSequencePromptCompressesFramesAndLeavesBoxUnchecked() async throws { /* 10 frames */ }
  func testClosedCheckboxWithoutSequenceCompressesImmediatelyWithoutPrompt() async throws { /* ordinary PNG */ }
  func testOpenCheckboxWithSequenceEncodesWithoutPrompt() async throws { /* 10 frames */ }
  func testOpenCheckboxWithoutSequenceAndAcceptedFallbackCompressesAndUnchecksBox() async throws { /* ordinary PNG */ }
  func testOpenCheckboxWithoutSequenceAndDeclinedFallbackShowsNoticeAndDoesNotQueueFiles() async throws { /* ordinary PNG */ }
  func testMixedImportEncodesSequenceAndProcessesStandalonePNGAndGIF() async throws { /* three task kinds */ }
  func testDimensionMismatchProducesFailedSequenceTaskWithoutModifyingFrames() async throws { /* valid PNG headers */ }
  ```

  Make these tests call explicit `resolvePendingImport(convertSequence:)` and `resolvePendingImport(compressInstead:)` methods rather than reaching into SwiftUI.

- [ ] **Step 3: Run AppModel tests and verify the new cases fail.**

  Run:

  ```bash
  xcodebuild -project PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutTests/PngCutTests test
  ```

  Expected: failures for `AppSettings.gif`, new preference keys, pending-import state, and GIF engine factories.

- [ ] **Step 4: Add AppSettings persistence and explicit import prompt types.**

  Extend `AppSettings` with `var gif = GIFSettings()`. Add these preference keys exactly:

  ```swift
  static let gifSequenceEnabled = "pngcut.gif.sequence-enabled"
  static let gifFrameRate = "pngcut.gif.frame-rate"
  static let gifFrameRateKind = "pngcut.gif.frame-rate-kind"
  static let gifLoop = "pngcut.gif.loop"
  ```

  Persist `.preset` as `"preset"` and `.custom` as `"custom"`; when stored values are absent or invalid, load `GIFSettings()`.

  Add the following exact immutable analysis and prompt types. `regularImages` excludes every frame belonging to a detected sequence; it retains all standalone PNG/JPEG/GIF files, including mixed imports. A `PNGSequence` stays a candidate until conversion is selected, at which point its ImageIO headers are validated.

  ```swift
  struct ImportResolution: Identifiable, Equatable {
      let id: UUID
      let regularImages: [DiscoveredImage]
      let sequences: [PNGSequence]

      init(
          id: UUID = UUID(),
          regularImages: [DiscoveredImage],
          sequences: [PNGSequence]
      ) {
          self.id = id
          self.regularImages = regularImages
          self.sequences = sequences
      }

      var sequenceFrameCount: Int {
          sequences.reduce(0) { $0 + $1.frameURLs.count }
      }

      var convertMessage: String {
          "发现达到阈值的连续编号 PNG（共 \(sequenceFrameCount) 张），是否转 GIF？"
      }
  }

  enum ImportPrompt: Identifiable, Equatable {
      case convertSequences(ImportResolution)
      case compressWithoutSequence(ImportResolution)

      var id: UUID {
          switch self {
          case let .convertSequences(resolution), let .compressWithoutSequence(resolution):
              resolution.id
          }
      }

      var message: String {
          switch self {
          case let .convertSequences(resolution): resolution.convertMessage
          case .compressWithoutSequence: "是否按常规方式压缩当前文件？"
          }
      }
  }
  ```

  Model the notice as an alert item rather than a raw `String`, so SwiftUI can bind it without an unsafe force unwrap:

  ```swift
  struct ImportNotice: Identifiable, Equatable {
      let id = UUID()
      let message: String
  }
  ```

  Add `@Published var pendingImportPrompt: ImportPrompt?` and `@Published var importNotice: ImportNotice?` to `AppModel`. Give it public resolution methods whose names match the tests:

  ```swift
  func resolvePendingImport(convertSequence: Bool)
  func resolvePendingImport(compressInstead: Bool)
  func dismissImportNotice()
  ```

- [ ] **Step 5: Move discovery and filename candidate analysis off the main actor.**

  Keep `add(urls:)` synchronous at the call site, but immediately start a utility-priority task that calls `FileDiscovery` and `PNGSequenceDetector.detect`. Return an immutable `ImportResolution` to `AppModel` on the main actor. Do **not** read PNG headers during this initial scan: validating only begins when a sequence is about to convert. Serialize resolutions in a FIFO array so a second drag cannot replace a visible confirmation for the first drag.

  Use the following behavior when an analysis becomes active:

  ```swift
  if !resolution.sequences.isEmpty && !settings.gif.pngSequenceConversionEnabled {
      pendingImportPrompt = .convertSequences(resolution)
  } else if resolution.sequences.isEmpty && settings.gif.pngSequenceConversionEnabled {
      pendingImportPrompt = .compressWithoutSequence(resolution)
  } else {
      prepareAndEnqueue(resolution, convertSequences: !resolution.sequences.isEmpty)
  }
  ```

  `resolvePendingImport(convertSequence: true)` must first set `settings.gif.pngSequenceConversionEnabled = true`, then call `prepareAndEnqueue(_:, convertSequences: true)`. Its `false` branch calls `prepareAndEnqueue(_:, convertSequences: false)` and leaves the checkbox unchecked. `resolvePendingImport(compressInstead: true)` must set the checkbox to `false` before it queues regular files. Its `false` branch must set `importNotice = ImportNotice(message: "当前文件夹没有 PNG 序列，无法转 GIF")`, retain the checked state, and not enqueue that resolution. `dismissImportNotice()` clears the item.

  Implement `prepareAndEnqueue(_:, convertSequences:)` on the worker path. When `convertSequences` is true, call `validateFrameDimensions(_:)` per candidate before planning Gifski; on a failure, use `CompressionQueue.recordFailed` to insert one `.gifski` sequence task in `.failed(.outputValidation("帧尺寸不一致，无法转 GIF"))` with `isRetryable: false`, never enqueue its PNG frames as normal compression, and continue processing other groups/standalone files. When conversion is declined, enqueue each sequence frame as normal PNG.

- [ ] **Step 6: Route each task to its operation and output policy.**

  Change the existing file compressor factory to cover `.gifsicle`; add a separate injected `sequenceEncoderFactory: () -> any GifskiSequenceEncoding` with a production default of `GifskiSequenceEncoder()`. Map the user-selected mode exactly:

  ```swift
  func gifQuality(for mode: CompressionMode) -> Int {
      mode == .lossless ? 100 : 80
  }

  func fileConfiguration(for format: ImageFormat) -> (engine: CompressionEngine, displayMode: CompressionMode) {
      switch format {
      case .png: return settings.mode == .lossless ? (.oxipng, .lossless) : (.pngquant, .balanced)
      case .jpeg: return (.mozjpeg, .balanced)
      case .gif: return settings.mode == .lossless ? (.gifsicle, .lossless) : (.gifsicle, .balanced)
      }
  }
  ```

  For every frame-size-valid sequence, make one `CompressionTask` with its ten-or-more URLs, `format: .gif`, `displayName` equal to the planned generated GIF name, `.pngSequence(frameCount:)`, `.gifski`, the current global mode, summed source bytes, `OutputPlanner.prepareGeneratedGIF`, and `.pngSequence(sequenceEncoder, quality: gifQuality(for: settings.mode), frameRate: settings.gif.frameRate.value, loop: settings.gif.loop)`. Construct dimension-failure tasks with the same `format: .gif` sequence metadata and a `.file(compressorFactory(.gifsicle))` operation solely to satisfy the queue work-item shape; pass them only to `recordFailed`, so the compressor never runs.

- [ ] **Step 7: Run AppModel and existing queue tests, then commit.**

  Run:

  ```bash
  xcodebuild -project PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutTests/PngCutTests \
    -only-testing:PngCutTests/CompressionQueueTests test
  ```

  Expected: PASS.

  Commit:

  ```bash
  git add PngCut/App/AppModel.swift PngCut/Domain/CompressionTask.swift \
    PngCutTests/PngCutTests.swift PngCutTests/CompressionQueueTests.swift
  git commit -m "feat: route GIF imports and sequence conversions"
  ```

### Task 5: Update the existing SwiftUI controls and task rows

**Files:**
- Modify: `PngCut/Views/MainWindowView.swift`
- Modify: `PngCut/Views/SettingsDrawerView.swift`
- Modify: `PngCut/Views/TaskRowView.swift`
- Modify: `PngCutUITests/PngCutUITests.swift`

- [ ] **Step 1: Write failing UI tests for the new controls.**

  Add these assertions while preserving all existing accessibility tests:

  ```swift
  func testSettingsExposeGIFControlsUsingExistingDrawer() {
      app.buttons["settingsButton"].tap()
      XCTAssertTrue(app.checkBoxes["pngSequenceGIFEnabled"].waitForExistence(timeout: 2))
      XCTAssertTrue(app.buttons["gifFrameRate20"].exists)
      XCTAssertTrue(app.buttons["gifFrameRate25"].exists)
      XCTAssertTrue(app.buttons["gifFrameRate30"].exists)
      XCTAssertTrue(app.textFields["gifCustomFrameRate"].exists)
      XCTAssertTrue(app.buttons["gifLoopForever"].exists)
      XCTAssertTrue(app.buttons["gifLoopOnce"].exists)
  }
  ```

- [ ] **Step 2: Run UI tests and verify they fail because the controls are absent.**

  Run:

  ```bash
  xcodebuild -project PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutUITests/PngCutUITests test
  ```

  Expected: the new element-existence assertion fails.

- [ ] **Step 3: Update MainWindowView without changing the overall layout.**

  Include `.gif` in `NSOpenPanel.allowedContentTypes`, and change the panel copy and empty-state copy from `PNG/JPG` to `PNG/JPG/GIF`. Add alerts bound to `model.pendingImportPrompt` and `model.importNotice`:

  ```swift
  .alert(item: $model.pendingImportPrompt) { prompt in
      switch prompt {
      case .convertSequences:
          return Alert(
              title: Text("发现 PNG 序列"),
              message: Text(prompt.message),
              primaryButton: .default(Text("转 GIF")) { model.resolvePendingImport(convertSequence: true) },
              secondaryButton: .cancel(Text("常规压缩")) { model.resolvePendingImport(convertSequence: false) }
          )
      case .compressWithoutSequence:
          return Alert(
              title: Text("未发现 PNG 序列"),
              message: Text("是否按常规方式压缩当前文件？"),
              primaryButton: .default(Text("压缩")) { model.resolvePendingImport(compressInstead: true) },
              secondaryButton: .cancel(Text("不压缩")) { model.resolvePendingImport(compressInstead: false) }
          )
      }
  }

  .alert(item: $model.importNotice) { notice in
      Alert(
          title: Text("无法转 GIF"),
          message: Text(notice.message),
          dismissButton: .default(Text("好")) { model.dismissImportNotice() }
      )
  }
  ```

- [ ] **Step 4: Add GIF settings using existing drawer primitives.**

  Rename only the existing section heading from `PNG 压缩方式` to `压缩方式`; retain the two current radio rows and the bottom-bar synchronization. Add a new `settingsSection("GIF 设置")` after it. Use a checkbox, not a two-row on/off radio:

  ```swift
  Toggle("PNG 序列转 GIF", isOn: Binding(
      get: { model.settings.gif.pngSequenceConversionEnabled },
      set: { model.settings.gif.pngSequenceConversionEnabled = $0 }
  ))
  .toggleStyle(.checkbox)
  .accessibilityIdentifier("pngSequenceGIFEnabled")
  ```

  Reuse `radio(title:isSelected:action:)` for `20 FPS`, `25 FPS`, `30 FPS`, `自定义`, `无限循环`, and `播放一次`. Set identifiers exactly to `gifFrameRate20`, `gifFrameRate25`, `gifFrameRate30`, `gifFrameRateCustom`, `gifLoopForever`, and `gifLoopOnce`. Bind custom text to local state; on submit, call `GIFFrameRate.custom(validating:)`, update the model only when it succeeds, and render `请输入 1–50 的整数` below the field when it fails.

- [ ] **Step 5: Preserve task-row structure while adding sequence information.**

  Replace only the source-name and secondary-detail data sources:

  ```swift
  Text(task.displayName)

  if case let .pngSequence(frameCount) = task.inputKind {
      Text("\(frameCount) 张 PNG · \(sourceSize)")
          .font(.system(size: 11))
          .foregroundStyle(.secondary)
  }
  ```

  Keep the existing card, progress bar, percentage, completed, and retry controls. For a failed task whose `isRetryable` is false, show `无法转换` in the existing failed-state slot instead of a retry button. Use `task.displayName` in the accessibility label.

- [ ] **Step 6: Run UI and unit tests, then commit.**

  Run:

  ```bash
  xcodebuild -project PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutUITests/PngCutUITests \
    -only-testing:PngCutTests/PngCutTests test
  ```

  Expected: PASS.

  Commit:

  ```bash
  git add PngCut/Views/MainWindowView.swift PngCut/Views/SettingsDrawerView.swift \
    PngCut/Views/TaskRowView.swift PngCutUITests/PngCutUITests.swift PngCutTests/PngCutTests.swift
  git commit -m "feat: add GIF settings and import prompts"
  ```

### Task 6: Bundle the two macOS tools and update release material

**Files:**
- Create: `scripts/build-gifsicle.sh`
- Create: `scripts/build-gifski.sh`
- Create: `PngCut/Resources/gifsicle/gifsicle-arm64`
- Create: `PngCut/Resources/gifsicle/gifsicle-x86_64`
- Create: `PngCut/Resources/gifsicle/LICENSE-gifsicle`
- Create: `PngCut/Resources/gifski/gifski-arm64`
- Create: `PngCut/Resources/gifski/gifski-x86_64`
- Create: `PngCut/Resources/gifski/LICENSE-gifski`
- Modify: `PngCut.xcodeproj/project.pbxproj`
- Modify: `scripts/check-release-content.sh`
- Modify: `README.md`
- Modify: `THIRD_PARTY_NOTICES.md`

- [ ] **Step 1: Write shell and resource-verification checks before adding resources.**

  Add Gifsicle and Gifski resource assertions to `check-release-content.sh` alongside the three existing engines:

  ```bash
  for resource in \
      'gifsicle/gifsicle-arm64' 'gifsicle/gifsicle-x86_64' \
      'gifski/gifski-arm64' 'gifski/gifski-x86_64'; do
      [[ -f "${actual_mount_point}/PngCut.app/Contents/Resources/${resource}" ]] || fail "DMG missing engine resource: ${resource}"
  done
  ```

  Add `file` architecture assertions for each of the four files, and run `bash -n scripts/check-release-content.sh`. Expected before resource work: a DMG check fails with a missing GIF engine resource.

- [ ] **Step 2: Implement a pinned Gifsicle build script.**

  Create `build-gifsicle.sh` matching the locking/clean-checkout style of `build-oxipng.sh`, pinning `VERSION="v1.96"` and `REPOSITORY="https://github.com/kohler/gifsicle.git"`. For each architecture `arm64` and `x86_64`, configure a separate build directory with the macOS SDK compiler, disable X11-only tools, then install the executable:

  ```bash
  (cd "${CHECKOUT_DIRECTORY}" && autoreconf -fi)
  mkdir -p "${BUILD_DIRECTORY}"
  (
    cd "${BUILD_DIRECTORY}"
    CC="$(xcrun --sdk macosx --find clang) -arch ${architecture}" \
      "${CHECKOUT_DIRECTORY}/configure" --disable-gifview --disable-gifdiff
    make -j"$(sysctl -n hw.ncpu)" gifsicle
  )
  install -m 755 "${BUILD_DIRECTORY}/src/gifsicle" "${RESOURCE_DIRECTORY}/gifsicle-${architecture}"
  ```

  Copy upstream `COPYING` to `LICENSE-gifsicle`, require `git`, `autoreconf`, `make`, and `xcrun`, and fail when the checked-out tag is not exactly `v1.96`.

- [ ] **Step 3: Implement a pinned Gifski build script.**

  Create `build-gifski.sh` in the same style, pinning `VERSION="1.34.0"` and `REPOSITORY="https://github.com/ImageOptim/gifski.git"`. Require `git`, `cargo`, and `rustup`; build with `--release --locked` for `aarch64-apple-darwin` and `x86_64-apple-darwin`; install each target-triple’s `release/gifski` executable as `gifski-arm64` / `gifski-x86_64`; copy upstream `LICENSE` as `LICENSE-gifski`; verify `file` reports the requested architecture.

- [ ] **Step 4: Build, inspect, and add resources to the app target.**

  Run:

  ```bash
  ./scripts/build-gifsicle.sh
  ./scripts/build-gifski.sh
  file PngCut/Resources/gifsicle/gifsicle-arm64 PngCut/Resources/gifsicle/gifsicle-x86_64
  file PngCut/Resources/gifski/gifski-arm64 PngCut/Resources/gifski/gifski-x86_64
  ```

  Expected: each binary reports its matching architecture and each resource directory contains a license. Add both directories to the app resource group and `PBXResourcesBuildPhase`; do not add binaries to source phases.

- [ ] **Step 5: Update user and license documentation.**

  Update the README format table and copy with all confirmed behavior: GIF uses Gifsicle `-O3` or `-O3 --lossy=200`; PNG sequences require ten consecutive numbered same-size PNGs; global modes map sequences to Gifski quality 100/80; supported FPS choices are 20/25/30/custom 1–50; loop choices are infinite/once; source PNG frames are retained; and folder imports retain the `_pngcut` relative-output behavior. State clearly that the shared `无损` label maps sequence conversion to Gifski quality 100 for UI consistency, not a promise that a generated GIF is pixel-identical to its PNG frames.

  Add notices with exact resource paths and upstream URLs:

  ```markdown
  ## Gifsicle 1.96

  pngcut bundles Gifsicle as a separate local GIF command-line program. Its source is GPL-2.0-only; the bundled license is `Resources/gifsicle/LICENSE-gifsicle`.

  ## Gifski 1.34.0

  pngcut bundles Gifski as a separate local PNG-sequence-to-GIF command-line program. Its source is AGPL-3.0-or-later; the bundled license is `Resources/gifski/LICENSE-gifski`.
  ```

  Keep the project root GPL v3 text unchanged; include the documented upstream-source route and perform the stated release compliance review before publishing.

- [ ] **Step 6: Extend release-content requirements and run release checks.**

  Require Gifsicle/Gifski names, versions, license paths, `GIF`, and `PNG 序列` in the README/notices checks. Extend the DMG architecture checks. Then run:

  ```bash
  bash -n scripts/build-gifsicle.sh scripts/build-gifski.sh scripts/check-release-content.sh
  ./scripts/check-release-content.sh
  ```

  Expected: syntax check and content check both PASS.

- [ ] **Step 7: Commit resource and release changes.**

  Commit only the GIF resources, their scripts, project resource membership, and release documentation:

  ```bash
  git add scripts/build-gifsicle.sh scripts/build-gifski.sh scripts/check-release-content.sh \
    PngCut/Resources/gifsicle PngCut/Resources/gifski PngCut.xcodeproj/project.pbxproj \
    README.md THIRD_PARTY_NOTICES.md
  git commit -m "feat: bundle GIF processing engines"
  ```

### Task 7: Run integration verification and create the release artifact

**Files:**
- Modify if required by a failing test: only files named in Tasks 1–6
- Test: all existing `PngCutTests`, `PngCutUITests`, `scripts/check-release-content.sh`, `scripts/test-dmg-mount-cleanup.sh`

- [ ] **Step 1: Build a clean Debug app and exercise bundled resource resolution.**

  Run:

  ```bash
  xcodebuild -project PngCut.xcodeproj -scheme PngCut -configuration Debug \
    -derivedDataPath .build/DerivedData-GIF-Debug CODE_SIGNING_ALLOWED=NO build
  ```

  Expected: `** BUILD SUCCEEDED **` and the Debug app contains `gifsicle` and `gifski` directories under `Contents/Resources`.

- [ ] **Step 2: Run all tests and classify the complete result.**

  Run:

  ```bash
  xcodebuild -project PngCut.xcodeproj -scheme PngCut \
    -destination 'platform=macOS' test
  ```

  Expected: all unit tests, including GIF discovery, sequence routing, settings, adapters, queue, and output policy, pass; UI tests must be reported separately if any environment-dependent failure remains.

- [ ] **Step 3: Build the Release DMG and verify its payload.**

  Run:

  ```bash
  ./scripts/create-dmg.sh
  ./scripts/check-release-content.sh --dmg dist/PngCut-1.0.dmg
  ./scripts/test-dmg-mount-cleanup.sh dist/PngCut-1.0.dmg
  ```

  Expected: Release build succeeds, `hdiutil verify` succeeds, all five engine families are present in the mounted app, architecture checks pass, and the DMG is detached after both successful and induced-failure inspections.

- [ ] **Step 4: Inspect the final change set and commit any test-only corrections.**

  Run:

  ```bash
  git status --short
  git diff --check
  git log --oneline -7
  ```

  Expected: no unintended generated `.build`, `dist`, or test artifacts are staged; `git diff --check` prints nothing. If verification requires a source/test/doc correction, make that minimal correction, rerun the affected command from this task, and commit it with a message naming the corrected behavior.
