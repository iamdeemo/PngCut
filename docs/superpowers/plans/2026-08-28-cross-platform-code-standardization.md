# Cross-Platform Code Standardization Implementation Plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Make macOS and Windows PngCut clients obey one versioned PNG/JPEG behavior contract while retaining separate native UI, filesystem, process, binary, and release implementations.

**Architecture:** Add JSON contract data and logical-path fixtures under `shared/`; add XCTest and NUnit adapters that consume those same files; then make each platform conform where its current behavior differs. Platform-only filesystem cases remain in the shared documents with an explicit platform selector, while every `all` case runs on both systems.

**Tech Stack:** Swift 5.9/XCTest/Foundation, C#/.NET Framework 4.8/NUnit, JSONDecoder, System.Web.Extensions JavaScriptSerializer, Bash, PowerShell, GitHub Actions.

---

## File structure

| File | Responsibility |
| --- | --- |
| `shared/contracts/v1/behavior.json` | Versioned formats, modes, engines, task lifecycle, no-change and output invariants. |
| `shared/contracts/v1/discovery-cases.json` | Cross-platform and platform-only input discovery test vectors. |
| `shared/contracts/v1/output-policy-cases.json` | Logical output-name, collision, overwrite and folder-output vectors. |
| `shared/contracts/v1/error-catalog.json` | Stable failure codes and user-visible Simplified Chinese messages. |
| `shared/contracts/v1/engine-manifest.json` | Engine versions, tags, source revisions and license identifiers. |
| `shared/fixtures/README.md` | Rules for mapping logical fixture paths to platform temporary directories. |
| `macos/PngCutTests/Support/SharedContractLoader.swift` | XCTest-only Codable loader for shared JSON. |
| `macos/PngCutTests/SharedContractDocumentTests.swift` | macOS contract document and vector execution tests. |
| `macos/PngCut/Services/FailureCatalog.swift` | macOS typed failure codes and presentation mapping. |
| `windows/PngCut.Tests/SharedContractDocumentTests.cs` | Windows contract document and vector execution tests. |
| `windows/src/PngCut.Core/Services/FailureCatalog.cs` | Windows typed failure codes and presentation mapping. |
| `macos/PngCut/Domain/OutputPolicy.swift` | macOS output policy parity and typed policy failures. |
| `windows/src/PngCut.Core/Services/OutputPolicy.cs` | Windows output naming and existing-custom-directory parity. |
| `macos/PngCut/Services/ImageCompressor.swift` | macOS typed compressor failures. |
| `macos/PngCut/Services/CompressionQueue.swift` | macOS failure propagation to the task queue. |
| `windows/src/PngCut.Core/Models/CompressionTask.cs` | Windows task failure-code snapshot. |
| `windows/src/PngCut.Engine/CompressionQueue.cs` | Windows typed failure propagation. |
| `macos/scripts/build-*.sh` | Reads pinned macOS engine tags from the shared manifest. |
| `windows/build/Test-ReleaseLayout.ps1` | Verifies packaged Windows resources against the shared manifest. |
| `.github/workflows/release.yml` | Runs macOS unit/contract tests before the DMG build. |

### Task 1: Create the versioned shared contract and document readers

**Files:**
- Create: `shared/contracts/v1/behavior.json`
- Create: `shared/contracts/v1/discovery-cases.json`
- Create: `shared/contracts/v1/output-policy-cases.json`
- Create: `shared/contracts/v1/error-catalog.json`
- Create: `shared/contracts/v1/engine-manifest.json`
- Create: `shared/fixtures/README.md`
- Create: `macos/PngCutTests/Support/SharedContractLoader.swift`
- Create: `macos/PngCutTests/SharedContractDocumentTests.swift`
- Create: `windows/PngCut.Tests/SharedContractDocumentTests.cs`
- Modify: `macos/PngCut.xcodeproj/project.pbxproj`
- Modify: `windows/PngCut.Tests/PngCut.Tests.csproj`
- Modify: `README.md`

