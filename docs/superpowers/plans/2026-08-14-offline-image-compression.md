# Offline PNG and JPEG Compression Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make pngcut a GPL v3, fully offline PNG/JPG/JPEG compressor using oxipng, pngquant, and MozJPEG.

**Architecture:** File discovery identifies supported formats. A per-task route maps PNG lossless to oxipng, PNG balanced to pngquant, and JPEG to MozJPEG. The existing queue receives a concrete `ImageCompressor` per task, while output policy preserves the source extension. Tinify and keychain state are removed.

**Tech Stack:** Swift 5.9, SwiftUI/AppKit, XCTest/XCUITest, bundled universal command-line binaries, Rust/Cargo, CMake, GPL v3.

---

### Task 1: Model supported formats and preserve output extensions

**Files:**

- Modify: `FFPNG/FFPNG/Services/FileDiscovery.swift`
- Modify: `FFPNG/FFPNG/Domain/CompressionTask.swift`
- Modify: `FFPNG/FFPNG/Domain/OutputPolicy.swift`
- Modify: `FFPNG/FFPNGTests/FileDiscoveryTests.swift`
- Modify: `FFPNG/FFPNGTests/OutputPolicyTests.swift`

- [ ] **Step 1: Write failing discovery and extension tests.**

```swift
func testDiscoverFindsPNGAndJPEGFilesRecursivelyIgnoringExtensionCase() throws {
    let png = try makeFile("icon.PNG", in: directory)
    let jpg = try makeFile("photo.JpG", in: directory)
    let jpeg = try makeFile("scan.JPEG", in: directory)
    _ = try makeFile("notes.pdf", in: directory)

    let result = FileDiscovery().discover(urls: [directory])

    XCTAssertEqual(Set(result.files), Set([png.standardizedFileURL, jpg.standardizedFileURL, jpeg.standardizedFileURL]))
    XCTAssertEqual(result.skippedNonImageCount, 1)
}

func testAdjacentJPEGOutputKeepsJPEGExtension() throws {
    let jpeg = directory.appendingPathComponent("photo.JPEG")
    try Data("source".utf8).write(to: jpeg)
    let prepared = try OutputPolicy.adjacent.prepare(source: jpeg)

    XCTAssertEqual(prepared.finalURL.lastPathComponent, "photo-optimized.jpeg")
    XCTAssertEqual(prepared.temporaryURL.pathExtension, "jpeg")
}
```

- [ ] **Step 2: Run the test to verify red.**

Run: `xcodebuild -project FFPNG/FFPNG.xcodeproj -scheme FFPNG -destination 'platform=macOS' -only-testing:FFPNGTests/FileDiscoveryTests -only-testing:FFPNGTests/OutputPolicyTests test`

Expected: JPG/JPEG discovery assertion fails and JPEG output is incorrectly named `.png`.

- [ ] **Step 3: Implement the minimal domain model.**

```swift
enum ImageFormat: String, Equatable, Sendable {
    case png, jpeg

    init?(url: URL) {
        switch url.pathExtension.lowercased() {
        case "png": self = .png
        case "jpg", "jpeg": self = .jpeg
        default: return nil
        }
    }
}

enum CompressionEngine: String, Equatable, Sendable {
    case oxipng, pngquant, mozjpeg
}
```

Make discovery accept those formats and count every other regular file in `skippedNonImageCount`. Add `format`, `engine`, and `displayMode` to `CompressionTask`. In `OutputPolicy`, use `source.pathExtension.lowercased()` for final and temporary extensions rather than hard-coded PNG.

- [ ] **Step 4: Run the targeted tests to verify green.**

Run: same command as Step 2.

Expected: all selected tests pass.

### Task 2: Bundle local pngquant and MozJPEG compressors

**Files:**

- Create: `FFPNG/scripts/build-pngquant.sh`
- Create: `FFPNG/scripts/build-mozjpeg.sh`
- Create: `FFPNG/FFPNG/Services/PngquantCompressor.swift`
- Create: `FFPNG/FFPNG/Services/MozJPEGCompressor.swift`
- Create: `FFPNG/FFPNGTests/PngquantCompressorTests.swift`
- Create: `FFPNG/FFPNGTests/MozJPEGCompressorTests.swift`
- Modify: `FFPNG/FFPNG/Services/ImageCompressor.swift`
- Modify: `FFPNG/FFPNG/Services/OxipngCompressor.swift`
- Modify: `FFPNG/FFPNG.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing injected-executable tests.**

```swift
func testPngquantUsesQualityRangeAndWritesTemporaryDestination() async throws {
    let executable = try makeScript("""
    #!/bin/sh
    test "$1" = "--quality=65-80" || exit 9
    cp "$6" "$5"
    """)
    let compressor = PngquantCompressor(resolver: FixedResolver(url: executable))

    try await compressor.compress(source: sourcePNG, temporaryDestination: destinationPNG, progress: { _ in })

    XCTAssertEqual(try Data(contentsOf: destinationPNG), try Data(contentsOf: sourcePNG))
}
```

Add equivalent MozJPEG tests covering successful output, non-zero exit mapped to `.localExecution`, and zero-exit missing output mapped to `.outputValidation`.

- [ ] **Step 2: Run the compressor tests to verify red.**

Run: `xcodebuild -project FFPNG/FFPNG.xcodeproj -scheme FFPNG -destination 'platform=macOS' -only-testing:FFPNGTests/PngquantCompressorTests -only-testing:FFPNGTests/MozJPEGCompressorTests test`

Expected: compiler errors because the two compressor types do not exist.

- [ ] **Step 3: Implement process wrappers and resolvers.**

Extract oxipng’s stderr-draining `Process` logic into an internal reusable runner. Implement architecture-aware resolvers matching the `oxipng-arm64` and `oxipng-x86_64` resource convention.

`PngquantCompressor` invokes:

```swift
["--quality=65-80", "--speed", "4", "--skip-if-larger",
 "--output", temporaryDestination.path, source.path]
