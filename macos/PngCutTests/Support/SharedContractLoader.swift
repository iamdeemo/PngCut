import Foundation

struct SharedContractDocument: Decodable {
    let version: Int
}

struct SharedOutputPolicyContract: Decodable {
    let version: Int
    let cases: [SharedOutputPolicyCase]
}

struct SharedOutputPolicyCase: Decodable {
    let id: String
    let platforms: [String]
    let policy: String
    let source: String
    let selectedFolder: String?
    let customDirectory: String?
    let existingOutputs: [String]?
    let expected: String?
    let expectedError: String?
}

struct SharedDiscoveryContract: Decodable {
    let version: Int
    let cases: [SharedDiscoveryCase]
}

struct SharedDiscoveryCase: Decodable {
    let id: String
    let platforms: [String]
    let selectedPaths: [String]
    let files: [String]
    let expectedImages: [String]
    let expectedSkippedRegularFiles: Int
}

struct SharedErrorCatalog: Decodable {
    let version: Int
    let errors: [SharedErrorCatalogEntry]
}

struct SharedErrorCatalogEntry: Decodable {
    let code: String
    let message: String
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
        try decode(SharedContractDocument.self, named: name)
    }

    static func outputPolicyContract() throws -> SharedOutputPolicyContract {
        try decode(SharedOutputPolicyContract.self, named: "output-policy-cases.json")
    }

    static func discoveryContract() throws -> SharedDiscoveryContract {
        try decode(SharedDiscoveryContract.self, named: "discovery-cases.json")
    }

    static func errorCatalog() throws -> SharedErrorCatalog {
        try decode(SharedErrorCatalog.self, named: "error-catalog.json")
    }

    static func decode<Document: Decodable>(_ type: Document.Type, named name: String) throws -> Document {
        try JSONDecoder().decode(type, from: Data(contentsOf: contractURL(named: name)))
    }
}