- [ ] **Step 1: Add failing macOS and Windows document-presence tests.**

  Add `SharedContractDocumentTests.swift` to the `PngCutTests` target with this first test; use the source file location so the test works in a clean CI checkout:

  ```swift
  import XCTest
  @testable import PngCut

  final class SharedContractDocumentTests: XCTestCase {
      func testSharedContractDocumentsExist() {
          let root = URL(fileURLWithPath: #filePath)
              .deletingLastPathComponent()
              .deletingLastPathComponent()
              .deletingLastPathComponent()
          for name in ["behavior.json", "discovery-cases.json", "output-policy-cases.json", "error-catalog.json", "engine-manifest.json"] {
              XCTAssertTrue(FileManager.default.fileExists(
                  atPath: root.appendingPathComponent("shared/contracts/v1/\(name)").path
              ))
          }
      }
  }
  ```

  Add `SharedContractDocumentTests.cs` to the Windows test project with this first test:

  ```csharp
  using System.IO;
  using NUnit.Framework;

  namespace PngCut.Tests;

  public class SharedContractDocumentTests
  {
      [TestCase("behavior.json")]
      [TestCase("discovery-cases.json")]
      [TestCase("output-policy-cases.json")]
      [TestCase("error-catalog.json")]
      [TestCase("engine-manifest.json")]
      public void Shared_contract_document_is_copied_to_test_output(string name)
      {
          Assert.That(File.Exists(Path.Combine(TestContext.CurrentContext.TestDirectory, "Contracts", name)), Is.True);
      }
  }
  ```

  Add the Swift file to a new `Support` test group and the `PngCutTests` sources phase in `macos/PngCut.xcodeproj/project.pbxproj`. Add the following Windows test-content item and framework reference to `windows/PngCut.Tests/PngCut.Tests.csproj`:

  ```xml
  <ItemGroup>
    <Reference Include="System.Web.Extensions" />
    <None Include="..\..\shared\contracts\v1\*.json">
      <Link>Contracts\%(Filename)%(Extension)</Link>
      <CopyToOutputDirectory>PreserveNewest</CopyToOutputDirectory>
    </None>
  </ItemGroup>
  ```

- [ ] **Step 2: Run the presence tests and verify the intended red state.**

  Run on macOS:

  ```bash
  xcodebuild -project macos/PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutTests/SharedContractDocumentTests test
  ```

  Expected: `testSharedContractDocumentsExist` fails because `shared/contracts/v1/behavior.json` is absent.

  Run on Windows:

  ```powershell
  dotnet test .\windows\PngCut.Tests\PngCut.Tests.csproj -c Release -p:Platform=x64 \
    --filter FullyQualifiedName~SharedContractDocumentTests
  ```

  Expected: the test project cannot copy the five absent JSON documents in `shared/contracts/v1/`.

