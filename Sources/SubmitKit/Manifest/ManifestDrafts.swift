/// Empty catalog rows used by the form while the developer enters the real
/// store identifiers and commercial terms. No guessed identifier, currency,
/// price, duration, or provider key is ever written to `store.yaml`.
public enum ManifestDrafts {
    public static func purchase() -> Manifest.Purchase {
        Manifest.Purchase(id: "", kind: .nonConsumable)
    }

    public static func subscriptionGroup() -> Manifest.SubscriptionGroup {
        Manifest.SubscriptionGroup(groupId: "")
    }

    public static func subscriptionPlan() -> Manifest.SubscriptionGroup.Plan {
        Manifest.SubscriptionGroup.Plan(id: "", duration: "")
    }

    public static func entitlement() -> Manifest.Entitlement {
        Manifest.Entitlement(key: "")
    }

    public static func offering(isFirst: Bool) -> Manifest.Offering {
        Manifest.Offering(key: "", isCurrent: isFirst, products: [])
    }
}