```

Map pngquant exit status 99 to a no-op by copying the source to the temporary destination; map every other non-zero status to `.localExecution`.

`MozJPEGCompressor` runs the bundled pinned MozJPEG recompression helper, writes only to `temporaryDestination`, and validates a non-empty JPEG. The helper decodes an existing JPEG and re-encodes it with the documented balanced quality while retaining EXIF orientation and ICC profile.

- [ ] **Step 4: Add repeatable universal-binary builders.**

`build-pngquant.sh` pins an upstream tag/commit, builds aarch64 and x86_64, and installs `pngquant-arm64`, `pngquant-x86_64`, and GPL notices into `Resources/pngquant/`.

`build-mozjpeg.sh` pins a tagged release, builds both architectures with CMake, builds the helper and dependencies, and installs `mozjpeg-arm64`, `mozjpeg-x86_64`, and licenses into `Resources/mozjpeg/`. Both scripts copy the existing lock/clean-checkout safety pattern from `build-oxipng.sh`.

- [ ] **Step 5: Add project references, build resources, and verify green.**

Run: `./FFPNG/scripts/build-pngquant.sh && ./FFPNG/scripts/build-mozjpeg.sh && xcodebuild -project FFPNG/FFPNG.xcodeproj -scheme FFPNG -destination 'platform=macOS' -only-testing:FFPNGTests/PngquantCompressorTests -only-testing:FFPNGTests/MozJPEGCompressorTests test`

Expected: scripts report both Mach-O architectures and all selected tests pass.

### Task 3: Replace Tinify routing with offline, format-aware routing

**Files:**

- Modify: `FFPNG/FFPNG/App/AppModel.swift`
- Delete: `FFPNG/FFPNG/Services/TinifyCompressor.swift`
- Delete: `FFPNG/FFPNG/Services/KeychainStore.swift`
- Delete: `FFPNG/FFPNGTests/TinifyCompressorTests.swift`
- Delete: `FFPNG/FFPNGTests/KeychainStoreTests.swift`
- Modify: `FFPNG/FFPNGTests/FFPNGTests.swift`
- Modify: `FFPNG/FFPNG.xcodeproj/project.pbxproj`

- [ ] **Step 1: Write failing route tests with no API key.**

```swift
func testBalancedPNGUsesPngquantWithoutAPIKey() async throws {
    let model = AppModel(loadPersistedSettings: false, compressorFactory: makeRecordingFactory())
    model.setCompressionMode(.balanced)
    model.add(urls: [pngURL])

    XCTAssertEqual(await recorder.engines(), [.pngquant])
}

func testJPEGAlwaysUsesMozJPEGWhenLosslessPNGPreferenceIsSelected() async throws {
    let model = AppModel(loadPersistedSettings: false, compressorFactory: makeRecordingFactory())
    model.add(urls: [jpegURL])

    XCTAssertEqual(await recorder.engines(), [.mozjpeg])
    XCTAssertEqual(model.tasks.first?.displayMode, .balanced)
}
```

- [ ] **Step 2: Run the model test to verify red.**

Run: `xcodebuild -project FFPNG/FFPNG.xcodeproj -scheme FFPNG -destination 'platform=macOS' -only-testing:FFPNGTests/FFPNGTests test`

Expected: the current balanced path rejects a missing Tinify API key.

- [ ] **Step 3: Implement offline routing.**

Change the compressor factory to `(CompressionEngine) -> any ImageCompressor`. Remove API-key persistence, validation, Keychain injection, Tinify messages, and retry substitution. At enqueue, select `.oxipng` for lossless PNG, `.pngquant` for balanced PNG, and `.mozjpeg` for every JPEG. Keep the queue’s existing per-task compressor and output collision protections.

- [ ] **Step 4: Run model and queue tests to verify green.**

Run: `xcodebuild -project FFPNG/FFPNG.xcodeproj -scheme FFPNG -destination 'platform=macOS' -only-testing:FFPNGTests/FFPNGTests -only-testing:FFPNGTests/CompressionQueueTests test`

Expected: all selected tests pass with no Tinify or Keychain references.

### Task 4: Update the native UI and sliding mode indicator

**Files:**

- Modify: `FFPNG/FFPNG/Views/MainWindowView.swift`
- Modify: `FFPNG/FFPNG/Views/SettingsDrawerView.swift`
- Modify: `FFPNG/FFPNG/Views/TaskRowView.swift`
- Modify: `FFPNG/FFPNGUITests/FFPNGUITests.swift`

- [ ] **Step 1: Replace obsolete API UI tests with failing offline UI tests.**

```swift
func testBalancedModeIsAvailableWithoutAnAPIKey() {
    XCTAssertTrue(app.buttons["modeShortcutBalanced"].isEnabled)
}

