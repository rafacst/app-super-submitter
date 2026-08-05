import Foundation

/// The promotional image of a subscription or a one-time purchase.
///
/// This is the square picture the App Store shows beside the product, and Apple
/// asks for it before it will promote a purchase on the store page. Apple keeps
/// one per product, on two resources that take the same calls under different
/// names, so one writer serves both. Google offers no equivalent.
extension Runner {

    /// Which product the image hangs from.
    enum ProductImageFamily {
        case subscription
        case purchase

        /// The image resource itself.
        var imageType: String {
            switch self {
            case .subscription: "subscriptionImages"
            case .purchase: "inAppPurchaseImages"
            }
        }

        /// The relationship the create sends, and the type of its parent.
        var parent: (name: String, type: String) {
            switch self {
            case .subscription: ("subscription", "subscriptions")
            case .purchase: ("inAppPurchaseV2", "inAppPurchases")
            }
        }

        /// Where the images of one product are read. The purchase half reads
        /// through v2, exactly as its offer codes do.
        func listPath(productID: String) -> String {
            switch self {
            case .subscription: "/v1/subscriptions/\(productID)/images"
            case .purchase: "/v2/inAppPurchases/\(productID)/images"
            }
        }
    }

    /// Writes the promotional image, or leaves the product alone.
    ///
    /// A missing key means "do not manage", the same as everywhere else.
    ///
    /// The image Apple already holds costs no upload: the checksum decides,
    /// which is how the screenshots decide it too, so a re-run is free. Apple
    /// keeps one image per product, so a different picture replaces the old
    /// one. That picture is the developer's own and the manifest is the
    /// desired state, so the replacement is what the key asked for.
    func appleProductImage(_ path: String?, productID: String,
                           family: ProductImageFamily) async throws {
        guard let path, let url = resolve(path) else { return }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let checksum = Checksums.md5(data)

        let existing = JSON(data: try await api.apple(
            "GET", family.listPath(productID: productID) + "?limit=200").data)
        var stale: [String] = []
        for item in existing["data"].array {
            guard let id = item["id"].string else { continue }
            if item["attributes"]["sourceFileChecksum"].string == checksum { return }
            stale.append(id)
        }
        for id in stale {
            try await api.apple("DELETE", "/v1/\(family.imageType)/\(id)")
        }

        let reservation = JSON(data: try await api.apple(
            "POST", "/v1/\(family.imageType)", body: [
                "data": [
                    "type": family.imageType,
                    "attributes": ["fileName": url.lastPathComponent,
                                   "fileSize": data.count],
                    "relationships": [family.parent.name: [
                        "data": ["type": family.parent.type, "id": productID]]],
                ],
            ]).data)
        guard let id = reservation["data"]["id"].string else { return }
        try await executeUploadOperations(
            reservation["data"]["attributes"]["uploadOperations"], data: data)
        try await api.apple("PATCH", "/v1/\(family.imageType)/\(id)", body: [
            "data": ["type": family.imageType, "id": id,
                     "attributes": ["uploaded": true, "sourceFileChecksum": checksum]],
        ])
    }
}
