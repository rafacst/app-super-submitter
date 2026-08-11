import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// The reviewer sign-in App Store Connect already holds, on one button.
///
/// The Review info tab could only offer it after the whole store read on the
/// Summary tab had filled `actualState`. A developer standing on that tab with
/// two empty fields, on an app that has shipped with a demo account several
/// times, had nothing to press: the account was in App Store Connect and the
/// way to it was another tab.
private final class ReviewDetailStub: URLProtocol, @unchecked Sendable {
    /// Answered oldest first, which App Store Connect is free to do, and the
    /// account lives on the older one.
    static let versions = """
    {"data":[
      {"id":"v-120","type":"appStoreVersions",
       "attributes":{"versionString":"1.2","platform":"IOS",
                     "appVersionState":"READY_FOR_SALE"}},
      {"id":"v-140","type":"appStoreVersions",
       "attributes":{"versionString":"1.4","platform":"IOS",
                     "appVersionState":"PREPARE_FOR_SUBMISSION"}}
     ]}
    """

    /// The draft carries the empty string Apple returns for a value it will
    /// not hand back. The released version carries the account.
    static func detail(_ versionID: String) -> String {
        versionID == "v-140"
            ? """
              {"data":{"id":"d-140","type":"appStoreReviewDetails",
               "attributes":{"demoAccountRequired":true,"demoAccountName":"",
                             "demoAccountPassword":""}}}
              """
            : """
              {"data":{"id":"d-120","type":"appStoreReviewDetails",
               "attributes":{"demoAccountRequired":true,
                             "demoAccountName":"reviewer@example.com",
                             "demoAccountPassword":""}}}
              """
    }

    static let requested = Requested()
    final class Requested: @unchecked Sendable {
        private let lock = NSLock()
        private var paths: [String] = []
        var all: [String] { lock.withLock { paths } }
        func add(_ path: String) { lock.withLock { paths.append(path) } }
        func clear() { lock.withLock { paths = [] } }
    }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        let path = request.url?.path ?? ""
        Self.requested.add(path)
        let body: String
        if path.hasSuffix("/appStoreVersions") {
            body = Self.versions
        } else if path.hasSuffix("/appStoreReviewDetail") {
            let id = path.split(separator: "/").dropLast().last.map(String.init) ?? ""
            body = Self.detail(id)
        } else {
            body = #"{"data":[]}"#
        }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Data(body.utf8))
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct DemoAccountReadTests {

    private func client() -> AppleActionsClient {
        ReviewDetailStub.requested.clear()
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [ReviewDetailStub.self]
        let credential = AppleCredential(
            keyID: "ABCD123456", issuerID: "issuer",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
            fileName: "AuthKey_ABCD123456.p8")
        return AppleActionsClient(api: StoreAPI(
            credentials: StoreCredentials(apple: credential), record: { _ in },
            session: URLSession(configuration: configuration)))
    }

    @Test func itWalksBackToTheVersionThatNamesTheAccount() async throws {
        let signIn = try await client().reviewSignIn(appID: "1")

        #expect(signIn.name == "reviewer@example.com")
        #expect(signIn.versionString == "1.2")
        // Apple withholds it, and "" is not an answer.
        #expect(signIn.password == nil)
    }

    /// The draft is asked before the released version, whatever order the API
    /// answered the list in.
    @Test func theNewestVersionIsAskedFirst() async throws {
        _ = try await client().reviewSignIn(appID: "1")

        let details = ReviewDetailStub.requested.all.filter {
            $0.hasSuffix("/appStoreReviewDetail")
        }
        #expect(details.first?.contains("v-140") == true)
        #expect(details.count == 2, "it stopped at the first account it found")
    }

    /// A read that finds nothing says so rather than offering an empty field.
    @Test func anEmptyAnswerCarriesNoAccount() async throws {
        let signIn = try await client().reviewSignIn(appID: "1", depth: 1)

        #expect(signIn.name == nil)
        #expect(signIn.required == true)
        #expect(!signIn.isEmpty, "the draft still answered the required flag")
    }
}
