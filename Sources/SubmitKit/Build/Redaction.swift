import Foundation

/// Removes secrets before a line reaches a log, the UI, or a diagnostic.
///
/// Redaction happens at the data source, not at the presentation layer, so a
/// value that never reaches a buffer cannot leak through a path nobody thought
/// about. upload-spec sections 3.7 and 12.2.
public struct Redactor: Sendable {
    public static let mask = "«redacted»"

    /// Literal values that must never appear. The app knows these because it
    /// holds them: a `.p8` body, a service-account JSON, an API key.
    private let literals: [String]

    public init(literals: [String] = []) {
        // A two-character fragment of a key is not the leak, and redacting it
        // would blank half the log. Only a substantial literal is masked.
        self.literals = literals
            .flatMap { $0.components(separatedBy: .newlines) }
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { $0.count >= 8 }
            .sorted { $0.count > $1.count }
    }

    public func redact(_ line: String) -> String {
        var result = line
        for literal in literals {
            result = result.replacingOccurrences(of: literal, with: Redactor.mask)
        }
        return Redactor.maskAssignments(in: result)
    }

    /// A name that says "secret", a separator, then the value.
    /// `API_TOKEN=abc123def` becomes `API_TOKEN=«redacted»`.
    private static let assignment = try? NSRegularExpression(
        pattern: "(?i)\\b((?:[\\w.-]*)(?:pass(?:word|wd)?|secret|token|api[_-]?key"
            + "|private[_-]?key|credential|keystore|signing[_-]?key|authorization"
            // A scheme word belongs to the name, never to the value.
            + "|bearer)(?:[\\w.-]*)\\s*[=:]\\s*(?:(?:Bearer|Basic|Token)\\s+)?[\"']?)"
            + "([^\\s\"']{4,})")

    static func maskAssignments(in line: String) -> String {
        guard let assignment else { return line }
        let range = NSRange(line.startIndex..., in: line)
        return assignment.stringByReplacingMatches(in: line, range: range,
                                                   withTemplate: "$1\(mask)")
    }

    /// True when a variable's name says it holds a secret.
    public static func isSecretName(_ name: String) -> Bool {
        maskAssignments(in: "\(name)=0000") != "\(name)=0000"
    }

    /// The environment names that a run passed, for a diagnostic. The values
    /// never travel with them. upload-spec section 6.2.
    public static func names(of environment: [String: String]) -> [String] {
        environment.keys.sorted()
    }
}