- [ ] **Step 3: Add complete v1 documents and fixture guidance.**

  Create `behavior.json` with these authoritative values:

  ```json
  {
    "version": 1,
    "formats": ["png", "jpeg"],
    "modes": ["lossless", "balanced"],
    "engines": {
      "oxipng": { "format": "png", "mode": "lossless" },
      "pngquant": { "format": "png", "mode": "balanced" },
      "mozjpeg": { "format": "jpeg", "mode": "balanced" }
    },
    "taskStates": ["queued", "processing", "completed", "failed"],
    "retryableState": "failed",
    "pngquantNoChangeExitCodes": [98, 99],
    "output": {
      "suffix": "_pngcut",
      "directOutputExtension": "lowercase",
      "customDirectory": "must-exist-directory",
      "collisionFirstSuffix": 2,
      "folderOutput": "sibling-root-preserve-relative-path"
    }
  }
  ```

  Create `discovery-cases.json` with this complete vector set:

  ```json
  {
    "version": 1,
    "cases": [
      {
        "id": "discover-case-insensitive-supported-images",
        "platforms": ["all"],
        "selectedPaths": ["import"],
        "files": ["import/icon.PNG", "import/nested/photo.JpG", "import/nested/scan.JPEG", "import/nested/readme.pdf"],
        "expectedImages": ["import/icon.PNG", "import/nested/photo.JpG", "import/nested/scan.JPEG"],
        "expectedSkippedRegularFiles": 1
      },
      {
        "id": "discover-deduplicates-normalized-inputs",
        "platforms": ["all"],
        "selectedPaths": ["import/icon.png", "import/nested/../icon.png"],
        "files": ["import/icon.png"],
        "expectedImages": ["import/icon.png"],
        "expectedSkippedRegularFiles": 0
      }
    ]
  }
  ```

  Create `output-policy-cases.json` with this complete vector set:

  ```json
  {
    "version": 1,
    "cases": [
      {
        "id": "adjacent-normalizes-extension",
        "platforms": ["all"],
        "policy": "adjacent",
        "source": "import/banner.PNG",
        "expected": "import/banner_pngcut.png"
      },
      {
        "id": "folder-preserves-relative-source-name",
        "platforms": ["all"],
        "policy": "adjacent",
        "selectedFolder": "import/project",
        "source": "import/project/icons/Logo.JPG",
        "expected": "import/project_pngcut/icons/Logo.JPG"
      },
      {
        "id": "adjacent-collision-uses-two",
        "platforms": ["all"],
        "policy": "adjacent",
        "source": "import/logo.png",
        "existingOutputs": ["import/logo_pngcut.png"],
        "expected": "import/logo_pngcut-2.png"
      },
      {
        "id": "overwrite-keeps-source",
        "platforms": ["all"],
        "policy": "overwrite",
        "source": "import/logo.JPG",
        "expected": "import/logo.JPG"
      },
      {
        "id": "custom-requires-existing-directory",
        "platforms": ["all"],
        "policy": "custom",
        "source": "import/logo.png",
        "customDirectory": "missing-output",
        "expectedError": "output_policy_invalid"
      },
      {
        "id": "windows-unc-share-root",
        "platforms": ["windows"],
        "policy": "adjacent",
        "selectedFolder": "\\\\server\\share\\",
        "source": "\\\\server\\share\\icons\\logo.JPG",
        "expected": "\\\\server\\share\\_pngcut\\icons\\logo.JPG"
      }
    ]
  }
  ```

  Add `error-catalog.json` with this exact content:

  ```json
  {
    "version": 1,
    "errors": [
      { "code": "input_unreadable", "message": "无法读取输入文件。" },
      { "code": "output_policy_invalid", "message": "输出位置无效。" },
      { "code": "engine_unavailable", "message": "压缩引擎不可用。" },
      { "code": "engine_failed", "message": "压缩程序执行失败。" },
      { "code": "output_invalid", "message": "压缩程序没有生成有效输出文件。" },
      { "code": "output_conflict", "message": "输出文件已存在，未覆盖原文件。" }
    ]
  }
  ```

  Create `engine-manifest.json` with this exact content:

  ```json
  {
    "version": 1,
    "engines": {
      "oxipng": {
        "version": "10.2.0",
        "macosTag": "v10.2.0",
        "sourceRevision": "340cd9878d8d8289f09fa101b48a8f5f0b7783f4",
        "upstream": "https://github.com/oxipng/oxipng",
        "license": "MIT"
      },
      "pngquant": {
        "version": "3.0.3",
        "macosTag": "3.0.3",
        "sourceRevision": "53a332a58f44357b6b41842a54d74aa1e245913d",
        "upstream": "https://github.com/kornelski/pngquant",
        "license": "GPL-3.0-or-later"
      },
      "mozjpeg": {
        "version": "4.1.5",
        "macosTag": "v4.1.5",
        "sourceRevision": "6c9f0897afa1c2738d7222a0a9ab49e8b536a267",
        "upstream": "https://github.com/mozilla/mozjpeg",
        "license": "IJG-BSD-zlib"
      }
    }
  }
  ```

  In `shared/fixtures/README.md`, require tests to create `all` paths under a unique temporary root, map each logical slash-separated path below that root, and execute a platform-only case only when its `platforms` includes the current platform. Add `shared/` to the repository-layout block in the root README.

- [ ] **Step 4: Add minimal JSON loaders and content assertions.**

  Implement the macOS loader in `SharedContractLoader.swift`:

  ```swift
  import Foundation

  struct SharedContractDocument: Decodable {
      let version: Int
  }

  enum SharedContractLoader {
      static func contractURL(named name: String) -> URL {
          URL(fileURLWithPath: #filePath)
              .deletingLastPathComponent()
              .deletingLastPathComponent()
              .deletingLastPathComponent()
              .deletingLastPathComponent()
              .appendingPathComponent("shared/contracts/v1/\(name)")
      }

      static func document(named name: String) throws -> SharedContractDocument {
          try JSONDecoder().decode(SharedContractDocument.self, from: Data(contentsOf: contractURL(named: name)))
      }
  }
  ```

  Extend the Swift test with `XCTAssertEqual(try SharedContractLoader.document(named: "behavior.json").version, 1)`. In the C# test, use `JavaScriptSerializer` to parse the copied file and assert the `version` value:

  ```csharp
  var json = File.ReadAllText(Path.Combine(TestContext.CurrentContext.TestDirectory, "Contracts", "behavior.json"));
  var document = new System.Web.Script.Serialization.JavaScriptSerializer()
      .Deserialize<System.Collections.Generic.Dictionary<string, object>>(json);
  Assert.That(document["version"], Is.EqualTo(1));
  ```

- [ ] **Step 5: Run both focused suites and commit the contract foundation.**

  Run the commands from Step 2 again. Expected: both pass their document-presence and `version == 1` assertions.

  Commit:

  ```bash
  git add shared README.md macos/PngCutTests/Support/SharedContractLoader.swift \
    macos/PngCutTests/SharedContractDocumentTests.swift macos/PngCut.xcodeproj/project.pbxproj \
    windows/PngCut.Tests/SharedContractDocumentTests.cs windows/PngCut.Tests/PngCut.Tests.csproj
  git commit -m "feat: add shared compression contracts"
  ```

