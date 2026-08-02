import Foundation

/// A field with three states, from the manifest design rules in spec 5.1.
///
/// - The key is absent: do not manage this field. Never write it, never
///   delete the remote value.
/// - The key is `null`: clear the remote value.
/// - The key holds a value: write that value.
///
/// A plain `Optional` collapses the first two states into one. That loses the
/// user intent on a load and a save, and the save writes back to a file in
/// their repository. So the three states need three cases.
public enum Managed<Value: Codable & Sendable & Equatable>: Sendable, Equatable {
    case unmanaged
    case clear
    case value(Value)

    public var value: Value? {
        if case .value(let v) = self { return v }
        return nil
    }

    /// True when an apply writes this field.
    public var isManaged: Bool {
        if case .unmanaged = self { return false }
        return true
    }
}

extension Managed: Codable {
    public init(from decoder: any Decoder) throws {
        let container = try decoder.singleValueContainer()
        if container.decodeNil() {
            self = .clear
        } else {
            self = .value(try container.decode(Value.self))
        }
    }

    public func encode(to encoder: any Encoder) throws {
        var container = encoder.singleValueContainer()
        switch self {
        case .unmanaged, .clear: try container.encodeNil()
        case .value(let v): try container.encode(v)
        }
    }
}

// The two overloads below carry the absent case. The compiler prefers them
// over the generic `encode`/`decode`, so every synthesized `Codable` on a
// struct that holds a `Managed` field gets the behaviour for free.

extension KeyedDecodingContainer {
    public func decode<V>(_ type: Managed<V>.Type, forKey key: Key) throws -> Managed<V> {
        guard contains(key) else { return .unmanaged }
        if try decodeNil(forKey: key) { return .clear }
        return .value(try decode(V.self, forKey: key))
    }

    /// Text needs one more rule than the generic case above.
    ///
    /// A YAML `|` block always ends with a newline, and a save writes the text
    /// back as a quoted scalar without it. The value would then change on a
    /// save that the developer did not make, and the next plan would show a
    /// diff against a store that holds the same words. So the trailing
    /// newlines go at the load, once, before anything compares them.
    public func decode(_ type: Managed<String>.Type, forKey key: Key) throws -> Managed<String> {
        guard contains(key) else { return .unmanaged }
        if try decodeNil(forKey: key) { return .clear }
        var text = try decode(String.self, forKey: key)
        while text.hasSuffix("\n") { text.removeLast() }
        return .value(text)
    }
}

extension KeyedEncodingContainer {
    public mutating func encode<V>(_ value: Managed<V>, forKey key: Key) throws {
        switch value {
        case .unmanaged: return            // write no key at all
        case .clear: try encodeNil(forKey: key)
        case .value(let v): try encode(v, forKey: key)
        }
    }
}
