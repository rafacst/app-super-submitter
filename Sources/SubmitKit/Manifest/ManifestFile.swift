import Foundation
import Yams

/// Reads and writes `store.yaml`.
///
/// The file is the source of truth. Every tab edits it, and nothing else
/// stores the desired state. Spec section 4.
public enum ManifestFile {
    public static let defaultName = "store.yaml"

    public static func load(from url: URL) throws -> Manifest {
        let text = try String(contentsOf: url, encoding: .utf8)
        return try decode(text)
    }

    public static func decode(_ yaml: String) throws -> Manifest {
        try YAMLDecoder().decode(Manifest.self, from: yaml)
    }

    public static func encode(_ manifest: Manifest) throws -> String {
        let encoder = YAMLEncoder()
        encoder.options.indent = 2
        encoder.options.width = 80
        encoder.options.sortKeys = false
        return try encoder.encode(manifest)
    }

    public static func save(_ manifest: Manifest, to url: URL) throws {
        try encode(manifest).write(to: url, atomically: true, encoding: .utf8)
    }
}
