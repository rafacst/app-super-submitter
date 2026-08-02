import Foundation

/// Spec section 7.4. Google offers a real transaction, and the app uses it:
/// one edit wraps the whole Google side, and the run deletes it on any
/// failure before the commit.
extension Runner {

    func googleOpenEdit() async throws {
        let created = JSON(data: try await api.google("POST", "\(googleBase)/edits",
                                                      body: [:]).data)
        guard let id = created["id"].string else { throw RunError.missingEdit }
        googleEditID = id
        googleCommitted = false
    }

    private func editPath(_ suffix: String = "") throws -> String {
        guard let editID = googleEditID else { throw RunError.missingEdit }
        return "\(googleBase)/edits/\(editID)\(suffix)"
    }

    func googleListing(_ locale: String) async throws {
        var body: [String: Any] = ["language": locale]
        let title = manifest.listingText(locale: locale, field: .name)
        let short = Planner.googleShortDescription(manifest, locale)
        let full = manifest.listingText(locale: locale, field: .description)
        let video = manifest.listingText(locale: locale, field: .googleVideo)
        if !title.isEmpty { body["title"] = title }
        if !short.isEmpty { body["shortDescription"] = short }
        if !full.isEmpty { body["fullDescription"] = full }
        if !video.isEmpty { body["video"] = video }
        try await api.google("PUT", try editPath("/listings/\(locale)"), body: body)
    }

    func googleDetails() async throws {
        guard let review = manifest.review else { return }
        var body: [String: Any] = [:]
        if let email = review.contactEmail, !email.isEmpty { body["contactEmail"] = email }
        if let phone = review.contactPhone, !phone.isEmpty { body["contactPhone"] = phone }
        guard !body.isEmpty else { return }
        try await api.google("PATCH", try editPath("/details"), body: body)
    }

    /// Spec 7.5. Google uses one multipart upload and answers with the
    /// `sha256`, which the app compares to the local hash.
    func googleImages(locale: String, imageType: String, files: [MediaUpload],
                      index: Int) async throws {
        var uploaded = 0
        for file in files {
            try Task.checkCancellation()
            let data = try Data(contentsOf: file.url, options: .mappedIfSafe)
            let path = "/upload/androidpublisher/v3/applications/"
                + "\(StateReader.escape(manifest.apps.google?.packageName ?? ""))"
                + "/edits/\(googleEditID ?? "")/listings/\(locale)/\(imageType)"
            let response = JSON(data: try await api.googleUpload(
                path, contentType: Self.contentType(for: file.url), body: data).data)
            let remote = response["image"]["sha256"].string
            if let remote, remote != file.sha256 {
                throw RunError.uploadFailed(
                    "\(file.url.lastPathComponent): Google reported a different checksum.")
            }
            uploaded += 1
            report(index: index, fraction: Double(uploaded) / Double(files.count),
                   detail: "\(uploaded) of \(files.count) images")
        }
    }

    func googleBundleUpload(path: String, index: Int) async throws {
        guard let url = resolve(path) else { throw RunError.missingBuild }
        guard let editID = googleEditID else { throw RunError.missingEdit }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        report(index: index, fraction: 0.05, detail: "\(url.lastPathComponent)")
        let uploadPath = "/upload/androidpublisher/v3/applications/"
            + "\(StateReader.escape(manifest.apps.google?.packageName ?? ""))"
            + "/edits/\(editID)/bundles"
        let response = JSON(data: try await api.googleUpload(
            uploadPath, contentType: "application/octet-stream", body: data).data)
        googleVersionCode = response["versionCode"].int
        report(index: index, fraction: 1,
               detail: "version code \(googleVersionCode.map(String.init) ?? "unknown")")
    }

    /// The release `status` is always `draft` in an apply, whatever the
    /// manifest says. Section 7.9 reads the manifest value, and only there.
    func googleTrack() async throws {
        let track = manifest.release?.google?.track ?? "production"
        var codes = actual.google?.tracks[track]?.versionCodes ?? []
        if let code = googleVersionCode, !codes.contains(code) { codes.append(code) }
        guard !codes.isEmpty else { return }

        var release: [String: Any] = [
            "status": "draft",
            "versionCodes": codes.map(String.init),
        ]
        if let priority = manifest.release?.google?.inAppUpdatePriority {
            release["inAppUpdatePriority"] = priority
        }
        let notes = releaseNotes()
        if !notes.isEmpty { release["releaseNotes"] = notes }
        if let name = manifest.release?.versionName { release["name"] = name }

        try await api.google("PATCH", try editPath("/tracks/\(track)"),
                             body: ["track": track, "releases": [release]])
    }