### Task 2: Execute shared discovery and output vectors, then close output-policy drift

**Files:**
- Create: `macos/PngCutTests/SharedContractBehaviorTests.swift`
- Create: `windows/PngCut.Tests/SharedContractBehaviorTests.cs`
- Modify: `macos/PngCutTests/Support/SharedContractLoader.swift`
- Modify: `macos/PngCut.xcodeproj/project.pbxproj`
- Modify: `windows/src/PngCut.Core/Services/OutputPolicy.cs`
- Modify: `windows/PngCut.Tests/OutputPolicyTests.cs`
- Modify: `windows/PngCut.Tests/PngCut.Tests.csproj`

- [ ] **Step 1: Write failing behavior-adapter tests for all shared output vectors.**

  Extend the Swift loader with decodable `OutputPolicyContract` and `OutputPolicyCase` types, including `id`, `platforms`, `policy`, `source`, optional `selectedFolder`, optional `customDirectory`, and `expected`. Add a Swift test that creates a unique temporary root and asserts the direct case:

  ```swift
  func testAdjacentCaseNormalizesTheOutputExtension() throws {
      let source = temporaryRoot.appendingPathComponent("import/banner.PNG")
      try makeFile(at: source)

      let prepared = try OutputPolicy.adjacent.prepare(source: source)

      XCTAssertEqual(relativePath(of: prepared.finalURL), "import/banner_pngcut.png")
  }
  ```

  Add the matching NUnit test, using a temporary root and `OutputPolicy.Prepare`:

  ```csharp
  [Test]
  public void Adjacent_case_normalizes_the_output_extension()
  {
      var source = CreateFile("import/banner.PNG");

      var prepared = OutputPolicy.Prepare(source, OutputMode.Adjacent);

      Assert.That(Relative(prepared.FinalPath), Is.EqualTo("import" + Path.DirectorySeparatorChar + "banner_pngcut.png"));
  }
  ```

  In both files add the following four exact assertions, loading their inputs from the contract by ID: `folder-preserves-relative-source-name` produces `import/project_pngcut/icons/Logo.JPG`; `adjacent-collision-uses-two` produces `import/logo_pngcut-2.png`; `overwrite-keeps-source` returns the unmodified source path and permits replacement; `custom-requires-existing-directory` fails with the `output_policy_invalid` contract code. In the NUnit file also load and execute `windows-unc-share-root` through the existing pure `ForFolderImport` API; do not execute it in XCTest.

- [ ] **Step 2: Run behavior tests and capture the expected Windows failures.**

  Run:

  ```bash
  xcodebuild -project macos/PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutTests/SharedContractBehaviorTests test
  ```

  Expected: PASS for existing macOS output behavior.

  Run on Windows:

  ```powershell
  dotnet test .\windows\PngCut.Tests\PngCut.Tests.csproj -c Release -p:Platform=x64 \
    --filter FullyQualifiedName~SharedContractBehaviorTests
  ```

  Expected: FAIL because Windows retains `.PNG` and accepts a non-existent custom output directory.

- [ ] **Step 3: Normalize the Windows direct-output extension and custom-directory guard.**

  In `windows/src/PngCut.Core/Services/OutputPolicy.cs`, make direct output use a lowercased extension and reject a missing or file-valued custom destination before reserving a name:

  ```csharp
  public static string ForSingleFile(string sourcePath)
  {
      if (sourcePath == null) throw new ArgumentNullException(nameof(sourcePath));
      return Path.Combine(
          DirectoryOf(sourcePath),
          Path.GetFileNameWithoutExtension(sourcePath) + "_pngcut" + Path.GetExtension(sourcePath).ToLowerInvariant());
  }

  private static string ExistingCustomDirectory(string? customDirectory)
  {
      if (string.IsNullOrWhiteSpace(customDirectory) || !Directory.Exists(customDirectory))
      {
          throw new ArgumentException("The custom output directory must exist.", nameof(customDirectory));
      }
      return customDirectory;
  }
  ```

  In the `OutputMode.Custom` branch call `ExistingCustomDirectory(customDirectory)` before `Path.Combine`. Preserve original case for the relative source filename of a folder import; that path is explicitly governed by a different contract case.

