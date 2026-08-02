import Foundation
import Testing

@Test func runtimeSourcesContainNoPlaceholderDataset() throws {
    let repository = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent()
        .deletingLastPathComponent()
        .deletingLastPathComponent()
    let sourceRoot = repository.appendingPathComponent("Sources/SuperSubmitter")
    let files = FileManager.default.enumerator(at: sourceRoot,
                                                includingPropertiesForKeys: nil)?
        .compactMap { $0 as? URL }
        .filter { $0.pathExtension == "swift" } ?? []
    let source = try files.map { try String(contentsOf: $0, encoding: .utf8) }
        .joined(separator: "\n")
    let banned = [
        "DemoData", "DemoApp", "DemoKeyValue", "com.example",
        "AuthKey_9F2KQ4X8L1", "FastBillSplit", "118.4 MB", "4.99 USD",
        "Split any bill in seconds", "bill,split,tip,receipt", "1179 × 2555",
        "[\"en-US\", \"pt-BR\"]", "old?.currency ?? \"USD\"",
        "old?.amount ?? 0", "newManifest.addLocale(\"en-US\"",
    ]

    for value in banned {
        #expect(!source.contains(value), "Runtime source still contains placeholder: \(value)")
    }
}
