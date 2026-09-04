# PngCut Import Decision Reliability Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Replace invisible GIF-import alerts with one in-window decision overlay so every required user choice is visible, blocks new imports clearly, and always releases the import pipeline afterwards.

**Architecture:** `AppModel` will expose one `ImportDecision?` state instead of separate prompt and notice state. `MainWindowView` will render that state through a single `ImportDecisionOverlay` above the whole window and reject new import entry points while the overlay exists. Model tests own state transitions and FIFO recovery; UI tests exercise deterministic launch scenarios and accessibility identifiers.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, XCTest/XCUITest, Xcode project `macos/PngCut.xcodeproj`.

---

## File structure

- Modify: `macos/PngCut/App/AppModel.swift` — replace `ImportPrompt`/`ImportNotice` with a single decision state and atomic resolution methods.
- Modify: `macos/PngCut/Views/MainWindowView.swift` — remove both alert modifiers, add the full-window overlay, and block drag/drop and file-picking while a decision is active.
- Modify: `macos/PngCut/App/PngCutApp.swift` — add Debug-only, launch-argument-driven model construction for deterministic UI tests.
- Modify: `macos/PngCutTests/PngCutTests.swift` — migrate existing GIF import tests to the new public model API and add recovery regression coverage.
- Modify: `macos/PngCutUITests/PngCutUITests.swift` — verify overlay visibility, action flow, and input locking with launch arguments.
- Modify: `.gitignore` — ignore the local `.superpowers/` visual-companion session directory created during design.

Current working tree note: `macos/PngCut/App/AppModel.swift` and `macos/PngCut/Views/MainWindowView.swift` contain the known, uncommitted privacy-safe import diagnostics from the prior investigation. Retain them and include each in the corresponding Task 2 or Task 3 feature commit. Do not stage `.superpowers/`.

### Task 1: Define and prove the model-level recovery contract

**Files:**
- Modify: `macos/PngCutTests/PngCutTests.swift:529-803`
- Test: `macos/PngCutTests/PngCutTests.swift`

- [ ] **Step 1: Replace current prompt assertions and add the regression test before changing production code.**

  In `GIFImportAppModelTests`, change existing references to `pendingImportPrompt`, `resolvePendingImport`, `importNotice`, and `dismissImportNotice` to the planned names below. Add this test after `testRegularImagesWithoutCandidateAndConversionEnabledShowNoticeWhenDeclined`:

  ```swift
  func testDecliningNoSequenceNoticeUnlocksTheNextImport() async throws {
      let directory = try makeTemporaryDirectory("PngCut-DecisionRecoveryTests")
      defer { try? FileManager.default.removeItem(at: directory) }
      let first = try makeSourceFile(named: "first.png", in: directory)
      let second = try makeSourceFile(named: "second.png", in: directory)
      let model = AppModel(
          settings: AppSettings(gif: GIFSettings(isPNGSequenceConversionEnabled: true)),
          loadPersistedSettings: false,
          sequenceDetector: ModelSequenceDetector()
      )

      model.add(urls: [first])
      XCTAssertTrue(await waitUntil { model.activeImportDecision != nil })
      guard case .noSequenceDetected? = model.activeImportDecision else {
          return XCTFail("Expected the no-sequence decision")
      }

      model.resolveNoSequenceDecision(compressInstead: false)
      XCTAssertEqual(model.activeImportDecision, .noSequenceNotice)
      XCTAssertTrue(model.settings.gif.isPNGSequenceConversionEnabled)
      XCTAssertTrue(model.tasks.isEmpty)

      model.dismissNoSequenceNotice()
      XCTAssertNil(model.activeImportDecision)

      model.add(urls: [second])
      XCTAssertTrue(await waitUntil { model.activeImportDecision != nil })
      guard case let .noSequenceDetected(resolution)? = model.activeImportDecision else {
          return XCTFail("Expected the second import to be accepted")
      }
      XCTAssertEqual(resolution.regularImages.map(\.fileURL), [second])
  }
  ```

  Update the existing sequence tests to assert `case .sequenceDetected` and call `resolveSequenceDecision(convertSequence:)`; update the no-sequence tests to assert `case .noSequenceDetected`, call `resolveNoSequenceDecision(compressInstead:)`, and assert `case .noSequenceNotice` instead of a second notice property.

