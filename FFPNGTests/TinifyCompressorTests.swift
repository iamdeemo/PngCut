import Foundation
import XCTest
@testable import FFPNG

final class TinifyCompressorTests: XCTestCase {
    override func setUp() {
        super.setUp()
        TinifyURLProtocol.reset()
    }

    func testCompressorMapsUnauthorizedResponseToInvalidAPIKey() async throws {
        TinifyURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/shrink")
            return .response(status: 401, body: Self.errorBody("Credentials are invalid"))
        }

        let compressor = makeCompressor()

        await assertFailure(.invalidAPIKey) {
            try await compressor.compress(
                source: try self.makeSourcePNG(),
                temporaryDestination: self.makeTemporaryDestination(),
                progress: { _ in }
            )
        }
    }

    func testCompressorMapsQuotaResponseToQuotaExceeded() async throws {
        TinifyURLProtocol.handler = { _ in
            .response(status: 429, body: Self.errorBody("Compression limit exceeded"))
        }

        let compressor = makeCompressor()

        await assertFailure(.quotaExceeded) {
            try await compressor.compress(
                source: try self.makeSourcePNG(),
                temporaryDestination: self.makeTemporaryDestination(),
                progress: { _ in }
            )
        }
    }

    func testCompressorMapsTransportFailure() async throws {
        TinifyURLProtocol.handler = { _ in
            .failure(URLError(.notConnectedToInternet))
        }

        let compressor = makeCompressor()

        do {
            try await compressor.compress(
                source: try makeSourcePNG(),
                temporaryDestination: makeTemporaryDestination(),
                progress: { _ in }
            )
            XCTFail("Expected a transport failure")
        } catch let failure as CompressionFailure {
            guard case .transport = failure else {
                return XCTFail("Expected transport failure, got \(failure)")
            }
        }
    }

    func testCompressorUploadsThenDownloadsOptimizedOutput() async throws {
        let optimizedData = Data("optimized-png".utf8)
        var requests: [URLRequest] = []
        TinifyURLProtocol.handler = { request in
            requests.append(request)
            switch request.url?.path {
            case "/shrink":
                XCTAssertEqual(request.httpMethod, "POST")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic YXBpOnRlc3QtYXBpLWtleQ==")
                XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/png")
                XCTAssertEqual(Self.requestBody(request), Data("source-png".utf8))
                return .response(
                    status: 201,
                    body: Data("{\"output\":{\"url\":\"https://api.tinify.com/output/result\"}}".utf8)
                )
            case "/output/result":
                XCTAssertEqual(request.httpMethod, "GET")
                XCTAssertNil(request.value(forHTTPHeaderField: "Authorization"))
                return .response(status: 200, body: optimizedData)
            default:
                return .response(status: 500, body: Data())
            }
        }

        let source = try makeSourcePNG()
        let destination = makeTemporaryDestination()
        let progress = TestProgressRecorder()
        try await makeCompressor().compress(source: source, temporaryDestination: destination) {
            progress.append($0)
        }

        XCTAssertEqual(try Data(contentsOf: destination), optimizedData)
        XCTAssertEqual(requests.compactMap(\.url?.path), ["/shrink", "/output/result"])
        XCTAssertEqual(progress.values(), [0, 0.5, 1])
    }

    func testCompressorMapsMissingOutputURLToAPIResponse() async throws {
        TinifyURLProtocol.handler = { _ in
            .response(status: 201, body: Data("{\"output\":{}}".utf8))
        }

        let compressor = makeCompressor()

        await assertFailure(.apiResponse(statusCode: 201, message: "Tinify response is missing output.url.")) {
            try await compressor.compress(
                source: try self.makeSourcePNG(),
                temporaryDestination: self.makeTemporaryDestination(),
                progress: { _ in }
            )
        }
    }

    func testValidationAuthenticatesAOnePixelShrinkRequest() async throws {
        TinifyURLProtocol.handler = { request in
            XCTAssertEqual(request.url?.path, "/shrink")
            XCTAssertEqual(request.httpMethod, "POST")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Authorization"), "Basic YXBpOnRlc3QtYXBpLWtleQ==")
            XCTAssertEqual(request.value(forHTTPHeaderField: "Content-Type"), "image/png")
            XCTAssertFalse(Self.requestBody(request)?.isEmpty ?? true)
            return .response(
                status: 201,
                body: Data("{\"output\":{\"url\":\"https://api.tinify.com/output/validated\"}}".utf8)
            )
        }

        try await makeCompressor().validateAPIKey()
    }

    func testValidationMapsUnauthorizedResponseToInvalidAPIKey() async throws {
        TinifyURLProtocol.handler = { _ in
            .response(status: 401, body: Self.errorBody("Credentials are invalid"))
        }

        let compressor = makeCompressor()

        await assertFailure(.invalidAPIKey) {
            try await compressor.validateAPIKey()
        }
    }

    func testLiveValidationAcceptsExplicitlyProvidedTinifyKey() async throws {
        guard let apiKey = ProcessInfo.processInfo.environment["FFPNG_TINIFY_API_KEY"],
              !apiKey.isEmpty else {
            throw XCTSkip("Set FFPNG_TINIFY_API_KEY to run the live Tinify validation test.")
        }

        try await TinifyCompressor(apiKey: apiKey).validateAPIKey()
    }

    func testCompressorRejectsOutputURLOutsideTinifyBeforeDownload() async throws {
        var requestCount = 0
        TinifyURLProtocol.handler = { request in
            requestCount += 1
            XCTAssertEqual(request.url?.path, "/shrink")
            return .response(
                status: 201,
                body: Data("{\"output\":{\"url\":\"https://untrusted.example/output/result\"}}".utf8)
            )
        }

        let compressor = makeCompressor()

        await assertFailure(.apiResponse(statusCode: 201, message: "Tinify response contains an untrusted output URL.")) {
            try await compressor.compress(
                source: try self.makeSourcePNG(),
                temporaryDestination: self.makeTemporaryDestination(),
                progress: { _ in }
            )
        }
        XCTAssertEqual(requestCount, 1)
    }

    func testCompressorRejectsRedirectResponseWithoutFollowingIt() async throws {
        var requests: [URLRequest] = []
        TinifyURLProtocol.handler = { request in
            requests.append(request)
            switch request.url?.path {
            case "/shrink":
                return .response(
                    status: 201,
                    body: Data("{\"output\":{\"url\":\"https://api.tinify.com/output/redirected\"}}".utf8)
                )
            case "/output/redirected":
                return .response(
                    status: 302,
                    body: Data(),
                    headers: ["Location": "https://untrusted.example/output/result"]
                )
            default:
                return .response(status: 500, body: Data())
            }
        }

        let compressor = makeCompressor()

        await assertFailure(.apiResponse(statusCode: 302, message: nil)) {
            try await compressor.compress(
                source: try self.makeSourcePNG(),
                temporaryDestination: self.makeTemporaryDestination(),
                progress: { _ in }
            )
        }
        XCTAssertEqual(requests.compactMap(\.url?.path), ["/shrink", "/output/redirected"])
    }

    func testOutputDownloadDelegateRejectsEveryRedirect() throws {
        let delegate = TrustedOutputRedirectDelegate()
        let response = try XCTUnwrap(
            HTTPURLResponse(
                url: URL(string: "https://api.tinify.com/output/result")!,
                statusCode: 302,
                httpVersion: nil,
                headerFields: ["Location": "https://api.tinify.com/output/other"]
            )
        )
        var proposedRequest: URLRequest?

        delegate.urlSession(
            URLSession(configuration: .ephemeral),
            task: URLSession.shared.dataTask(with: URL(string: "https://api.tinify.com/output/result")!),
            willPerformHTTPRedirection: response,
            newRequest: URLRequest(url: URL(string: "https://api.tinify.com/output/other")!)
        ) { proposedRequest = $0 }

        XCTAssertNil(proposedRequest)
        XCTAssertEqual(delegate.rejectedStatusCode, 302)
    }

    private func makeCompressor() -> TinifyCompressor {
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [TinifyURLProtocol.self]
        return TinifyCompressor(apiKey: "test-api-key", session: URLSession(configuration: configuration))
    }

    private func makeSourcePNG() throws -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TinifyCompressorTests-\(UUID().uuidString).png")
        try Data("source-png".utf8).write(to: url)
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func makeTemporaryDestination() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent("TinifyCompressorTests-\(UUID().uuidString).png")
        addTeardownBlock { try? FileManager.default.removeItem(at: url) }
        return url
    }

    private func assertFailure(
        _ expected: CompressionFailure,
        operation: () async throws -> Void
    ) async {
        do {
            try await operation()
            XCTFail("Expected \(expected)")
        } catch let failure as CompressionFailure {
            XCTAssertEqual(failure, expected)
        } catch {
            XCTFail("Expected CompressionFailure, got \(error)")
        }
    }

    private static func errorBody(_ message: String) -> Data {
        Data("{\"error\":\"Error\",\"message\":\"\(message)\"}".utf8)
    }

    private static func requestBody(_ request: URLRequest) -> Data? {
        if let body = request.httpBody {
            return body
        }
        guard let stream = request.httpBodyStream else {
            return nil
        }
        stream.open()
        defer { stream.close() }

        var data = Data()
        var buffer = [UInt8](repeating: 0, count: 1_024)
        while stream.hasBytesAvailable {
            let count = stream.read(&buffer, maxLength: buffer.count)
            guard count > 0 else {
                break
            }
            data.append(buffer, count: count)
        }
        return data
    }
}

