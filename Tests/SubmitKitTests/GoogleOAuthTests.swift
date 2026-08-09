import Foundation
import Testing
@testable import SubmitKit

private final class GoogleOAuthProtocol: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) static var handler: (@Sendable (URLRequest) throws
        -> (HTTPURLResponse, Data))?

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        do {
            let (response, data) = try Self.handler!(request)
            client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
            client?.urlProtocol(self, didLoad: data)
            client?.urlProtocolDidFinishLoading(self)
        } catch {
            client?.urlProtocol(self, didFailWithError: error)
        }
    }

    override func stopLoading() {}
}

private func googleOAuthSession() -> URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.protocolClasses = [GoogleOAuthProtocol.self]
    return URLSession(configuration: configuration)
}

private func requestBody(_ request: URLRequest) -> String {
    if let body = request.httpBody { return String(decoding: body, as: UTF8.self) }
    guard let stream = request.httpBodyStream else { return "" }
    stream.open()
    defer { stream.close() }
    var data = Data()
    var buffer = [UInt8](repeating: 0, count: 1_024)
    while stream.hasBytesAvailable {
        let count = stream.read(&buffer, maxLength: buffer.count)
        guard count > 0 else { break }
        data.append(contentsOf: buffer.prefix(count))
    }
    return String(decoding: data, as: UTF8.self)
}

@Suite(.serialized)
struct GoogleOAuthTests {
    @Test func authorizationRequestsOfflinePublisherAccessWithPKCE() throws {
        let url = try GoogleOAuth.authorizationURL(
            clientID: "desktop.apps.googleusercontent.com",
            redirectURI: "http://127.0.0.1:49152",
            state: "csrf-state",
            verifier: String(repeating: "v", count: 64))
        let components = try #require(URLComponents(url: url, resolvingAgainstBaseURL: false))
        let query: [String: String] = Dictionary(uniqueKeysWithValues:
            (components.queryItems ?? []).map { ($0.name, $0.value ?? "") })

        #expect(components.host == "accounts.google.com")
        #expect(query["client_id"] == "desktop.apps.googleusercontent.com")
        #expect(query["redirect_uri"] == "http://127.0.0.1:49152")
        #expect(query["response_type"] == "code")
        #expect(query["access_type"] == "offline")
        #expect(query["code_challenge_method"] == "S256")
        #expect(query["state"] == "csrf-state")
        #expect(query["scope"]?.contains("auth/androidpublisher") == true)
        #expect(query["scope"]?.contains("auth/playdeveloperreporting") == true)
    }

    @Test func callbackRejectsAnotherAuthorizationState() throws {
        let callback = URL(string: "http://127.0.0.1:49152/?code=secret&state=attacker")!

        #expect(throws: GoogleOAuth.Error.invalidState) {
            try GoogleOAuth.authorizationCode(from: callback, expectedState: "expected")
        }
    }

    @Test func codeExchangeKeepsTheRefreshTokenForLaterCalls() async throws {
        let session = googleOAuthSession()
        defer { session.invalidateAndCancel() }
        GoogleOAuthProtocol.handler = { request in
            #expect(request.url?.absoluteString == "https://oauth2.googleapis.com/token")
            let body = requestBody(request)
            #expect(body.contains("grant_type=authorization_code"))
            #expect(body.contains("code_verifier="))
            let data = Data(#"{"access_token":"access","refresh_token":"refresh","expires_in":3600}"#.utf8)
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!, data)
        }

        let credential = try await GoogleOAuth.exchange(
            code: "code", clientID: "client", redirectURI: "http://127.0.0.1:49152",
            verifier: String(repeating: "v", count: 64), session: session)

        #expect(credential.accessToken == "access")
        #expect(credential.refreshToken == "refresh")
        #expect(credential.clientID == "client")
        #expect(credential.expiresAt > Date().addingTimeInterval(3_500))
    }

    @Test func storeCallsMayUseAUserOAuthTokenInsteadOfAJSONKey() async throws {
        let session = googleOAuthSession()
        defer { session.invalidateAndCancel() }
        GoogleOAuthProtocol.handler = { request in
            #expect(request.url?.host == "androidpublisher.googleapis.com")
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer user-access")
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let credential = GoogleOAuthCredential(
            clientID: "client", accessToken: "user-access", refreshToken: "refresh",
            expiresAt: .distantFuture)
        let api = StoreAPI(credentials: StoreCredentials(googleOAuth: credential),
                           record: { _ in }, session: session)

        _ = try await api.google("GET", "/androidpublisher/v3/applications/example/reviews")
    }

    @Test func expiredUserOAuthTokenIsRefreshed() async throws {
        let session = googleOAuthSession()
        defer { session.invalidateAndCancel() }
        GoogleOAuthProtocol.handler = { request in
            if request.url?.host == "oauth2.googleapis.com" {
                let body = requestBody(request)
                #expect(body.contains("grant_type=refresh_token"))
                #expect(body.contains("refresh_token=refresh"))
                let data = Data(#"{"access_token":"new-access","expires_in":3600}"#.utf8)
                return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                        httpVersion: nil, headerFields: nil)!, data)
            }
            #expect(request.value(forHTTPHeaderField: "Authorization") == "Bearer new-access")
            return (HTTPURLResponse(url: request.url!, statusCode: 200,
                                    httpVersion: nil, headerFields: nil)!, Data("{}".utf8))
        }
        let credential = GoogleOAuthCredential(
            clientID: "client", accessToken: "expired", refreshToken: "refresh",
            expiresAt: .distantPast)
        let api = StoreAPI(credentials: StoreCredentials(googleOAuth: credential),
                           record: { _ in }, session: session)

        _ = try await api.google("GET", "/androidpublisher/v3/applications/example/reviews")
    }
}