func testSettingsContainNoTinifyControls() {
    app.buttons["settingsButton"].tap()
    XCTAssertFalse(app.textFields["tinifyAPIKeyField"].exists)
    XCTAssertTrue(app.staticTexts["压缩方式"].exists)
}
```

- [ ] **Step 2: Run UI tests to verify red.**

Run: `xcodebuild -project FFPNG/FFPNG.xcodeproj -scheme FFPNG -destination 'platform=macOS' -only-testing:FFPNGUITests test`

Expected: failures because balanced is disabled and API controls are visible.

- [ ] **Step 3: Implement format-aware copy and native slider motion.**

Allow `.png`, `.jpeg`, and `.folder` in the picker; change Chinese picker/drop copy to PNG/JPG and skipped copy to “非图片文件”. Remove API content from settings and make balanced always enabled. In `CompressionModeShortcut`, add one selection capsule whose horizontal offset is derived from `settings.mode`; apply only `.animation(.default, value: model.settings.mode)`. Do not animate opacity and do not supply a custom `Animation` curve.

Give the capsule `modeSlider` and buttons stable accessibility identifiers. Render each task’s `displayMode.title`; reserve engine name for accessibility only.

- [ ] **Step 4: Run UI tests and a debug build to verify green.**

Run: `xcodebuild -project FFPNG/FFPNG.xcodeproj -scheme FFPNG -destination 'platform=macOS' -only-testing:FFPNGUITests test && xcodebuild -project FFPNG/FFPNG.xcodeproj -scheme FFPNG -configuration Debug CODE_SIGNING_ALLOWED=NO build`

Expected: all UI tests pass; the debug build succeeds.

### Task 5: Publish GPL documents and create a final DMG

**Files:**

- Create: `FFPNG/LICENSE`
- Modify: `FFPNG/README.md`
- Modify: `FFPNG/THIRD_PARTY_NOTICES.md`
- Modify: `FFPNG/scripts/create-dmg.sh`

- [ ] **Step 1: Write a failing release-content check.**

```bash
test -f FFPNG/LICENSE
grep -q 'GNU GENERAL PUBLIC LICENSE' FFPNG/LICENSE
grep -q 'pngquant' FFPNG/THIRD_PARTY_NOTICES.md
grep -q 'MozJPEG' FFPNG/THIRD_PARTY_NOTICES.md
```

- [ ] **Step 2: Run it to verify red.**

Run: `test -f FFPNG/LICENSE && grep -q 'pngquant' FFPNG/THIRD_PARTY_NOTICES.md`

Expected: non-zero exit before GPL material exists.

- [ ] **Step 3: Add licensing and user documentation.**

Add unmodified GPL v3 text as `LICENSE`. Rewrite README to document PNG/JPG/JPEG support, all-local compression, engines, quality/no-larger behavior, source availability, and unsigned Gatekeeper opening steps. Replace the Tinify notice with pinned pngquant GPL and MozJPEG notices; bundle their license files through the resource phase.

- [ ] **Step 4: Build, test, package, and verify the new DMG.**

Run: `xcodebuild -project FFPNG/FFPNG.xcodeproj -scheme FFPNG -destination 'platform=macOS' test && ./FFPNG/scripts/create-dmg.sh && hdiutil verify FFPNG/dist/pngcut-1.0.dmg`

Expected: tests pass, disk-image verification is valid, and the DMG contains pngcut.app plus Applications.

- [ ] **Step 5: Inspect the release and record its checksum.**

Run: `file FFPNG/.build/DerivedData-Release/Build/Products/Release/pngcut.app/Contents/MacOS/pngcut FFPNG/.build/DerivedData-Release/Build/Products/Release/pngcut.app/Contents/Resources/pngquant/pngquant-arm64 FFPNG/.build/DerivedData-Release/Build/Products/Release/pngcut.app/Contents/Resources/mozjpeg/mozjpeg-arm64 && shasum -a 256 FFPNG/dist/pngcut-1.0.dmg`

Expected: universal app executable, arm64 bundled engines, and an SHA-256 for the unsigned/unnotarized DMG.

