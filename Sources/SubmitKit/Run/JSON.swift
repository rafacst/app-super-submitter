import Foundation

/// A read-only view over a decoded JSON payload.
///
/// The store payloads are wide, loosely shaped, and read in one place each.
/// Thirty `Decodable` structs would cost more lines than they save and would
/// break on the first field that Apple adds.
///
/// `// ponytail: JSONSerialization plus five accessors. Add a Codable model
/// // when a payload is written back, not when it is only read.`
/// The payload is a `JSONSerialization` tree of immutable Foundation values,
/// and nothing here mutates it, so the read-only view crosses actors safely.
public struct JSON: @unchecked Sendable {
    private let raw: Any?

    public init(_ raw: Any?) { self.raw = raw }

    public init(data: Data) {
        self.raw = try? JSONSerialization.jsonObject(with: data, options: [.fragmentsAllowed])
    }

    public subscript(key: String) -> JSON {
        JSON((raw as? [String: Any])?[key])
    }

    public subscript(index: Int) -> JSON {
        let list = raw as? [Any]
        guard let list, list.indices.contains(index) else { return JSON(nil) }
        return JSON(list[index])
    }

    public var array: [JSON] { (raw as? [Any])?.map(JSON.init) ?? [] }
    public var keys: [String] { ((raw as? [String: Any])?.keys).map(Array.init) ?? [] }
    public var string: String? { raw as? String }
    public var int: Int? { (raw as? Int) ?? (raw as? String).flatMap(Int.init) }
    public var double: Double? { (raw as? Double) ?? (raw as? String).flatMap(Double.init) }
    public var bool: Bool? { raw as? Bool }
    public var exists: Bool { raw != nil }

    /// `data[].id` keyed by `data[].attributes.locale`, read straight off a
    /// localization list. Every Apple localization resource answers that one
    /// shape, so an upsert asks this and never walks the array itself.
    public var idsByLocale: [String: String] {
        self["data"].array.reduce(into: [:]) { result, item in
            guard let locale = item["attributes"]["locale"].string,
                  let id = item["id"].string else { return }
            result[locale] = id
        }
    }
}

public extension Date {
    /// A store timestamp, with or without the fractional seconds.
    ///
    /// Apple stamps both shapes into the same field and the licensing service
    /// does the same, so every reader has to take both. Four readers each
    /// carried their own pair of formatters before this one.
    ///
    /// A fresh formatter per call. `ISO8601DateFormatter` is not `Sendable`,
    /// and these are read a handful of times per session, so a shared one
    /// would buy nothing and cost a lock. A bare `ISO8601DateFormatter`
    /// already means `.withInternetDateTime`, which is the plain shape.
    static func iso8601(_ text: String?) -> Date? {
        guard let text else { return nil }
        let withFraction = ISO8601DateFormatter()
        withFraction.formatOptions = [.withInternetDateTime, .withFractionalSeconds]
        return withFraction.date(from: text) ?? ISO8601DateFormatter().date(from: text)
    }
}