- [ ] **Step 4: Update old Windows expectations without weakening coverage.**

  Replace assertions that expect `logo_pngcut.JPG` for a direct output with `logo_pngcut.jpg`. Replace the old “custom does not create directory” test with two tests:

  ```csharp
  [Test]
  public void Prepare_custom_rejects_a_missing_directory()
  {
      Assert.That(() => OutputPolicy.Prepare(@"D:\\art\\logo.JPG", OutputMode.Custom, @"D:\\missing"),
          Throws.TypeOf<ArgumentException>());
  }

  [Test]
  public void Prepare_custom_uses_an_existing_directory()
  {
      var directory = CreateTemporaryDirectory();
      var prepared = OutputPolicy.Prepare(Path.Combine(directory, "logo.JPG"), OutputMode.Custom, directory);
      Assert.That(prepared.FinalPath, Is.EqualTo(Path.Combine(directory, "logo_pngcut.jpg")));
  }
  ```

- [ ] **Step 5: Run platform behavior and existing output suites, then commit.**

  Run the focused behavior commands from Step 2, plus:

  ```bash
  xcodebuild -project macos/PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutTests/OutputPolicyTests -only-testing:PngCutTests/FileDiscoveryTests test
  ```

  ```powershell
  dotnet test .\windows\PngCut.Tests\PngCut.Tests.csproj -c Release -p:Platform=x64 \
    --filter "FullyQualifiedName~OutputPolicyTests|FullyQualifiedName~FileDiscoveryTests|FullyQualifiedName~SharedContractBehaviorTests"
  ```

  Expected: PASS on both platforms.

  Commit:

  ```bash
  git add macos/PngCutTests/Support/SharedContractLoader.swift \
    macos/PngCutTests/SharedContractBehaviorTests.swift macos/PngCut.xcodeproj/project.pbxproj \
    windows/src/PngCut.Core/Services/OutputPolicy.cs windows/PngCut.Tests/OutputPolicyTests.cs \
    windows/PngCut.Tests/SharedContractBehaviorTests.cs windows/PngCut.Tests/PngCut.Tests.csproj
  git commit -m "feat: align output policy contracts"
  ```

### Task 3: Standardize task failure codes and user-facing error mapping

**Files:**
- Create: `macos/PngCut/Services/FailureCatalog.swift`
- Create: `macos/PngCutTests/FailureCatalogTests.swift`
- Create: `windows/src/PngCut.Core/Models/FailureCode.cs`
- Create: `windows/src/PngCut.Core/Services/FailureCatalog.cs`
- Create: `windows/PngCut.Tests/FailureCatalogTests.cs`
- Modify: `macos/PngCut/Services/ImageCompressor.swift`
- Modify: `macos/PngCut/Services/CompressionQueue.swift`
- Modify: `macos/PngCut/Domain/OutputPolicy.swift`
- Modify: `macos/PngCut/Views/TaskRowView.swift`
- Modify: `macos/PngCut.xcodeproj/project.pbxproj`
- Modify: `windows/src/PngCut.Core/Models/CompressionTask.cs`
- Modify: `windows/src/PngCut.Engine/CompressionQueue.cs`
- Modify: `windows/src/PngCut.Desktop/ViewModels/MainViewModel.cs`

- [ ] **Step 1: Write failing catalog-parity tests before changing failure types.**

  In both platform test suites, load `error-catalog.json`, assert that every code is present in the local catalog, and assert exact message parity. The required local API is:

  ```swift
  enum FailureCode: String, CaseIterable, Sendable {
      case inputUnreadable = "input_unreadable"
      case outputPolicyInvalid = "output_policy_invalid"
      case engineUnavailable = "engine_unavailable"
      case engineFailed = "engine_failed"
      case outputInvalid = "output_invalid"
      case outputConflict = "output_conflict"
  }
  ```

  ```csharp
  public enum FailureCode
  {
      InputUnreadable,
      OutputPolicyInvalid,
      EngineUnavailable,
      EngineFailed,
      OutputInvalid,
      OutputConflict
  }
  ```

  Add one UI-facing assertion per platform: an engine failure must display `压缩程序执行失败。` and must not include a source path or process command line.

- [ ] **Step 2: Run catalog tests and verify they fail for missing APIs.**

  Run the focused `FailureCatalogTests` target on macOS and the NUnit filter `FullyQualifiedName~FailureCatalogTests` on Windows.

  Expected: compilation fails because `FailureCode` and `FailureCatalog` do not exist.

