import Foundation
import Yams

/// A `store.yaml` the app could not read, said in words the developer can act
/// on.
///
/// `DecodingError.localizedDescription` says "The data couldn't be read
/// because it is missing." for every failure, and it names no key and no line.
/// That is the whole message a developer used to get for one forgotten key in
/// a file of four hundred lines.
public struct ManifestError: Error, LocalizedError, Equatable {
    public let message: String
    public var errorDescription: String? { message }
    public init(_ message: String) { self.message = message }
}

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

    /// The one door in. `ManifestBlocks.apply` ends here too, so the YAML
    /// editor and the file both explain a failure the same way.
    public static func decode(_ yaml: String) throws -> Manifest {
        do {
            return try YAMLDecoder().decode(Manifest.self, from: yaml)
        } catch let error as DecodingError {
            throw ManifestError(explain(error, in: yaml))
        }
        // A `YamlError` passes through untouched. It already carries its own
        // line, column, and a snippet of the offending text.
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

    // MARK: - Saying what is wrong

    static func explain(_ error: DecodingError, in yaml: String) -> String {
        let path: [any CodingKey]
        let problem: String
        switch error {
        case .keyNotFound(let key, let context):
            path = context.codingPath + [key]
            problem = "is missing"
        case .typeMismatch(let type, let context):
            path = context.codingPath
            problem = "must be \(words(for: type))"
        case .valueNotFound(let type, let context):
            path = context.codingPath
            problem = "has no value, and it needs \(words(for: type))"
        case .dataCorrupted(let context):
            path = context.codingPath
            problem = context.debugDescription
        @unknown default:
            return error.localizedDescription
        }

        let name = describe(path)
        // The deepest node the path reaches. A missing key has no node of its
        // own, so this lands on the block that should have carried it, which
        // is the line to open.
        let place = line(of: path, in: yaml).map { " Look at line \($0)." } ?? ""
        guard !name.isEmpty else { return "The file \(problem).\(place)" }
        return "The key \(name) \(problem).\(place)"
    }

    /// `pricing.territories[0].available`, the way a person would point at it.
    static func describe(_ path: [any CodingKey]) -> String {
        path.reduce(into: "") { text, key in
            if let index = key.intValue {
                text += "[\(index)]"
            } else {
                text += text.isEmpty ? key.stringValue : ".\(key.stringValue)"
            }
        }
    }

    /// Walks the same path through the YAML tree and reads the mark off the
    /// deepest node it reaches.
    static func line(of path: [any CodingKey], in yaml: String) -> Int? {
        guard let root = try? Yams.compose(yaml: yaml) else { return nil }
        var node = root
        for key in path {
            let next: Yams.Node?
            if let index = key.intValue {
                let items = node.sequence
                next = items.map(Array.init).flatMap { $0.indices.contains(index) ? $0[index] : nil }
            } else {
                next = node[key.stringValue]
            }
            guard let next else { break }
            node = next
        }
        return node.mark?.line
    }

    /// What the developer has to type, not what Swift calls the type.
    static func words(for type: Any.Type) -> String {
        if type == Bool.self { return "true or false" }
        if type == String.self { return "text" }
        if type == Int.self || type == Double.self || type == Decimal.self { return "a number" }
        let name = "\(type)"
        if name.hasPrefix("Array") { return "a list" }
        if name.hasPrefix("Dictionary") { return "a block of keys" }
        return "a block"
    }
}
