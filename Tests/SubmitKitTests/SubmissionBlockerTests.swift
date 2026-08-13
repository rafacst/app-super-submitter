import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// Apple answers a refused submit with "This resource cannot be reviewed,
/// please check associated errors to see why" and names no resource at all.
/// The app attached the version, every purchase, every custom product page and
/// every test to one submission, discarded each refusal, and printed Apple's
/// sentence, so the developer had nothing to act on.

private final class SubmitStub: URLProtocol, @unchecked Sendable {
    /// The custom product page add that Apple turns away.
    nonisolated(unsafe) static var refusePageAdd = true
    /// Whether the submit itself is refused.
    nonisolated(unsafe) static var refuseSubmit = true

    static func start(refusingPage: Bool = true, refusingSubmit: Bool = true) {
        refusePageAdd = refusingPage
        refuseSubmit = refusingSubmit
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    private static func answer(_ method: String, _ path: String,
                               _ body: [String: Any]) -> (Int, String) {
        switch (method, path) {
        case ("GET", "/v1/reviewSubmissions"):
            return (200, #"{"data":[]}"#)
        case ("POST", "/v1/reviewSubmissions"):
            return (200, #"{"data":{"id":"sub-1","type":"reviewSubmissions"}}"#)
        case ("GET", "/v1/apps/app-1/appCustomProductPages"):
            return (200, #"""
            {"data":[{"id":"page-1","attributes":{"name":"Bakers","visible":true}}]}
            """#)
        case ("GET", "/v1/appCustomProductPages/page-1/appCustomProductPageVersions"):
            return (200, #"""
            {"data":[{"id":"pv-1","attributes":{"state":"PREPARE_FOR_SUBMISSION"}}]}
            """#)
        case ("POST", "/v1/reviewSubmissionItems"):
            let relationships = (body["data"] as? [String: Any])?["relationships"]
                as? [String: Any] ?? [:]
            if refusePageAdd, relationships["appCustomProductPageVersion"] != nil {
                return (409, #"""
                {"errors":[{"status":"409","code":"STATE_ERROR",
                            "detail":"This resource cannot be reviewed."}]}
                """#)
            }
            return (200, #"{"data":{"id":"item-1","type":"reviewSubmissionItems"}}"#)
        case ("PATCH", "/v1/reviewSubmissions/sub-1"):
            return refuseSubmit
                ? (409, #"""
                   {"errors":[{"status":"409","code":"STATE_ERROR",
                               "detail":"This resource cannot be reviewed, please check associated errors to see why."}]}
                   """#)
                : (200, #"{"data":{"id":"sub-1"}}"#)
        case ("GET", "/v1/reviewSubmissions/sub-1/items"):
            return (200, #"""
            {"data":[
              {"id":"item-1","type":"reviewSubmissionItems",
               "attributes":{"state":"READY_FOR_REVIEW"},
               "relationships":{"appStoreVersion":{"data":{"id":"ver-1"}}}},
              {"id":"item-2","type":"reviewSubmissionItems",
               "attributes":{"state":"REJECTED"},
               "relationships":{"inAppPurchaseVersion":{"data":{"id":"ipv-9"}}}}
            ]}
            """#)
        default:
            return (200, #"{"data":[]}"#)
        }
    }

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
        let body = data.flatMap { try? JSONSerialization.jsonObject(with: $0) }
            as? [String: Any] ?? [:]
        let (status, answer) = Self.answer(request.httpMethod ?? "", url.path, body)
        let response = HTTPURLResponse(url: url, statusCode: status,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(answer.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

private func submitClient() -> ReleaseClient {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [SubmitStub.self]
    let credential = AppleCredential(
        keyID: "ABCD123456", issuerID: "issuer",
        privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
        fileName: "AuthKey_ABCD123456.p8")
    return ReleaseClient(
        api: StoreAPI(credentials: StoreCredentials(apple: credential), record: { _ in },
                      session: URLSession(configuration: configuration)),
        access: GrantAll())
}

@Suite(.serialized)
struct SubmissionBlockerTests {
    /// The page the app itself attached, named the way the developer will find
    /// it in App Store Connect.
    @Test func aRefusedSubmitNamesTheItemAppleTurnedAway() async throws {
        SubmitStub.start()

        await #expect(throws: ReleaseError.self) {
            _ = try await submitClient().releaseApple(
                appID: "app-1", platform: "IOS", versionID: "ver-1")
        }

        do {
            _ = try await submitClient().releaseApple(
                appID: "app-1", platform: "IOS", versionID: "ver-1")
            Issue.record("The submit was refused and should have thrown.")
        } catch {
            let message = error.localizedDescription
            #expect(message.contains("The custom product page Bakers"))
            // And the items read back, for the ones no add refused.
            #expect(message.contains("An in-app purchase (ipv-9)"))
            #expect(message.contains("rejected"))
            // Apple's own sentence is kept, because it is still the cause.
            #expect(message.contains("check associated errors"))
            // The item that is fine is not named.
            #expect(!message.contains("ver-1"))
        }
    }

    /// Nothing to name means Apple's own error travels untouched rather than
    /// being wrapped in a list of nothing.
    @Test func aRefusalWithNothingToNameKeepsApplesOwnError() async throws {
        SubmitStub.start(refusingPage: false)

        do {
            _ = try await submitClient().releaseApple(
                appID: "app-1", platform: "IOS", versionID: "ver-1")
            Issue.record("The submit was refused and should have thrown.")
        } catch let error as ReleaseError {
            // The items read still names the rejected purchase, so this is the
            // rich error even with no add refused.
            #expect(error.localizedDescription.contains("An in-app purchase (ipv-9)"))
        }
    }

    /// A submit Apple takes throws nothing, so no extra request is made and the
    /// happy path is untouched.
    @Test func aSubmitTheStoreAcceptsReturnsTheSubmission() async throws {
        SubmitStub.start(refusingPage: false, refusingSubmit: false)

        let id = try await submitClient().releaseApple(
            appID: "app-1", platform: "IOS", versionID: "ver-1")

        #expect(id == "sub-1")
    }

    /// One item covers one resource, and Apple hangs thirteen relationships off
    /// it. The name is the developer's way back to the thing.
    @Test func anItemIsNamedByTheResourceItCovers() {
        let page = JSON(data: Data(#"""
        {"id":"i","relationships":{"appCustomProductPageVersion":{"data":{"id":"pv-1"}}}}
        """#.utf8))
        #expect(ReleaseClient.itemName(page) == "A custom product page (pv-1)")

        let unknown = JSON(data: Data(#"{"id":"i-7","relationships":{}}"#.utf8))
        #expect(ReleaseClient.itemName(unknown).contains("i-7"))
        #expect(ReleaseClient.stateText("NOT_READY_FOR_REVIEW") == "not ready for review")
    }
}