- [ ] **Step 2: Run only the affected model tests and confirm the API is missing.**

  Run:

  ```bash
  xcodebuild -project macos/PngCut.xcodeproj -scheme PngCut -configuration Debug \
    -derivedDataPath macos/.build/DerivedData-Debug CODE_SIGNING_ALLOWED=NO \
    -only-testing:PngCutTests/GIFImportAppModelTests \
    test
  ```

  Expected: compilation fails because `activeImportDecision`, `resolveSequenceDecision`, `resolveNoSequenceDecision`, and `dismissNoSequenceNotice` do not exist yet.

- [ ] **Step 3: Commit the test-only red state only if the repository policy permits red commits; otherwise leave it unstaged and continue immediately.**

  This repository normally keeps commits green, so do not create a red commit. Verify the diff contains only test names and assertions described above.

### Task 2: Implement one atomic import-decision state machine

**Files:**
- Modify: `macos/PngCut/App/AppModel.swift:42-79, 130-136, 234-270, 304-333`
- Test: `macos/PngCutTests/PngCutTests.swift`

- [ ] **Step 1: Replace the two presentation types with one decision type.**

  Delete `ImportPrompt` and `ImportNotice`. In the same location, add:

  ```swift
  enum ImportDecision: Identifiable, Equatable, Sendable {
      case sequenceDetected(ImportResolution)
      case noSequenceDetected(ImportResolution)
      case noSequenceNotice

      var id: String {
          switch self {
          case let .sequenceDetected(resolution):
              "sequence-\(resolution.id.uuidString)"
          case let .noSequenceDetected(resolution):
              "no-sequence-\(resolution.id.uuidString)"
          case .noSequenceNotice:
              "no-sequence-notice"
          }
      }
  }
  ```

  Replace the published and stored import fields with:

  ```swift
  @Published private(set) var activeImportDecision: ImportDecision?
  private var pendingImportResolutions: [ImportResolution] = []
  ```

  Remove `pendingImportPrompt`, `importNotice`, and `activeImportResolution` completely. Add this read-only property next to the existing output properties:

  ```swift
  var isImportDecisionPresented: Bool {
      activeImportDecision != nil
  }
  ```

- [ ] **Step 2: Replace the old resolution methods with methods whose first operation releases the visible decision.**

  ```swift
  func resolveSequenceDecision(convertSequence: Bool) {
      guard case let .sequenceDetected(resolution)? = activeImportDecision else { return }
      activeImportDecision = nil
      if convertSequence {
          updateGIFSettings { $0.isPNGSequenceConversionEnabled = true }
          prepareAndEnqueueConvertedSequences(resolution)
      } else {
          enqueueRegularImages(in: resolution, includingSequenceFrames: true)
      }
      processNextImportResolutionIfPossible()
  }

  func resolveNoSequenceDecision(compressInstead: Bool) {
      guard case let .noSequenceDetected(resolution)? = activeImportDecision else { return }
      if compressInstead {
          activeImportDecision = nil
          updateGIFSettings { $0.isPNGSequenceConversionEnabled = false }
          enqueueRegularImages(in: resolution, includingSequenceFrames: false)
          processNextImportResolutionIfPossible()
      } else {
          activeImportDecision = .noSequenceNotice
      }
  }

  func dismissNoSequenceNotice() {
      guard case .noSequenceNotice? = activeImportDecision else { return }
      activeImportDecision = nil
      processNextImportResolutionIfPossible()
  }
  ```

  In `processNextImportResolutionIfPossible`, replace the old guard with:

  ```swift
  guard activeImportDecision == nil, !isPreparingSequenceImport else { return }
  ```

  Replace the two prompt assignments with `.sequenceDetected(resolution)` and `.noSequenceDetected(resolution)`. Keep the two direct-processing paths unchanged.