    private func releaseNotes() -> [[String: Any]] {
        (manifest.listing?.locales.keys ?? [:].keys).sorted().compactMap { locale in
            let override = manifest.listingText(locale: locale, field: .googleWhatsNew)
            let text = override.isEmpty
                ? manifest.listingText(locale: locale, field: .whatsNew)
                : override
            guard !text.isEmpty else { return nil }
            return ["language": locale, "text": text]
        }
    }

    /// Spec 7.7. Google offers batch endpoints, and one call replaces twenty.
    func googleProducts() async throws {
        let packageName = StateReader.escape(manifest.apps.google?.packageName ?? "")
        let base = "/androidpublisher/v3/applications/\(packageName)"

        let purchases = manifest.purchases ?? []
        if !purchases.isEmpty {
            let requests = purchases.map { purchase -> [String: Any] in
                var product: [String: Any] = [
                    "packageName": manifest.apps.google?.packageName ?? "",
                    "productId": purchase.id,
                ]
                if let price = purchase.price {
                    product["regionsVersion"] = ["version": "2022/02"]
                    product["listings"] = [[
                        "languageCode": manifest.listing?.defaultLocale ?? "en-US",
                        "title": purchase.name ?? purchase.id,
                    ]]
                    product["purchaseOptions"] = [[
                        "purchaseOptionId": purchase.id,
                        "buyOption": [:],
                        "regionalPricingAndAvailabilityConfigs": [[
                            "regionCode": price.territory ?? "US",
                            "price": Self.money(price),
                            "availability": "AVAILABLE",
                        ]],
                    ]]
                }
                return ["updateOneTimeProductRequest": ["oneTimeProduct": product,
                                                        "allowMissing": true]]
            }
            try await api.google("POST", "\(base)/oneTimeProducts:batchUpdate",
                                 body: ["requests": requests])
        }

        for group in manifest.subscriptions ?? [] {
            let requests = group.plans.map { plan -> [String: Any] in
                var subscription: [String: Any] = [
                    "packageName": manifest.apps.google?.packageName ?? "",
                    "productId": plan.id,
                ]
                subscription["listings"] = [[
                    "languageCode": manifest.listing?.defaultLocale ?? "en-US",
                    "title": group.groupName ?? group.groupId,
                ]]
                var basePlan: [String: Any] = [
                    "basePlanId": plan.basePlanId ?? "default",
                    "autoRenewingBasePlanType": ["billingPeriodDuration": plan.duration],
                ]
                if let price = plan.price {
                    basePlan["regionalConfigs"] = [[
                        "regionCode": price.territory ?? "US",
                        "price": Self.money(price),
                    ]]
                }
                subscription["basePlans"] = [basePlan]
                return ["updateSubscriptionRequest": ["subscription": subscription,
                                                      "allowMissing": true]]
            }
            guard !requests.isEmpty else { continue }
            try await api.google("POST", "\(base)/subscriptions:batchUpdate",
                                 body: ["requests": requests])
        }
    }

    func googleValidate() async throws {
        try await api.google("POST", try editPath(":validate"), body: [:])
    }

    /// The commit is **not** a submission. Two things keep the release out of
    /// review, and the app always sends both: `changesNotSentForReview=true`
    /// holds the listing, and `status: draft` holds the bundle.
    func googleCommit() async throws {
        try await api.google("POST", try editPath(":commit"), body: [:],
                             query: [URLQueryItem(name: "changesNotSentForReview",
                                                  value: "true")])
        googleCommitted = true
    }

    private static func contentType(for url: URL) -> String {
        url.pathExtension.lowercased() == "png" ? "image/png" : "image/jpeg"
    }

    static func money(_ price: Price) -> [String: Any] {
        // Google takes units and nanos, never a float. A float would round a
        // real price on a real store.
        let total = NSDecimalNumber(decimal: price.amount * 1_000_000_000).int64Value
        return [
            "currencyCode": price.currency,
            "units": String(total / 1_000_000_000),
            "nanos": Int(total % 1_000_000_000),
        ]
    }
}
