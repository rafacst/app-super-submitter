import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// A draft that cannot be repaired needs a way out, and until now the only one
/// was App Store Connect. `DELETE /v1/appStoreVersions/{id}` takes the version
/// and everything in it, so the screen asks twice and this checks the call.

private final class DeleteStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var calls: [String] = []
    private static let lock = NSLock()

    static func start() { lock.withLock { calls = [] } }
    static var seen: [String] { lock.withLock { calls } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        Self.lock.withLock {
            Self.calls.append("\(request.httpMethod ?? "") \(url.path)")
        }
        let response = HTTPURLResponse(url: url, statusCode: 204,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data("{}".utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func deleteClient(access: any AccessGate = GrantAll()) -> ReleaseClient {
    DeleteStub.start()
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [DeleteStub.self]
    let credential = AppleCredential(
        keyID: "ABCD123456", issuerID: "issuer",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
        fileName: "AuthKey_ABCD123456.p8")
    return ReleaseClient(
        api: StoreAPI(credentials: StoreCredentials(apple: credential), record: { _ in },
                      session: URLSession(configuration: configuration)),
        access: access)
}

@Suite(.serialized)
struct DraftVersionDeleteTests {
    @Test func theDeleteReachesTheVersionAndNothingElse() async throws {
        try await deleteClient().deleteAppleDraftVersion(versionID: "ver-1")

        #expect(DeleteStub.seen == ["DELETE /v1/appStoreVersions/ver-1"])
    }

    /// It undoes more than any other call in this app, so it sits behind the
    /// same gate as the submission and the cancel.
    @Test func theDeleteIsBehindTheReleaseGate() async throws {
        let denied = GrantNone()

        await #expect(throws: (any Error).self) {
            try await deleteClient(access: denied)
                .deleteAppleDraftVersion(versionID: "ver-1")
        }
        #expect(DeleteStub.seen.isEmpty)
    }

    /// Only a version the developer can still edit. A version in review belongs
    /// to Apple until it answers, and one that shipped is what customers have.
    @Test func onlyAnEditableVersionIsEverOffered() {
        #expect(AppleVersionState.editable.contains("PREPARE_FOR_SUBMISSION"))
        #expect(AppleVersionState.editable.contains("DEVELOPER_REJECTED"))
        #expect(!AppleVersionState.editable.contains("IN_REVIEW"))
        #expect(!AppleVersionState.editable.contains("WAITING_FOR_REVIEW"))
        #expect(!AppleVersionState.editable.contains("READY_FOR_SALE"))
        #expect(!AppleVersionState.editable.contains("PENDING_DEVELOPER_RELEASE"))
    }
}