- [ ] **Step 3: Implement local catalogs and typed failure snapshots.**

  Implement `FailureCatalog.swift` as a non-UI service with this public surface:

  ```swift
  enum FailureCatalog {
      static func message(for code: FailureCode) -> String {
          switch code {
          case .inputUnreadable: "无法读取输入文件。"
          case .outputPolicyInvalid: "输出位置无效。"
          case .engineUnavailable: "压缩引擎不可用。"
          case .engineFailed: "压缩程序执行失败。"
          case .outputInvalid: "压缩程序没有生成有效输出文件。"
          case .outputConflict: "输出文件已存在，未覆盖原文件。"
          }
      }
  }
  ```

  In `ImageCompressor.swift`, replace the old failure enum with the typed diagnostic container:

  ```swift
  struct CompressionFailure: Error, Equatable, Sendable {
      let code: FailureCode
      let technicalMessage: String?
  }
  ```

  Replace raw `CompressionFailure.localExecution` and `.outputValidation` construction sites with the appropriate code while retaining the diagnostic only in `technicalMessage`. Map missing bundled binaries to `.engineUnavailable`, nonzero/compressor-launch failures to `.engineFailed`, bad temporary output to `.outputInvalid`, output-policy setup failures to `.outputPolicyInvalid`, and safe commit collisions to `.outputConflict`. In `CompressionQueue`, catch `OutputPolicyError.destinationAlreadyExists` separately and convert it to `.outputConflict`; convert other `OutputPolicyError` values to `.outputPolicyInvalid`. Make `TaskRowView` render `FailureCatalog.message(for: failure.code)`.

  Implement `FailureCode.cs` and `FailureCatalog.cs` exactly as follows:

  ```csharp
  namespace PngCut.Core.Models;

  public enum FailureCode
  {
      InputUnreadable,
      OutputPolicyInvalid,
      EngineUnavailable,
      EngineFailed,
      OutputInvalid,
      OutputConflict
  }
  ```

  ```csharp
  using PngCut.Core.Models;

  namespace PngCut.Core.Services;

  public static class FailureCatalog
  {
      public static string Message(FailureCode code) => code switch
      {
          FailureCode.InputUnreadable => "无法读取输入文件。",
          FailureCode.OutputPolicyInvalid => "输出位置无效。",
          FailureCode.EngineUnavailable => "压缩引擎不可用。",
          FailureCode.EngineFailed => "压缩程序执行失败。",
          FailureCode.OutputInvalid => "压缩程序没有生成有效输出文件。",
          FailureCode.OutputConflict => "输出文件已存在，未覆盖原文件。",
          _ => throw new System.ArgumentOutOfRangeException(nameof(code))
      };
  }
  ```

  Add `public FailureCode? ErrorCode { get; private set; }` to `CompressionTask`. Change `Fail` to receive a `FailureCode` and store `ErrorCode = code` plus `ErrorMessage = FailureCatalog.Message(code)`. In the Windows queue, map `CompressionException` from engine execution to `EngineFailed`, invalid temporary output to `OutputInvalid`, output reservation/preparation failures to `OutputPolicyInvalid`, and commit collisions to `OutputConflict`. Update `MainViewModel` to display the stored catalog message only.

- [ ] **Step 4: Update affected existing tests with typed expectations.**

  Replace macOS equality assertions such as `.localExecution("failed")` with:

  ```swift
  XCTAssertEqual(failure.code, .engineFailed)
  XCTAssertEqual(failure.technicalMessage, "failed")
  ```

  Replace Windows string-prefix assertions with:

  ```csharp
  Assert.That(failed.ErrorCode, Is.EqualTo(FailureCode.EngineFailed));
  Assert.That(failed.ErrorMessage, Is.EqualTo("压缩程序执行失败。"));
  ```

  Keep all existing no-change, continue-after-failure and retry tests; amend only their error representation assertions.

- [ ] **Step 5: Run failure, queue and UI-facing unit tests, then commit.**

  Run:

  ```bash
  xcodebuild -project macos/PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutTests/FailureCatalogTests -only-testing:PngCutTests/CompressionQueueTests \
    -only-testing:PngCutTests/PngCutTests test
  ```

  ```powershell
  dotnet test .\windows\PngCut.Tests\PngCut.Tests.csproj -c Release -p:Platform=x64 \
    --filter "FullyQualifiedName~FailureCatalogTests|FullyQualifiedName~CompressionQueueTests"
  ```

  Expected: PASS; failures no longer expose platform-specific source paths in the UI model.

  Commit:

  ```bash
  git add macos/PngCut/Services/FailureCatalog.swift macos/PngCut/Services/ImageCompressor.swift \
    macos/PngCut/Services/CompressionQueue.swift macos/PngCut/Domain/OutputPolicy.swift \
    macos/PngCut/Views/TaskRowView.swift macos/PngCutTests/FailureCatalogTests.swift \
    macos/PngCutTests/CompressionQueueTests.swift macos/PngCutTests/PngCutTests.swift \
    macos/PngCut.xcodeproj/project.pbxproj windows/src/PngCut.Core/Services/FailureCatalog.cs \
    windows/src/PngCut.Core/Models/FailureCode.cs windows/src/PngCut.Core/Models/CompressionTask.cs \
    windows/src/PngCut.Engine/CompressionQueue.cs \
    windows/src/PngCut.Desktop/ViewModels/MainViewModel.cs windows/PngCut.Tests/FailureCatalogTests.cs \
    windows/PngCut.Tests/CompressionQueueTests.cs
  git commit -m "feat: standardize compression failure codes"
  ```

