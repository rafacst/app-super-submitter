import Foundation

public enum PriceDraftResult: Sendable, Equatable {
    case empty
    case invalid(String)
    case valid(Price)
}

public enum PriceDraft {
    public static func resolve(amount: String, currency: String,
                               territory: String = "") -> PriceDraftResult {
        let amount = amount.trimmingCharacters(in: .whitespacesAndNewlines)
        let currency = currency.trimmingCharacters(in: .whitespacesAndNewlines)
        let territory = territory.trimmingCharacters(in: .whitespacesAndNewlines)
        if amount.isEmpty { return .empty }
        guard let decimal = Decimal(string: amount) else {
            return .invalid("The price must be a valid decimal amount.")
        }
        guard !currency.isEmpty else {
            return .invalid("Enter a currency code to save the price.")
        }
        return .valid(Price(amount: decimal, currency: currency.uppercased(),
                            territory: territory.isEmpty ? nil : territory.uppercased()))
    }
}
