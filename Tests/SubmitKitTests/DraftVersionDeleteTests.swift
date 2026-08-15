import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// A draft that cannot be repaired needs a way out, and until now the only one
/// was App Store Connect. `DELETE /v1/appStoreVersions/{id}` takes the version
/// and everything in it, so the screen asks twice and this checks the call.

private final class DeleteStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var calls: [String] = []
    nonisolated(unsafe) private static var bodies: [[String: Any]] = []
    private static let lock = NSLock()

    static func start() { lock.withLock { calls = []; bodies = [] } }
    static var seen: [String] { lock.withLock { calls } }

    /// The attributes of the first body sent, which is all these calls carry.
    static var attributes: [String: Any] {
        lock.withLock {
            (bodies.first?["data"] as? [String: Any])?["attributes"] as? [String: Any] ?? [:]
        }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let url = request.url!
        var data = request.httpBody
        if data == nil, let stream = request.httpBodyStream {
            stream.open()
            defer { stream.close() }
            var bytes = [UInt8](repeating: 0, count: 64 * 1_024)
            var collected = Data()
            while stream.hasBytesAvailable {
                let count = stream.read(&bytes, maxLength: bytes.count)
                guard count > 0 else { break }
                collected.append(contentsOf: bytes[..<count])
            }
            data = collected
        }
        let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) } as? [String: Any]
        Self.lock.withLock {
            Self.calls.append("\(request.httpMethod ?? "") \(url.path)")
            if let body { Self.bodies.append(body) }
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

    /// The delete alone touches no build. The binary stays in App Store
    /// Connect and stays in TestFlight, which is what the panel now says.
    @Test func theDeleteOnItsOwnSendsNoBuildCall() async throws {
        try await deleteClient().deleteAppleDraftVersion(versionID: "ver-1")

        #expect(!DeleteStub.seen.contains { $0.hasPrefix("PATCH /v1/builds") })
    }

    /// Expiring is the whole of what Apple offers for a build. There is no
    /// `DELETE /v1/builds/{id}` and no call that removes the binary, so the
    /// option says expire and the request carries the one attribute that does
    /// it.
    @Test func expiringABuildPatchesItExpired() async throws {
        try await deleteClient().expireAppleBuild(buildID: "build-9")

        #expect(DeleteStub.seen == ["PATCH /v1/builds/build-9"])
        #expect(DeleteStub.attributes["expired"] as? Bool == true)
        // Nothing else rides along. `usesNonExemptEncryption` is the other
        // attribute of this request and it belongs to the upload, not here.
        #expect(DeleteStub.attributes.count == 1)
    }

    /// It takes a build off TestFlight, so it sits behind the same gate as the
    /// delete it follows.
    @Test func theExpireIsBehindTheReleaseGate() async throws {
        await #expect(throws: (any Error).self) {
            try await deleteClient(access: GrantNone()).expireAppleBuild(buildID: "build-9")
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