### Task 4: Centralize engine metadata and add release-time contract checks

**Files:**
- Modify: `macos/scripts/build-oxipng.sh`
- Modify: `macos/scripts/build-pngquant.sh`
- Modify: `macos/scripts/build-mozjpeg.sh`
- Modify: `macos/scripts/check-release-content.sh`
- Modify: `windows/build/Test-ReleaseLayout.ps1`
- Modify: `windows/README.md`
- Modify: `macos/THIRD_PARTY_NOTICES.md`
- Modify: `.github/workflows/release.yml`

- [ ] **Step 1: Write failing manifest-consumption checks.**

  Before changing release code, add these checks to a clean shell/PowerShell invocation:

  ```bash
  rg -q 'engine-manifest.json' macos/scripts/build-oxipng.sh
  rg -q 'engine-manifest.json' macos/scripts/build-pngquant.sh
  rg -q 'engine-manifest.json' macos/scripts/build-mozjpeg.sh
  rg -q 'engine-manifest.json' macos/scripts/check-release-content.sh
  ```

  ```powershell
  Select-String -Quiet -Path .\windows\build\Test-ReleaseLayout.ps1 -Pattern 'engine-manifest.json'
  ```

  Also require `shared/contracts/v1/engine-manifest.json` to contain each key with `plutil` on macOS and `ConvertFrom-Json` on Windows. The macOS extraction command must be:

  ```bash
  plutil -extract 'engines.oxipng.version' raw shared/contracts/v1/engine-manifest.json
  ```

  The Windows equivalent must be:

  ```powershell
  $manifest = Get-Content "$PSScriptRoot\..\..\shared\contracts\v1\engine-manifest.json" -Raw | ConvertFrom-Json
  if ($manifest.engines.oxipng.version -ne '10.2.0') { throw 'Unexpected oxipng manifest version.' }
  ```

- [ ] **Step 2: Run checks and verify the initial failure.**

  Run:

  ```bash
  bash -n macos/scripts/build-oxipng.sh macos/scripts/build-pngquant.sh macos/scripts/build-mozjpeg.sh \
    macos/scripts/check-release-content.sh
  ./macos/scripts/check-release-content.sh
  ```

  Expected before implementation: the `rg` and `Select-String` checks fail because no current release/build script consumes `engine-manifest.json`; the manifest extraction itself passes because Task 1 created it.

- [ ] **Step 3: Make macOS build scripts consume manifest tags.**

  In each `macos/scripts/build-*.sh`, replace the hardcoded version/tag definition with a manifest helper:

  ```bash
  readonly CONTRACT_MANIFEST="${PROJECT_DIRECTORY}/../shared/contracts/v1/engine-manifest.json"

  manifest_value() {
      /usr/libexec/PlistBuddy -c "Print :$1:$2" "${CONTRACT_MANIFEST}"
  }
  ```

  Because `PlistBuddy` does not parse JSON, convert this one file through `plutil -convert xml1 -o - "${CONTRACT_MANIFEST}"` and read the requested key from stdin using `plutil -extract`; use this concrete helper instead:

  ```bash
  manifest_value() {
      local engine_key="$1"
      local field_key="$2"
      plutil -extract "engines.${engine_key}.${field_key}" raw "${CONTRACT_MANIFEST}"
  }
  ```

  Set each script's existing `VERSION`/tag from `manifest_value` and keep its existing clean-checkout, lock, architecture and `file` checks unchanged. Extend `check-release-content.sh` to require manifest existence and its three documented versions.

