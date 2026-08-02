import Foundation

/// Reads the `AndroidManifest.xml` of an `.aab`.
///
/// That file is neither plain XML nor the binary XML of an `.apk`. It is a
/// protobuf message, in the aapt2 `XmlNode` schema. `aapt2 dump` reads an
/// `.apk` and refuses an `.aab`, and `bundletool` is a Java program that a
/// Mac does not ship.
///
/// So this file reads the six fields the app needs, straight from the wire
/// format. It costs about 100 lines and it removes a prerequisite: the
/// developer needs no Android SDK on the machine that submits.
///
/// The schema, and the only field numbers this file uses:
///
///     XmlNode      { XmlElement element = 1 }
///     XmlElement   { string name = 3, XmlAttribute attribute = 4, XmlNode child = 5 }
///     XmlAttribute { string name = 2, string value = 3 }
///
/// ponytail: six fields off the wire, not a protobuf runtime. Add
/// SwiftProtobuf when this needs the resource table too.
enum ProtoManifest {

    struct Element {
        var name: String = ""
        var attributes: [String: String] = [:]
        var children: [Element] = []

        func firstChild(_ name: String) -> Element? {
            children.first { $0.name == name }
        }

        func childrenNamed(_ name: String) -> [Element] {
            children.filter { $0.name == name }
        }
    }

    /// Returns the root `<manifest>` element.
    static func parse(_ data: Data) throws -> Element {
        guard let root = try node(Array(data)) else {
            throw PackageError.unreadable("AndroidManifest.xml", "The proto holds no element.")
        }
        return root
    }

    // MARK: - The three messages

    private static func node(_ bytes: [UInt8]) throws -> Element? {
        var scanner = Scanner(bytes)
        while let field = try scanner.next() {
            if field.number == 1, case .bytes(let payload) = field.value {
                return try element(payload)
            }
        }
        return nil
    }

    private static func element(_ bytes: [UInt8]) throws -> Element {
        var result = Element()
        var scanner = Scanner(bytes)
        while let field = try scanner.next() {
            guard case .bytes(let payload) = field.value else { continue }
            switch field.number {
            case 3:
                result.name = String(decoding: payload, as: UTF8.self)
            case 4:
                let pair = try attribute(payload)
                // The local name is enough. Two attributes that share a local
                // name in different namespaces do not occur in a manifest.
                if !pair.name.isEmpty { result.attributes[pair.name] = pair.value }
            case 5:
                if let child = try node(payload) { result.children.append(child) }
            default:
                break
            }
        }
        return result
    }

    private static func attribute(_ bytes: [UInt8]) throws -> (name: String, value: String) {
        var name = "", value = ""
        var scanner = Scanner(bytes)
        while let field = try scanner.next() {
            guard case .bytes(let payload) = field.value else { continue }
            switch field.number {
            case 2: name = String(decoding: payload, as: UTF8.self)
            case 3: value = String(decoding: payload, as: UTF8.self)
            default: break
            }
        }
        return (name, value)
    }

    // MARK: - The wire format

    private enum Value {
        case varint(UInt64)
        case bytes([UInt8])
        case fixed64(UInt64)
        case fixed32(UInt32)
    }

    private struct Scanner {
        private let bytes: [UInt8]
        private var index = 0

        init(_ bytes: [UInt8]) { self.bytes = bytes }

        mutating func next() throws -> (number: Int, value: Value)? {
            guard index < bytes.count else { return nil }
            let key = try varint()
            let number = Int(key >> 3)
            switch key & 7 {
            case 0:
                return (number, .varint(try varint()))
            case 1:
                return (number, .fixed64(try fixed(8)))
            case 2:
                let length = Int(try varint())
                guard length >= 0, index + length <= bytes.count else { throw truncated }
                defer { index += length }
                return (number, .bytes(Array(bytes[index..<(index + length)])))
            case 5:
                return (number, .fixed32(UInt32(try fixed(4))))
            default:
                throw PackageError.unreadable("AndroidManifest.xml", "Unknown wire type.")
            }
        }

        private mutating func varint() throws -> UInt64 {
            var result: UInt64 = 0
            var shift: UInt64 = 0
            while index < bytes.count {
                let byte = bytes[index]
                index += 1
                result |= UInt64(byte & 0x7F) << shift
                if byte & 0x80 == 0 { return result }
                shift += 7
                if shift > 63 { throw truncated }
            }
            throw truncated
        }

        private mutating func fixed(_ count: Int) throws -> UInt64 {
            guard index + count <= bytes.count else { throw truncated }
            var result: UInt64 = 0
            for offset in 0..<count {
                result |= UInt64(bytes[index + offset]) << (8 * UInt64(offset))
            }
            index += count
            return result
        }

        private var truncated: PackageError {
            .unreadable("AndroidManifest.xml", "The proto ends inside a value.")
        }
    }
}
