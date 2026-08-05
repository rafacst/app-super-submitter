import Foundation

/// The redeemable codes of an App Store offer code, and the switch that
/// stops one.
///
/// Apple splits this in two. `subscriptionOfferCodes` and
/// `inAppPurchaseOfferCodes` are the *offer*: the discount, the duration, and
/// who qualifies. Neither one is redeemable. The codes a customer types live
/// on two more resources per family, and the app created none of them before,
/// so every offer code it wrote reached nobody.
///
/// The two families take the same four calls under different names, so one
/// writer serves both.
extension Runner {

    /// Which product the offer code hangs from.
    enum OfferCodeFamily {
        case subscription
        case purchase

        /// The offer code resource itself.
        var offerType: String {
            switch self {
            case .subscription: "subscriptionOfferCodes"
            case .purchase: "inAppPurchaseOfferCodes"
            }
        }

        var customType: String {
            switch self {
            case .subscription: "subscriptionOfferCodeCustomCodes"
            case .purchase: "inAppPurchaseOfferCodeCustomCodes"
            }
        }

        var oneTimeType: String {
            switch self {
            case .subscription: "subscriptionOfferCodeOneTimeUseCodes"
            case .purchase: "inAppPurchaseOfferCodeOneTimeUseCodes"
            }
        }
    }

    /// The codes of one offer, and its active switch.
    ///
    /// Every call reads the store first. A custom code Apple already holds is
    /// skipped, and a one-time use batch is created once and never again: a
    /// second create would mint a second batch on every run, and a re-run has
    /// to be free.
    func appleOfferCodeValues(_ offer: Manifest.Offer, offerCodeID: String,
                              family: OfferCodeFamily) async throws {
        if let codes = offer.codes {
            try await appleCustomCodes(codes, offerCodeID: offerCodeID, family: family)
            try await appleOneTimeUseCodes(codes, offerCodeID: offerCodeID, family: family)
        }
        try await appleOfferCodeState(offer, offerCodeID: offerCodeID, family: family)
    }

    private func appleCustomCodes(_ codes: Manifest.Offer.Codes, offerCodeID: String,
                                  family: OfferCodeFamily) async throws {
        guard let custom = codes.custom, !custom.isEmpty else { return }
        let existing = JSON(data: try await api.apple(
            "GET", "/v1/\(family.offerType)/\(offerCodeID)/customCodes?limit=200").data)
        let held = Set(existing["data"].array
            .compactMap { $0["attributes"]["customCode"].string })

        for (code, count) in custom.sorted(by: { $0.key < $1.key }) {
            try Task.checkCancellation()
            guard !held.contains(code) else { continue }
            var attributes: [String: Any] = [
                "customCode": code,
                "numberOfCodes": max(count, 1),
            ]
            put(&attributes, "expirationDate", codes.expiresOn ?? "")
            try await api.apple("POST", "/v1/\(family.customType)", body: [
                "data": [
                    "type": family.customType,
                    "attributes": attributes,
                    "relationships": ["offerCode": [
                        "data": ["type": family.offerType, "id": offerCodeID]]],
                ],
            ])
        }
    }

    /// Apple mints the batch and the app never sees the codes. The developer
    /// downloads them from App Store Connect, so nothing here logs one.
    private func appleOneTimeUseCodes(_ codes: Manifest.Offer.Codes, offerCodeID: String,
                                      family: OfferCodeFamily) async throws {
        guard let count = codes.oneTimeUse, count > 0 else { return }
        // Apple takes the expiry as required here, and a batch without one is
        // a 400 that reads like a server fault. The validator says so first.
        guard let expiresOn = codes.expiresOn, !expiresOn.isEmpty else { return }

        let existing = JSON(data: try await api.apple(
            "GET", "/v1/\(family.offerType)/\(offerCodeID)/oneTimeUseCodes?limit=200").data)
        guard existing["data"].array.isEmpty else { return }

        try await api.apple("POST", "/v1/\(family.oneTimeType)", body: [
            "data": [
                "type": family.oneTimeType,
                "attributes": [
                    "numberOfCodes": count,
                    "expirationDate": expiresOn,
                ],
                "relationships": ["offerCode": [
                    "data": ["type": family.offerType, "id": offerCodeID]]],
            ],
        ])
    }

    /// Deactivates an offer code, or leaves it alone.
    ///
    /// A missing key means "do not manage", the same as everywhere else. A
    /// deactivated offer stops a new redemption and keeps every subscription
    /// that already used one, so nothing here reaches a paying customer.
    private func appleOfferCodeState(_ offer: Manifest.Offer, offerCodeID: String,
                                     family: OfferCodeFamily) async throws {
        guard let active = offer.active else { return }
        try await api.apple("PATCH", "/v1/\(family.offerType)/\(offerCodeID)", body: [
            "data": [
                "type": family.offerType,
                "id": offerCodeID,
                "attributes": ["active": active],
            ],
        ])
    }
}
