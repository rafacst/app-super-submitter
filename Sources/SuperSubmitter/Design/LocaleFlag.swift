import SwiftUI

/// The flag of a store language, and the name a person reads for it.
///
/// A language code on its own is a thing to decode: `pt-BR` and `pt-PT` differ
/// by two letters, and `zh-Hans` names no country at all. The flag is read
/// before the letters are, which is what a list of ten languages needs.
struct LocaleFlag: View {
    let code: String
    var size: CGFloat = 14

    var body: some View {
        Group {
            if let flag = Self.emoji(for: code) {
                Text(flag).font(.system(size: size))
            } else {
                // A language with no one country behind it: `es-419` is Latin
                // America. A globe says "a region" without naming a wrong one.
                Image(systemName: "globe")
                    .font(Theme.font(size: size * 0.85))
                    .foregroundStyle(Theme.text2)
            }
        }
        .frame(width: size + 4)
        .accessibilityHidden(true)
    }

    /// The flag of the country a code names, or of the country its language is
    /// most spoken in when it names none: `ja` is Japan and `zh-Hans` is China.
    /// Nil for a region that is not a country, such as `419`.
    static func emoji(for code: String) -> String? {
        guard let region = region(for: code) else { return nil }
        // A flag is the two letters of the country as regional indicator
        // symbols, which sit 0x1F1A5 above the capital letters.
        var flag = ""
        for letter in region.unicodeScalars {
            guard let symbol = Unicode.Scalar(letter.value + 0x1F1A5) else { return nil }
            flag.unicodeScalars.append(symbol)
        }
        return flag
    }

    static func region(for code: String) -> String? {
        let named = Locale(identifier: code).region?.identifier
        let likely = Locale(identifier: Locale.Language(identifier: code).maximalIdentifier)
            .region?.identifier
        guard let region = (named ?? likely)?.uppercased(), region.count == 2,
              region.unicodeScalars.allSatisfy({ (65...90).contains($0.value) }) else { return nil }
        return region
    }

    /// "Portuguese (Brazil)", in the language of the Mac. The code itself when
    /// the system has no name for it.
    static func name(for code: String) -> String {
        Locale.current.localizedString(forIdentifier: code) ?? code
    }
}
