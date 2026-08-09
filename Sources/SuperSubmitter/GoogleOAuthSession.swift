import AppKit
import Darwin
import Foundation
import SubmitKit

enum GoogleOAuthConfiguration {
    static var clientID: String? {
        let value = ProcessInfo.processInfo.environment["GOOGLE_OAUTH_CLIENT_ID"]
            ?? Bundle.main.object(forInfoDictionaryKey: "SSGoogleOAuthClientID") as? String
        guard let value, !value.isEmpty, !value.hasPrefix("$(") else { return nil }
        return value
    }
}

@MainActor
enum GoogleOAuthSession {
    static func authorize(clientID: String) async throws -> GoogleOAuthCredential {
        let server = try LoopbackServer()
        let redirectURI = "http://127.0.0.1:\(server.port)"
        let state = try GoogleOAuth.randomToken()
        let verifier = try GoogleOAuth.randomToken(byteCount: 64)
        let url = try GoogleOAuth.authorizationURL(
            clientID: clientID, redirectURI: redirectURI, state: state, verifier: verifier)
        guard NSWorkspace.shared.open(url) else { throw LoopbackServer.Error.browser }

        return try await withTaskCancellationHandler {
            let callback = try await Task.detached { try server.waitForCallback() }.value
            let code = try GoogleOAuth.authorizationCode(from: callback, expectedState: state)
            return try await GoogleOAuth.exchange(
                code: code, clientID: clientID, redirectURI: redirectURI, verifier: verifier)
        } onCancel: {
            server.close()
        }
    }
}

private final class LoopbackServer: @unchecked Sendable {
    enum Error: Swift.Error, LocalizedError {
        case socket
        case callback
        case timedOut
        case browser

        var errorDescription: String? {
            switch self {
            case .socket: "Super Submitter could not start Google's secure local callback."
            case .callback: "Google returned an unreadable authorization callback."
            case .timedOut: "Google authorization timed out. Try connecting again."
            case .browser: "Super Submitter could not open the Google authorization page."
            }
        }
    }

    let port: UInt16
    private let lock = NSLock()
    private var descriptor: Int32

    init() throws {
        let fd = Darwin.socket(AF_INET, SOCK_STREAM, 0)
        guard fd >= 0 else { throw Error.socket }
        var reuse: Int32 = 1
        setsockopt(fd, SOL_SOCKET, SO_REUSEADDR, &reuse, socklen_t(MemoryLayout.size(ofValue: reuse)))

        var address = sockaddr_in()
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = 0
        address.sin_addr = in_addr(s_addr: inet_addr("127.0.0.1"))
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                Darwin.bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0, Darwin.listen(fd, 1) == 0 else {
            Darwin.close(fd)
            throw Error.socket
        }
        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        let named = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                getsockname(fd, $0, &length)
            }
        }
        guard named == 0 else {
            Darwin.close(fd)
            throw Error.socket
        }
        descriptor = fd
        port = UInt16(bigEndian: actual.sin_port)
    }

    deinit { close() }

    func close() {
        lock.withLock {
            guard descriptor >= 0 else { return }
            Darwin.close(descriptor)
            descriptor = -1
        }
    }

    func waitForCallback() throws -> URL {
        let fd = lock.withLock { descriptor }
        guard fd >= 0 else { throw CancellationError() }
        var ready = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
        for _ in 0..<1_200 {
            if Task.isCancelled { throw CancellationError() }
            let result = Darwin.poll(&ready, 1, 250)
            if result > 0 { break }
            if result < 0, errno != EINTR { throw Error.socket }
        }
        guard ready.revents & Int16(POLLIN) != 0 else { throw Error.timedOut }

        let client = Darwin.accept(fd, nil, nil)
        guard client >= 0 else { throw Error.socket }
        defer {
            Darwin.close(client)
            close()
        }
        var bytes = [UInt8](repeating: 0, count: 16_384)
        let count = Darwin.read(client, &bytes, bytes.count)
        guard count > 0,
              let line = String(bytes: bytes.prefix(count), encoding: .utf8)?
                .components(separatedBy: "\r\n").first,
              line.hasPrefix("GET "),
              let target = line.split(separator: " ").dropFirst().first,
              let callback = URL(string: String(target),
                                 relativeTo: URL(string: "http://127.0.0.1:\(port)"))?
                .absoluteURL else { throw Error.callback }

        let body = "Google authorization complete. You can close this tab and return to Super Submitter."
        let response = "HTTP/1.1 200 OK\r\nContent-Type: text/plain; charset=utf-8\r\nContent-Length: \(body.utf8.count)\r\nConnection: close\r\n\r\n\(body)"
        _ = response.withCString { Darwin.write(client, $0, strlen($0)) }
        return callback
    }
}