- [ ] **Step 3: Run the focused model suite and confirm it passes.**

  Run the Task 1 command again.

  Expected: `GIFImportAppModelTests` passes, including the new “decline → notice → next import” recovery test and FIFO prompt tests.

- [ ] **Step 4: Commit the model change and its tests.**

  ```bash
  git add macos/PngCut/App/AppModel.swift macos/PngCutTests/PngCutTests.swift
  git commit -m "fix: make GIF import decisions recoverable"
  ```

### Task 3: Add a single full-window decision overlay and deterministic UI launch scenarios

**Files:**
- Modify: `macos/PngCut/Views/MainWindowView.swift:40-286`
- Modify: `macos/PngCut/App/PngCutApp.swift:5-18`
- Modify: `macos/PngCut/App/AppModel.swift`
- Modify: `macos/PngCutUITests/PngCutUITests.swift`

- [ ] **Step 1: Write two failing UI tests that use explicit launch arguments.**

  Add launch arguments before `app.launch()` in the specific tests, then assert the following stable identifiers:

  ```swift
  func testNoSequenceDecisionBlocksImportUntilNoticeIsAcknowledged() {
      app.terminate()
      app.launchArguments = ["--ui-test-no-sequence-decision"]
      app.launch()

      XCTAssertTrue(app.otherElements["importDecisionOverlay"].waitForExistence(timeout: 2))
      XCTAssertFalse(app.buttons["chooseFilesButton"].isEnabled)
      XCTAssertTrue(app.buttons["importDecisionDecline"].isHittable)

      app.buttons["importDecisionDecline"].tap()
      XCTAssertTrue(app.staticTexts["当前文件夹没有 PNG 序列，无法转 GIF"].waitForExistence(timeout: 2))
      app.buttons["importDecisionAcknowledge"].tap()

      XCTAssertFalse(app.otherElements["importDecisionOverlay"].exists)
      XCTAssertTrue(app.buttons["chooseFilesButton"].isEnabled)
  }

  func testSequenceDecisionShowsBothExplicitActions() {
      app.terminate()
      app.launchArguments = ["--ui-test-sequence-decision"]
      app.launch()

      XCTAssertTrue(app.otherElements["importDecisionOverlay"].waitForExistence(timeout: 2))
      XCTAssertTrue(app.buttons["importDecisionConvert"].isHittable)
      XCTAssertTrue(app.buttons["importDecisionCompress"].isHittable)
      XCTAssertFalse(app.buttons["chooseFilesButton"].isEnabled)
  }
  ```

- [ ] **Step 2: Run the UI tests and confirm they fail because neither the overlay nor launch scenarios exists.**

  Run:

  ```bash
  xcodebuild -project macos/PngCut.xcodeproj -scheme PngCut -configuration Debug \
    -derivedDataPath macos/.build/DerivedData-Debug CODE_SIGNING_ALLOWED=NO \
    -only-testing:PngCutUITests/PngCutUITests/testNoSequenceDecisionBlocksImportUntilNoticeIsAcknowledged \
    -only-testing:PngCutUITests/PngCutUITests/testSequenceDecisionShowsBothExplicitActions \
    test
  ```

  Expected: FAIL because `importDecisionOverlay` never appears.

- [ ] **Step 3: Add Debug-only launch models in `AppModel` and `PngCutApp`.**

  Add the following factory inside `AppModel` (outside all existing methods) and keep it Debug-only:

  ```swift
  #if DEBUG
  static func uiTestModel(arguments: [String]) -> AppModel? {
      let model = AppModel(loadPersistedSettings: false)
      if arguments.contains("--ui-test-no-sequence-decision") {
          model.activeImportDecision = .noSequenceDetected(
              ImportResolution(regularImages: [], sequences: [])
          )
          return model
      }
      if arguments.contains("--ui-test-sequence-decision") {
          let frameURLs = (1...10).map {
              URL(fileURLWithPath: "/tmp/pngcut-ui-test/walk_\(String(format: "%04d", $0)).png")
          }
          let sequence = PNGSequence(
              frameURLs: frameURLs,
              importedFolderRoot: nil,
              outputFileName: "walk.gif"
          )
          model.activeImportDecision = .sequenceDetected(
              ImportResolution(regularImages: [], sequences: [sequence])
          )
          return model
      }
      return nil
  }
  #endif
  ```

  Change `PngCutApp` to initialize its state object in `init`:

  ```swift
  @StateObject private var model: AppModel

  init() {
  #if DEBUG
      if let model = AppModel.uiTestModel(arguments: ProcessInfo.processInfo.arguments) {
          _model = StateObject(wrappedValue: model)
      } else {
          _model = StateObject(wrappedValue: AppModel())
      }
  #else
      _model = StateObject(wrappedValue: AppModel())
  #endif
      NSApplication.shared.appearance = NSAppearance(named: .aqua)
  }
  ```

  The UI tests only inspect the seeded sequence decision; they do not start encoding the placeholder URLs. The launch arguments and seed factory are omitted entirely from Release builds.

