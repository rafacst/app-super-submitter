import Foundation

/// Unpacks the gzip that Apple sends for a sales or a finance report.
///
/// Both report endpoints answer `application/a-gzip` and nothing else, so a
/// reader that cannot unpack gzip cannot show a report at all.
///
/// Foundation unpacks a raw deflate stream and not a gzip container, so this
/// strips the header and the trailer and hands the middle to Foundation. That
/// is the whole of it: no zlib dependency, no third-party package.
enum Gzip {
    enum Failure: Error, Equatable {
        case notGzip
        case truncated
    }

    /// RFC 1952. The header is ten fixed bytes and up to four optional fields,
    /// and the trailer is a CRC and a length that Foundation does not want.
    static func unpack(_ data: Data) throws -> Data {
        let bytes = [UInt8](data)
        guard bytes.count > 18 else { throw Failure.truncated }
        guard bytes[0] == 0x1f, bytes[1] == 0x8b, bytes[2] == 0x08 else {
            throw Failure.notGzip
        }

        let flags = bytes[3]
        var index = 10

        // FEXTRA. Two bytes of length, then that many bytes.
        if flags & 0x04 != 0 {
            guard index + 1 < bytes.count else { throw Failure.truncated }
            let length = Int(bytes[index]) | Int(bytes[index + 1]) << 8
            index += 2 + length
        }
        // FNAME and FCOMMENT. Each runs to its own zero byte.
        for flag in [UInt8(0x08), UInt8(0x10)] where flags & flag != 0 {
            while index < bytes.count, bytes[index] != 0 { index += 1 }
            index += 1
        }
        // FHCRC. Two bytes.
        if flags & 0x02 != 0 { index += 2 }

        // The trailer is the last eight bytes and never part of the stream.
        let end = bytes.count - 8
        guard index < end else { throw Failure.truncated }

        let deflated = data.subdata(in: index ..< end)
        return try (deflated as NSData).decompressed(using: .zlib) as Data
    }

    /// The report as text. Apple writes a tab-separated sales report and a
    /// comma-separated finance report, and both are UTF-8.
    static func unpackText(_ data: Data) throws -> String {
        let unpacked = try unpack(data)
        return String(data: unpacked, encoding: .utf8)
            ?? String(decoding: unpacked, as: UTF8.self)
    }
}