- [ ] **Step 4: Make Windows release validation consume the manifest.**

  Add this helper near the top of `windows/build/Test-ReleaseLayout.ps1`:

  ```powershell
  $contractManifestPath = Join-Path $PSScriptRoot '..\..\shared\contracts\v1\engine-manifest.json'
  $contractManifest = Get-Content $contractManifestPath -Raw | ConvertFrom-Json
  foreach ($engine in 'oxipng', 'pngquant', 'mozjpeg') {
      if ([string]::IsNullOrWhiteSpace($contractManifest.engines.$engine.version)) {
          throw "Shared manifest is missing $engine version."
      }
  }
  ```

  Preserve the ZIP's platform-specific x86/x64 binary checks. Update `windows/README.md` and `macos/THIRD_PARTY_NOTICES.md` to point at `shared/contracts/v1/engine-manifest.json` for the canonical version/source table while retaining their platform-specific license paths.

- [ ] **Step 5: Gate the release workflow with macOS unit/contract tests.**

  Insert this step before `Build DMG` in `.github/workflows/release.yml`:

  ```yaml
      - name: Test macOS core and shared contracts
        run: >-
          xcodebuild -project macos/PngCut.xcodeproj -scheme PngCut
          -destination 'platform=macOS'
          -only-testing:PngCutTests test
  ```

  Keep the existing Windows `dotnet test` step; it already runs the new NUnit contract tests for x64 and x86.

- [ ] **Step 6: Verify scripts and commit release integration.**

  Run:

  ```bash
  bash -n macos/scripts/build-oxipng.sh macos/scripts/build-pngquant.sh macos/scripts/build-mozjpeg.sh \
    macos/scripts/check-release-content.sh
  ./macos/scripts/check-release-content.sh
  git diff --check
  ```

  Expected: syntax and content checks pass, and the diff check prints nothing.

  Commit:

  ```bash
  git add macos/scripts/build-oxipng.sh macos/scripts/build-pngquant.sh macos/scripts/build-mozjpeg.sh \
    macos/scripts/check-release-content.sh windows/build/Test-ReleaseLayout.ps1 \
    windows/README.md macos/THIRD_PARTY_NOTICES.md .github/workflows/release.yml
  git commit -m "ci: validate shared engine contracts"
  ```

### Task 5: Verify the standardized baseline and preserve the GIF design boundary

**Files:**
- Test: all sources in `macos/PngCutTests/`
- Test: all sources in `macos/PngCutUITests/`
- Test: all sources in `windows/PngCut.Tests/`
- Test: `.github/workflows/release.yml`
- Inspect: `docs/superpowers/specs/2026-08-28-gif-compression-and-png-sequence-design.md`
- Inspect: `docs/superpowers/plans/2026-08-28-gif-compression-and-png-sequence.md`

- [ ] **Step 1: Build and run the full macOS unit suite.**

  Run:

  ```bash
  xcodebuild -project macos/PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutTests test
  ```

  Expected: all `PngCutTests`, including shared document, behavior, failure and existing queue/engine/output tests, pass. Report UI tests separately rather than calling the entire Xcode suite green if the two known baseline UI assertions still fail.

- [ ] **Step 2: Run the macOS UI suite and record its independent result.**

  Run:

  ```bash
  xcodebuild -project macos/PngCut.xcodeproj -scheme PngCut -destination 'platform=macOS' \
    -only-testing:PngCutUITests test
  ```

  Expected: classify every UI result explicitly. If `testBalancedModeIsDisabledBeforeValidation` or `testBottomBarOffersDisabledBalancedShortcutBeforeValidation` still fail before any GIF work, report them as the established baseline rather than attributing them to this standardization.

- [ ] **Step 3: Run Windows tests on both shipping architectures.**

  Run on Windows:

  ```powershell
  dotnet test .\windows\PngCut.Tests\PngCut.Tests.csproj -c Release -p:Platform=x64
  dotnet test .\windows\PngCut.Tests\PngCut.Tests.csproj -c Release -p:Platform=x86
  ```

  Expected: both runs pass all non-explicit tests, including shared contract vectors. Do not claim Windows verification on macOS; record it as pending until these commands run on a Windows host.

- [ ] **Step 4: Verify the repository boundary and GIF documents.**

  Run:

  ```bash
  test -f docs/superpowers/specs/2026-08-28-gif-compression-and-png-sequence-design.md
  test -f docs/superpowers/plans/2026-08-28-gif-compression-and-png-sequence.md
  find shared -type f | sort
  git status --short
  git diff --check
  ```

  Expected: both GIF documents exist unchanged from their preserved commits, `shared/` contains only contract/fixture data and no platform binaries, and no generated build or test artifact is staged.

- [ ] **Step 5: Commit only verification corrections, then stop before GIF implementation.**

  If a verification command exposes a source or test defect, add a failing regression test first, make the smallest matching correction, rerun that exact command, and commit only the correction. End this plan after the standardized PNG/JPEG baseline is verified; begin a fresh GIF design cycle against contract v1 rather than implementing Gifsicle or Gifski here.
