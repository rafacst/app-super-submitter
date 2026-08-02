import Foundation
import Testing
@testable import SubmitKit

private func temporaryRoot() throws -> URL {
    let url = FileManager.default.temporaryDirectory
        .appendingPathComponent("super-submitter-tests/\(UUID().uuidString)")
    try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
    return url
}

@Test func theRunLogWritesOneJSONLineEveryCall() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let log = try RunLog(root: root)
    await log.append(APICall(system: "apple", method: "POST", path: "/v1/appStoreVersions",
                             status: 201, durationMs: 412, requestId: "abc"))
    await log.append(APICall(system: "google", method: "POST", path: "/edits",
                             status: 200, durationMs: 180))
    await log.close()

    let text = try String(contentsOf: log.url, encoding: .utf8)
    let lines = text.split(separator: "\n")
    #expect(lines.count == 2)
    #expect(log.url.path.contains(".super-submitter/runs"))
    #expect(log.url.pathExtension == "jsonl")

    let first = JSON(data: Data(lines[0].utf8))
    #expect(first["call"]["status"].int == 201)
    #expect(first["call"]["path"].string == "/v1/appStoreVersions")
    #expect(first["time"].string?.isEmpty == false)
}

@Test func theRunLogHoldsNoTokenAndNoBody() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }

    let log = try RunLog(root: root)
    await log.append(APICall(system: "apple", method: "PATCH", path: "/v1/appInfos/1",
                             status: 200, durationMs: 90))
    await log.close()

    let text = try String(contentsOf: log.url, encoding: .utf8)
    // The record type carries no header, no body, and no credential field, so
    // no secret can reach a file that sits in a repository.
    #expect(!text.lowercased().contains("authorization"))
    #expect(!text.lowercased().contains("bearer"))
    for key in JSON(data: Data(text.split(separator: "\n")[0].utf8))["call"].keys {
        #expect(["system", "method", "path", "status", "durationMs", "requestId",
                 "error", "dryRun"].contains(key))
    }
}

@Test func aDryRunLineReadsAsADryRun() {
    let call = APICall(system: "apple", method: "POST", path: "/v1/appStoreVersions",
                       dryRun: true)
    let line = call.line(at: Date())

    #expect(line.contains("POST"))
    #expect(line.contains("/v1/appStoreVersions"))
    #expect(line.contains("dry"))
}

@Test func aRunLogUsesOwnerOnlyPermissions() async throws {
    let root = try temporaryRoot()
    defer { try? FileManager.default.removeItem(at: root) }
    let log = try RunLog(root: root)
    await log.close()

    let mode = try FileManager.default.attributesOfItem(atPath: log.url.path)[.posixPermissions]
        as? NSNumber

    #expect(mode?.intValue == 0o600)
}
