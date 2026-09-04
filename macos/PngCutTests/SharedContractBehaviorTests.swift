import XCTest
@testable import PngCut

final class SharedContractBehaviorTests: XCTestCase {
    private var temporaryRoot: URL!

    override func setUpWithError() throws {
        temporaryRoot = FileManager.default.temporaryDirectory
            .appendingPathComponent("PngCut-SharedContractBehaviorTests-\(UUID().uuidString)", isDirectory: true)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    override func tearDownWithError() throws {
        try? FileManager.default.removeItem(at: temporaryRoot)
    }

    func testAdjacentCaseNormalizesTheOutputExtension() throws {
        let testCase = try outputCase(id: "adjacent-normalizes-extension")
        let source = try makeFile(at: testCase.source)

        let prepared = try OutputPolicy.adjacent.prepare(source: source)

        XCTAssertEqual(relativePath(of: prepared.finalURL), testCase.expected)
    }

    func testFolderCasePreservesTheRelativeSourceName() throws {
        let testCase = try outputCase(id: "folder-preserves-relative-source-name")
        let source = try makeFile(at: testCase.source)
        let selectedFolder = logicalURL(testCase.selectedFolder!)
        var planner = OutputPlanner(policy: .adjacent, customDirectory: nil, reservedFinalURLs: [])

        let prepared = try planner.prepare(source: source, importedFolderRoot: selectedFolder)

        XCTAssertEqual(relativePath(of: prepared.finalURL), testCase.expected)
    }

    func testAdjacentCollisionUsesTheFirstNumberedSuffix() throws {
        let testCase = try outputCase(id: "adjacent-collision-uses-two")
        let source = try makeFile(at: testCase.source)
        try (testCase.existingOutputs ?? []).forEach { _ = try makeFile(at: $0) }

        let prepared = try OutputPolicy.adjacent.prepare(source: source)

        XCTAssertEqual(relativePath(of: prepared.finalURL), testCase.expected)
    }

    func testOverwriteCaseKeepsTheSourceAndAllowsReplacement() throws {
        let testCase = try outputCase(id: "overwrite-keeps-source")
        let source = try makeFile(at: testCase.source)

        let prepared = try OutputPolicy.overwrite.prepare(source: source)

        XCTAssertEqual(relativePath(of: prepared.finalURL), testCase.expected)
        XCTAssertTrue(prepared.allowsReplacingExistingFile)
    }

    func testCustomCaseRejectsAMissingDirectoryWithTheContractCode() throws {
        let testCase = try outputCase(id: "custom-requires-existing-directory")
        let source = try makeFile(at: testCase.source)

        XCTAssertThrowsError(
            try OutputPolicy.customDirectory.prepare(
                source: source,
                customDirectory: logicalURL(testCase.customDirectory!)
            )
        ) { error in
            XCTAssertEqual(outputPolicyErrorCode(error), testCase.expectedError)
        }
    }

    func testDiscoveryCasesMatchTheSharedContract() throws {
        for testCase in try SharedContractLoader.discoveryContract().cases where testCase.platforms.contains("all") {
            try resetTemporaryRoot()
            try testCase.files.forEach { _ = try makeFile(at: $0) }

            let result = FileDiscovery().discover(urls: testCase.selectedPaths.map(logicalURL))

            XCTAssertEqual(
                result.files.map(relativePath(of:)).sorted(),
                testCase.expectedImages.sorted(),
                testCase.id
            )
            XCTAssertEqual(result.skippedNonImageCount, testCase.expectedSkippedRegularFiles, testCase.id)
        }
    }

    private func outputCase(id: String) throws -> SharedOutputPolicyCase {
        guard let testCase = try SharedContractLoader.outputPolicyContract().cases.first(where: { $0.id == id }) else {
            throw XCTSkip("Missing output policy contract case \(id).")
        }
        return testCase
    }

    private func makeFile(at logicalPath: String) throws -> URL {
        let url = logicalURL(logicalPath)
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        try Data("fixture".utf8).write(to: url)
        return url
    }

    private func logicalURL(_ path: String) -> URL {
        temporaryRoot.appendingPathComponent(path)
    }

    private func resetTemporaryRoot() throws {
        try FileManager.default.removeItem(at: temporaryRoot)
        try FileManager.default.createDirectory(at: temporaryRoot, withIntermediateDirectories: true)
    }

    private func relativePath(of url: URL) -> String {
        String(url.standardizedFileURL.path.dropFirst(temporaryRoot.standardizedFileURL.path.count + 1))
    }

    private func outputPolicyErrorCode(_ error: Error) -> String? {
        guard error is OutputPolicyError else {
            return nil
        }
        return "output_policy_invalid"
    }
}
