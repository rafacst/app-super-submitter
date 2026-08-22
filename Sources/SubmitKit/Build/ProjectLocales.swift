import Foundation

/// The languages a project ships, and which of them it is written in first.
///
/// The new-app door reads a folder and fills `store.yaml` from it. It read the
/// identifier, the version and the name, and stopped: the manifest came out
/// with no listing language at all, so Details, Media and Preview store all
/// opened on "Add the first locale" — three tabs blocked on an answer the
/// project states plainly, in the same file the identifier came from.
///
/// Nothing here guesses. A project that names no development region and holds
/// no localisation returns nothing, and the developer answers as they did
/// before this existed.
public struct ProjectLocales: Sendable, Equatable {
    /// The language the listing is written in first, in store form: `en-US`,
    /// `pt-BR`, `ja`.
    public var defaultLocale: String?
    /// Every language the project ships, the default included, sorted.
    public var locales: [String] = []

    public init(defaultLocale: String? = nil, locales: [String] = []) {
        self.defaultLocale = defaultLocale
        self.locales = locales
    }

    public var isEmpty: Bool { defaultLocale == nil && locales.isEmpty }

    // MARK: - Apple

    /// Reads an Xcode container: the development region, and every region the
    /// project knows.
    ///
    /// `knownRegions` is the list Xcode maintains as `.lproj` folders are
    /// added, so it is the project's own answer and not a walk of the disk.
    /// Two of its entries are never languages — `Base` is the unlocalised
    /// interface and `en` may appear beside `Base` for the same reason.
    public static func apple(container: URL) -> ProjectLocales {
        guard let project = AppleProjectIdentity.projectFile(for: container),
              let text = try? String(contentsOf: project, encoding: .utf8)
        else { return ProjectLocales() }
        return parseApple(text)
    }

    static func parseApple(_ text: String) -> ProjectLocales {
        var result = ProjectLocales()
        let region = AppleProjectIdentity.pick(
            AppleProjectIdentity.values(of: "developmentRegion", in: text))
        result.defaultLocale = region.flatMap(storeLocale(for:))
        let known = knownRegions(in: text).compactMap(storeLocale(for:))
        result.locales = normalise(known, default: result.defaultLocale)
        return result
    }

    /// The `knownRegions = ( en, "pt-BR", Base, );` block of a `project.pbxproj`.
    ///
    /// It is the one list in the file that spans several lines, so it cannot go
    /// through `AppleProjectIdentity.values`, which reads `KEY = value;` and
    /// nothing else.
    static func knownRegions(in text: String) -> [String] {
        guard let start = text.range(of: "knownRegions = (") else { return [] }
        let rest = text[start.upperBound...]
        guard let end = rest.firstIndex(of: ")") else { return [] }
        return rest[rest.startIndex..<end]
            .split { $0 == "," || $0.isNewline }
            .map {
                $0.trimmingCharacters(in: .whitespaces)
                    .trimmingCharacters(in: CharacterSet(charactersIn: "\""))
            }
            .filter { !$0.isEmpty }
    }

    // MARK: - Android

    /// Reads a Gradle module: `res/xml/locales_config.xml` first, then the
    /// `res/values-xx` folders beside `res/values`.
    ///
    /// `locales_config.xml` is the file Android 13 reads for per-app languages,
    /// and it lists them in preference order, so its first entry is the
    /// default. A project without one says which languages it ships through
    /// the qualified resource folders, and `values` with no qualifier is the
    /// default: Android states no language for it, so the default locale stays
    /// nil unless `locales_config.xml` answered.
    public static func android(module: URL) -> ProjectLocales {
        let res = module.appendingPathComponent("src/main/res")
        var result = ProjectLocales()
        let config = res.appendingPathComponent("xml/locales_config.xml")
        if let text = try? String(contentsOf: config, encoding: .utf8) {
            let listed = parseLocalesConfig(text).compactMap(storeLocale(for:))
            result.defaultLocale = listed.first
            result.locales = normalise(listed, default: result.defaultLocale)
            if !result.locales.isEmpty { return result }
        }
        let folders = (try? FileManager.default.contentsOfDirectory(
            atPath: res.path))?.sorted() ?? []
        let qualified = folders
            .filter { $0.hasPrefix("values-") }
            .map { String($0.dropFirst("values-".count)) }
            .compactMap(storeLocale(for:))
        result.locales = normalise(qualified, default: nil)
        return result
    }

    /// `<locale android:name="pt-BR"/>`, in order.
    static func parseLocalesConfig(_ text: String) -> [String] {
        var found: [String] = []
        var rest = Substring(text)
        while let start = rest.range(of: "android:name=\"") {
            let after = rest[start.upperBound...]
            guard let end = after.firstIndex(of: "\"") else { break }
            let value = String(after[after.startIndex..<end])
            if !value.isEmpty { found.append(value) }
            rest = after[after.index(after: end)...]
        }
        return found
    }

    // MARK: - Shared

    /// One resource qualifier or region code as a store locale.
    ///
    /// Android writes `pt-rBR` and `b+sr+Latn`, Xcode writes `pt-BR` and `en`,
    /// and the stores take `pt-BR`. Anything that is not a language code is
    /// refused rather than passed on: `night`, `v21`, `sw600dp` and `Base` all
    /// arrive here from a folder listing or a `knownRegions` block.
    static func storeLocale(for raw: String) -> String? {
        var value = raw.trimmingCharacters(in: .whitespaces)
        guard !value.isEmpty, value != "Base" else { return nil }
        // `b+sr+Latn` is Android's BCP 47 form for a script the short form
        // cannot say.
        if value.hasPrefix("b+") {
            value = value.dropFirst(2).split(separator: "+").joined(separator: "-")
        }
        // `pt-rBR` is the resource form of `pt-BR`, and the `r` is a marker
        // and never part of the region.
        let parts = value.split(separator: "-").map(String.init)
        // Two or three lowercase letters, and nothing else. `v21` and
        // `sw600dp` both arrive here from a `res` folder listing.
        guard let language = parts.first, language.count == 2 || language.count == 3,
              language.allSatisfy(\.isLetter), language.lowercased() == language
        else { return nil }
        guard parts.count > 1 else { return language }
        var tail = parts[1]
        if tail.count == 3, tail.hasPrefix("r") { tail = String(tail.dropFirst()) }
        // A region is two letters, a script is four. Anything else is a
        // configuration qualifier that followed the language in a folder name.
        guard tail.count == 2 || tail.count == 4, tail.allSatisfy(\.isLetter) else {
            return language
        }
        return "\(language)-\(tail.count == 2 ? tail.uppercased() : tail.capitalized)"
    }

    /// Unique, sorted, and always holding the default.
    static func normalise(_ values: [String], default code: String?) -> [String] {
        var set = Set(values)
        if let code { set.insert(code) }
        return set.sorted()
    }
}
