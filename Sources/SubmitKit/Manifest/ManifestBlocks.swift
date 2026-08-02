import Foundation
import Yams

/// The manifest blocks that one tab owns. Spec section 16.1: each tab holds a
/// YAML toggle that shows the raw block behind that tab, and **both sides edit
/// the same file**.
///
/// `// ponytail: slice the encoded document by top-level key. A second
/// // per-tab serializer would be a second place for the schema to drift.`
public enum ManifestBlock: String, Sendable, CaseIterable {
    case stores, build, details, media, money, reviewInfo

    /// The top-level keys of `store.yaml` that this tab writes.
    public var keys: [String] {
        switch self {
        case .stores: ["apps"]
        case .build: ["release"]
        case .details: ["listing"]
        case .media: ["media"]
        case .money: ["monetization", "pricing", "purchases", "subscriptions",
                      "entitlements", "offerings"]
        case .reviewInfo: ["review"]
        }
    }
}

public enum ManifestBlockError: Error, LocalizedError, Equatable {
    case notAMapping
    case unknownKey(String, ManifestBlock)

    public var errorDescription: String? {
        switch self {
        case .notAMapping:
            "The YAML must be a block of keys, for example `apps:`."
        case .unknownKey(let key, let block):
            "`\(key)` does not belong to this tab. It writes \(block.keys.joined(separator: ", "))."
        }
    }
}

public extension ManifestFile {
    /// The raw YAML of one tab's blocks, in the order the schema states them.
    static func encode(_ manifest: Manifest, block: ManifestBlock) throws -> String {
        let whole = try Yams.compose(yaml: encode(manifest)) ?? .mapping([:])
        guard case .mapping(let mapping) = whole else { return "" }
        var slice = Yams.Node.Mapping()
        for key in block.keys {
            guard let value = mapping[Yams.Node(key)] else { continue }
            slice[Yams.Node(key)] = value
        }
        guard !slice.isEmpty else { return "# This tab holds nothing yet.\n" }
        return try Yams.serialize(node: .mapping(slice), indent: 2, width: 80,
                                  sortKeys: false)
    }

    /// Writes an edited block back into the manifest.
    ///
    /// The block replaces its own keys and touches nothing else, so an edit on
    /// the Media tab can never drop the pricing.
    static func apply(_ yaml: String, block: ManifestBlock,
                      to manifest: Manifest) throws -> Manifest {
        let whole = try Yams.compose(yaml: encode(manifest)) ?? .mapping([:])
        guard case .mapping(var mapping) = whole else { throw ManifestBlockError.notAMapping }

        let trimmed = yaml.trimmingCharacters(in: .whitespacesAndNewlines)
        let edited: Yams.Node.Mapping
        if trimmed.isEmpty {
            edited = Yams.Node.Mapping()
        } else if let parsed = try Yams.compose(yaml: yaml) {
            guard case .mapping(let value) = parsed else {
                throw ManifestBlockError.notAMapping
            }
            edited = value
        } else {
            // A comments-only document composes to nil and represents an empty
            // block. A leading comment followed by YAML still composes above.
            edited = Yams.Node.Mapping()
        }

        for key in edited.keys {
            guard let name = key.string, block.keys.contains(name) else {
                throw ManifestBlockError.unknownKey(key.string ?? "?", block)
            }
        }
        for key in block.keys {
            let node = Yams.Node(key)
            mapping[node] = edited[node]
        }
        return try decode(try Yams.serialize(node: .mapping(mapping), indent: 2, width: 80,
                                             sortKeys: false))
    }
}