- [ ] **Step 4: Replace both `.alert` modifiers with one overlay.**

  Keep the root `VStack`, but add a single overlay after `.preferredColorScheme`:

  ```swift
  .overlay {
      if let decision = model.activeImportDecision {
          ImportDecisionOverlay(
              decision: decision,
              accent: accent,
              resolveSequence: model.resolveSequenceDecision,
              resolveNoSequence: model.resolveNoSequenceDecision,
              acknowledgeNotice: model.dismissNoSequenceNotice
          )
          .accessibilityIdentifier("importDecisionOverlay")
      }
  }
  ```

  Implement `ImportDecisionOverlay` in this file. It must contain an opaque hit-testable dimming background, a centered rounded white card, and these exact controls:

  | Decision | Title | Buttons and identifiers |
  | --- | --- | --- |
  | `.sequenceDetected` | `发现 PNG 序列` | `转 GIF` / `importDecisionConvert`; `常规压缩` / `importDecisionCompress` |
  | `.noSequenceDetected` | `未发现 PNG 序列` | `常规压缩` / `importDecisionCompress`; `不压缩` / `importDecisionDecline` |
  | `.noSequenceNotice` | `无法转 GIF` | `好` / `importDecisionAcknowledge` |

  Use `PrimaryButtonStyle(accent:)` for the affirmative action and a plain bordered style for the secondary action. Do not add a close button or background tap handler.

  Implement the overlay with this structure, keeping all actions injected from `MainWindowView`:

  ```swift
  private struct ImportDecisionOverlay: View {
      let decision: ImportDecision
      let accent: Color
      let resolveSequence: (Bool) -> Void
      let resolveNoSequence: (Bool) -> Void
      let acknowledgeNotice: () -> Void

      var body: some View {
          ZStack {
              Color.black.opacity(0.28)
                  .ignoresSafeArea()
                  .contentShape(Rectangle())

              VStack(alignment: .leading, spacing: 14) {
                  Text(title).font(.system(size: 17, weight: .semibold))
                  Text(message).font(.system(size: 13)).foregroundStyle(.secondary)
                  Text("请先完成当前导入选择")
                      .font(.system(size: 11))
                      .foregroundStyle(.secondary)
                  HStack(spacing: 10) { actions }
              }
              .padding(22)
              .frame(width: 360, alignment: .leading)
              .background(Color.white)
              .clipShape(RoundedRectangle(cornerRadius: 10, style: .continuous))
              .shadow(color: .black.opacity(0.2), radius: 18, y: 8)
          }
      }

      private var title: String {
          switch decision {
          case .sequenceDetected: "发现 PNG 序列"
          case .noSequenceDetected: "未发现 PNG 序列"
          case .noSequenceNotice: "无法转 GIF"
          }
      }

      private var message: String {
          switch decision {
          case let .sequenceDetected(resolution): resolution.convertMessage
          case .noSequenceDetected: "是否按常规方式压缩当前文件？"
          case .noSequenceNotice: "当前文件夹没有 PNG 序列，无法转 GIF"
          }
      }

      @ViewBuilder private var actions: some View {
          Spacer()
          switch decision {
          case .sequenceDetected:
              Button("常规压缩") { resolveSequence(false) }
                  .buttonStyle(.bordered)
                  .accessibilityIdentifier("importDecisionCompress")
              Button("转 GIF") { resolveSequence(true) }
                  .buttonStyle(PrimaryButtonStyle(accent: accent))
                  .accessibilityIdentifier("importDecisionConvert")
          case .noSequenceDetected:
              Button("不压缩") { resolveNoSequence(false) }
                  .buttonStyle(.bordered)
                  .accessibilityIdentifier("importDecisionDecline")
              Button("常规压缩") { resolveNoSequence(true) }
                  .buttonStyle(PrimaryButtonStyle(accent: accent))
                  .accessibilityIdentifier("importDecisionCompress")
          case .noSequenceNotice:
              Button("好", action: acknowledgeNotice)
                  .buttonStyle(PrimaryButtonStyle(accent: accent))
                  .accessibilityIdentifier("importDecisionAcknowledge")
          }
      }
  }
  ```

  Delete `importPromptBinding` and `importNoticeBinding` entirely.