private final class TinifyURLProtocol: URLProtocol {
    enum Result {
        case response(status: Int, body: Data, headers: [String: String] = [:])
        case failure(Error)
    }

    static var handler: ((URLRequest) -> Result)?

    static func reset() {
        handler = nil
    }

    override class func canInit(with request: URLRequest) -> Bool {
        request.url?.host == "api.tinify.com"
    }

    override class func canonicalRequest(for request: URLRequest) -> URLRequest {
        request
    }

    override func startLoading() {
        guard let handler = Self.handler else {
            return XCTFail("Missing URLProtocol handler")
        }

        switch handler(request) {
        case let .response(status, body, headers):
            var responseHeaders = ["Content-Type": "application/json"]
            headers.forEach { responseHeaders[$0.key] = $0.value }
            let response = HTTPURLResponse(
                url: request.url!,
                statusCode: status,
                httpVersion: nil,
                headerFields: responseHeaders
            )!
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: body)
            client?.urlProtocolDidFinishLoading(self)
        case let .failure(error):
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private final class TestProgressRecorder: @unchecked Sendable {
    private let lock = NSLock()
    private var recordedValues: [Double] = []

    func append(_ value: Double) {
        lock.lock()
        defer { lock.unlock() }
        recordedValues.append(value)
    }

    func values() -> [Double] {
        lock.lock()
        defer { lock.unlock() }
        return recordedValues
    }
}