- [ ] **Step 5: Lock every import entry point while the overlay is present.**

  Add the same guard to both import functions:

  ```swift
  private func chooseFiles() {
      guard !model.isImportDecisionPresented else { return }
      // existing panel code
  }

  private func acceptDrop(_ providers: [NSItemProvider]) -> Bool {
      guard !model.isImportDecisionPresented else { return false }
      // existing provider code
  }
  ```

  Apply `.disabled(model.isImportDecisionPresented)` to `EmptyDropView` and to the “添加文件” button. Ensure the overlay is above the settings drawer and bottom bar so it intercepts their clicks while leaving their visual layout unchanged.

  The two source edits are:

  ```swift
  EmptyDropView(/* existing arguments */)
      .disabled(model.isImportDecisionPresented)

  Button("添加文件", action: chooseFiles)
      .disabled(model.isImportDecisionPresented)
      .buttonStyle(.borderless)
  ```

- [ ] **Step 6: Run the focused UI tests and confirm they pass.**

  Run the Task 3 Step 2 command again.

  Expected: both tests pass; the first verifies the sequence “decision → no-sequence notice → acknowledge → input unlocked.”

- [ ] **Step 7: Commit the UI implementation and UI tests.**

  ```bash
  git add macos/PngCut/App/AppModel.swift macos/PngCut/App/PngCutApp.swift macos/PngCut/Views/MainWindowView.swift macos/PngCutUITests/PngCutUITests.swift
  git commit -m "fix: show GIF import decisions in app"
  ```

### Task 4: Clean local design artifacts and verify the release package

**Files:**
- Modify: `.gitignore`
- Verify: `macos/scripts/create-dmg.sh`

- [ ] **Step 1: Ignore local visual-companion artifacts.**

  Add this exact entry under the local-artifact sections of `.gitignore`:

  ```gitignore
  # Local brainstorming visual-companion sessions
  .superpowers/
  ```

  Do not delete the session directory as part of the implementation; Git will simply stop reporting it.

- [ ] **Step 2: Run the complete macOS test suite.**

  Run:

  ```bash
  xcodebuild -project macos/PngCut.xcodeproj -scheme PngCut -configuration Debug \
    -derivedDataPath macos/.build/DerivedData-Debug CODE_SIGNING_ALLOWED=NO \
    test
  ```

  Expected: all unit and UI tests pass. If the host again reports an Xcode automation-service startup error before test execution, record it as environment infrastructure failure, then rerun the model suite and the Release build; do not call the UI tests passing.

- [ ] **Step 3: Build and validate the DMG.**

  Run:

  ```bash
  ./scripts/create-dmg.sh
  ```

  from `macos/`.

  Expected: `** BUILD SUCCEEDED **`, `release-content check passed`, and a verified `macos/dist/PngCut-1.0.0.dmg`.

- [ ] **Step 4: Review exact staged content, then commit the ignore rule.**

  ```bash
  git add .gitignore
  git diff --cached --check
  git diff --cached --stat
  git commit -m "chore: ignore local brainstorm files"
  git status --short
  ```

  Expected: working tree contains no product-source changes. The generated `macos/dist/` DMG remains ignored and is not committed.
