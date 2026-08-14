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

    /// One localized store listing.
    ///
    /// A locale Google already holds is patched, and a new one is written
    /// whole. The difference matters, because this body has never carried
    /// every field: it omits what the manifest does not manage, and a PUT
    /// replaces the listing, so an unmanaged promo video that the developer
    /// set in the Play Console was silently deleted by an apply that only
    /// meant to write a description. No plan row could show that, because the
    /// planner skips an unmanaged field too.
    ///
    /// The three manifest states now reach Google intact: a value writes the
    /// field, a null clears it, and an absent key leaves the Play Console
    /// alone.
    func googleListing(_ locale: String) async throws {
        let entry = manifest.listing?.locales[locale]
        var body: [String: Any] = ["language": locale]
        let title = manifest.listingText(locale: locale, field: .name)
        if !title.isEmpty { body["title"] = title }
        // The short description falls back to the Apple subtitle, which is the
        // same rule the plan compares with.
        if let short = Self.listingField(entry?.google?.shortDescription)
            ?? Self.listingField(entry?.subtitle) {
            body["shortDescription"] = short
        }
        if let full = Self.listingField(entry?.description) {
            body["fullDescription"] = full
        }
        if let video = Self.listingField(entry?.google?.video) {
            body["video"] = video
        }
        let method = actual.google?.listings[locale] == nil ? "PUT" : "PATCH"
        try await api.google(method, try editPath("/listings/\(locale)"), body: body)
    }

    /// What one listing field sends, or nil when the manifest leaves it alone.
    ///
    /// `// ponytail: nil means "omit", and the empty string means "clear".
    /// // Two different absences, because the manifest has two.`
    static func listingField(_ managed: Managed<String>?) -> String? {
        switch managed {
        case .value(let text): text.isEmpty ? nil : text
        case .clear: ""
        case .unmanaged, nil: nil
        }
    }

    func googleDetails() async throws {
        var body: [String: Any] = [:]
        if let email = manifest.review?.contactEmail, !email.isEmpty {
            body["contactEmail"] = email
        }
        if let phone = manifest.review?.contactPhone, !phone.isEmpty {
            body["contactPhone"] = phone
        }
        if let locale = manifest.listing?.defaultLocale {
            let website = manifest.listingText(locale: locale, field: .supportURL)
            if !website.isEmpty { body["contactWebsite"] = website }
        }
        guard !body.isEmpty else { return }
        try await api.google("PATCH", try editPath("/details"), body: body)
    }

    /// The Data safety declaration, from a CSV that Play Console exported.
    ///
    /// This used to build a CSV out of four `question_id` values that the app
    /// made up. Google owns those ids and publishes them in the export, so a
    /// body built from invented ones could only be refused. Nothing is sent
    /// without the real file now, and the validator asks for it.
    func googleDataSafety() async throws {
        guard let path = manifest.review?.dataSafetyCSV, !path.isEmpty else { return }
        guard let url = resolve(path) else {
            throw RunError.uploadFailed("The Data safety CSV \(path) could not be read.")
        }
        let safetyLabels = try String(contentsOf: url, encoding: .utf8)
        try await api.google("POST", "\(googleBase)/dataSafety",
                             body: ["safetyLabels": safetyLabels])
    }

    func googleDeleteListing(_ locale: String) async throws {
        try await api.google("DELETE", try editPath("/listings/\(locale)"))
    }

    /// Spec 7.5. Google uses one multipart upload and answers with the
    /// `sha256`, which the app compares to the local hash.
    func googleImages(locale: String, imageType: String, files: [MediaUpload],
                      index: Int) async throws {
        guard let editID = googleEditID else { throw RunError.missingEdit }
        try await api.google("DELETE", try editPath("/listings/\(locale)/\(imageType)"))
        var uploaded = 0
        for file in files {
            try Task.checkCancellation()
            let data = try Data(contentsOf: file.url, options: .mappedIfSafe)
            let path = "/upload/androidpublisher/v3/applications/"
                + "\(StateReader.escape(manifest.apps.google?.packageName ?? ""))"
                + "/edits/\(editID)/listings/\(locale)/\(imageType)"
            let response = JSON(data: try await api.googleUpload(
                path, contentType: Self.contentType(for: file.url), body: data).data)
            guard let remote = response["image"]["sha256"].string,
                  remote == file.sha256 else {
                throw RunError.uploadFailed(
                    "\(file.url.lastPathComponent): Google did not confirm the expected checksum.")
            }
            uploaded += 1
            report(index: index, fraction: Double(uploaded) / Double(files.count),
                   detail: "\(uploaded) of \(files.count) images")
        }
    }

    func googleBundleUpload(path: String, index: Int) async throws {
        guard let url = resolve(path) else { throw RunError.missingBuild }
        guard let editID = googleEditID else { throw RunError.missingEdit }
        report(index: index, fraction: 0.05, detail: "\(url.lastPathComponent)")
        let uploadPath = "/upload/androidpublisher/v3/applications/"
            + "\(StateReader.escape(manifest.apps.google?.packageName ?? ""))"
            + "/edits/\(editID)/bundles"
        let response = JSON(data: try await api.googleUpload(
            uploadPath, contentType: "application/octet-stream", file: url).data)
        guard let versionCode = response["versionCode"].int else {
            throw RunError.uploadFailed("Google accepted the bundle but returned no version code.")
        }
        googleVersionCode = versionCode
        report(index: index, fraction: 1,
               detail: "version code \(googleVersionCode.map(String.init) ?? "unknown")")
    }

    /// A custom closed-testing track. Google creates `internal`, `alpha`,
    /// `beta`, and `production` by itself, and it creates nothing else.
    func googleCreateTrack(_ track: String) async throws {
        try await api.google("POST", try editPath("/tracks"),
                             body: ["track": track, "releases": []])
    }

    /// A plain APK, next to or instead of the App Bundle.
    func googleApkUpload(path: String, index: Int) async throws {
        guard let url = resolve(path) else { throw RunError.missingBuild }
        guard let editID = googleEditID else { throw RunError.missingEdit }
        report(index: index, fraction: 0.05, detail: "\(url.lastPathComponent)")
        let uploadPath = "/upload/androidpublisher/v3/applications/"
            + "\(StateReader.escape(manifest.apps.google?.packageName ?? ""))"
            + "/edits/\(editID)/apks"
        let response = JSON(data: try await api.googleUpload(
            uploadPath, contentType: "application/vnd.android.package-archive",
            file: url).data)
        guard let versionCode = response["versionCode"].int else {
            throw RunError.uploadFailed("Google accepted the APK and returned no version code.")
        }
        googleApkVersionCode = versionCode
        report(index: index, fraction: 0.9, detail: "version code \(versionCode)")

        // The direct confirmation. The bundle flow reads the edit back in
        // `UploadService.checkGoogle`; the APK had only the upload response,
        // so a version code that never reached the edit went unnoticed until
        // the commit refused it.
        let uploaded = try await googleApks().first { $0.versionCode == versionCode }
        guard let uploaded else {
            throw RunError.uploadFailed(
                "Google answered version code \(versionCode) for \(url.lastPathComponent) and then listed no such APK in the edit.")
        }
        report(index: index, fraction: 1,
               detail: uploaded.sha1.map { "version code \(versionCode)  ·  \($0)" }
                   ?? "version code \(versionCode)")
    }

    /// One APK inside the open edit. Google lists the ones it already holds
    /// for the app as well as the ones this edit uploaded.
    struct EditAPK: Equatable {
        var versionCode: Int
        var sha1: String?
    }

    func googleApks() async throws -> [EditAPK] {
        let payload = JSON(data: try await api.google("GET", try editPath("/apks")).data)
        return payload["apks"].array.compactMap { item in
            guard let code = item["versionCode"].int else { return nil }
            return EditAPK(versionCode: code, sha1: item["binary"]["sha1"].string)
        }
    }

    /// An APK that the developer hosts. Google stores the metadata and never
    /// the bytes, so this call sends no file.
    func googleExternalApk() async throws {
        guard let apk = manifest.release?.google?.externalApk else { return }
        var payload: [String: Any] = [
            "packageName": manifest.apps.google?.packageName ?? "",
            "applicationLabel": apk.applicationLabel,
            "versionCode": apk.versionCode,
            "versionName": apk.versionName,
            "minimumSdk": apk.minimumSdk,
            "certificateBase64s": apk.certificateBase64s,
            "externallyHostedUrl": apk.url,
        ]
        if let maximum = apk.maximumSdk { payload["maximumSdk"] = maximum }
        if let codes = apk.nativeCodes, !codes.isEmpty { payload["nativeCodes"] = codes }
        if let features = apk.usesFeatures, !features.isEmpty {
            payload["usesFeatures"] = features
        }
        if let permissions = apk.usesPermissions, !permissions.isEmpty {
            payload["usesPermissions"] = permissions.map { ["name": $0] }
        }
        if let icon = apk.iconBase64, !icon.isEmpty { payload["iconBase64"] = icon }

        try await api.google("POST", try editPath("/apks/externallyHosted"),
                             body: ["externallyHostedApk": payload])
    }

    /// The mapping file or the native symbols. Both attach to a version code,
    /// so both run after an artifact upload.
    func googleDeobfuscation(kind: String, path: String, index: Int) async throws {
        guard let url = resolve(path) else { throw RunError.missingBuild }
        guard let editID = googleEditID else { throw RunError.missingEdit }
        guard let versionCode = googleApkVersionCode ?? googleVersionCode
            ?? actual.google?.highestVersionCode else {
            throw RunError.uploadFailed(
                "\(url.lastPathComponent) needs an uploaded artifact to attach to.")
        }
        report(index: index, fraction: 0.05, detail: url.lastPathComponent)
        let uploadPath = "/upload/androidpublisher/v3/applications/"
            + "\(StateReader.escape(manifest.apps.google?.packageName ?? ""))"
            + "/edits/\(editID)/apks/\(versionCode)/deobfuscationFiles/\(kind)"
        try await api.googleUpload(uploadPath, contentType: "application/octet-stream", file: url)
        report(index: index, fraction: 1, detail: "attached to version code \(versionCode)")
    }

    /// An expansion file. Google accepts one for an APK and never for a
    /// bundle, so this reads the APK version code and no other.
    ///
    /// The file Google already holds costs no upload, the same rule the
    /// product images follow. An expansion file runs to two gigabytes, so a
    /// re-run that skips it is the difference between a minute and an hour.
    func googleExpansionFile(kind: String, path: String, index: Int) async throws {
        guard let url = resolve(path) else { throw RunError.missingBuild }
        guard let editID = googleEditID else { throw RunError.missingEdit }
        guard let versionCode = try await googleExpansionTarget() else {
            throw RunError.uploadFailed(
                "An expansion file needs an APK. The manifest names no androidApk build, and the app holds no APK to attach one to.")
        }
        report(index: index, fraction: 0.05, detail: url.lastPathComponent)

        let local = Planner.fileSize(url)
        if local > 0,
           try await googleExpansionFileState(versionCode: versionCode, kind: kind) == local {
            report(index: index, fraction: 1,
                   detail: "already attached to version code \(versionCode)")
            return
        }

        let uploadPath = "/upload/androidpublisher/v3/applications/"
            + "\(StateReader.escape(manifest.apps.google?.packageName ?? ""))"
            + "/edits/\(editID)/apks/\(versionCode)/expansionFiles/\(kind)"
        try await api.googleUpload(uploadPath, contentType: "application/octet-stream", file: url)
        report(index: index, fraction: 1, detail: "attached to version code \(versionCode)")
    }

    /// The APK the expansion file attaches to: the one this run uploaded, or
    /// the newest one the app already holds.
    ///
    /// The second half is what a re-run needs. A run that uploads no APK used
    /// to fail this step outright, even though the app had an APK sitting
    /// right there to attach to.
    func googleExpansionTarget() async throws -> Int? {
        if let versionCode = googleApkVersionCode { return versionCode }
        return try await googleApks().map(\.versionCode).max()
    }

    /// The size of what Google has attached to one APK, or nil when it has
    /// nothing to compare.
    ///
    /// Google answers a size here and no checksum, so the size is the whole
    /// comparison. It answers no size at all for an expansion file that only
    /// points at another version's, and nil then means "upload", which is the
    /// safe way round.
    ///
    /// `// ponytail: the byte count decides. Two different files of the same
    /// // exact length on one version code would read as equal. Compare a
    /// // local hash instead the day Google answers one.`
    func googleExpansionFileState(versionCode: Int, kind: String) async throws -> Int64? {
        let path = try editPath("/apks/\(versionCode)/expansionFiles/\(kind)")
        let payload: JSON
        do {
            payload = JSON(data: try await api.google("GET", path).data)
        } catch ConnectionError.http(let status, _) where status == 404 {
            // No expansion file of this kind on this APK. A state, not a
            // failure, and the caller uploads one.
            return nil
        }
        return payload["fileSize"].int.map(Int64.init)
    }

    /// The release `status` is always `draft` in an apply, whatever the
    /// manifest says. Section 7.9 reads the manifest value, and only there.
    func googleTrack(_ track: String) async throws {
        var codes = actual.google?.tracks[track]?.versionCodes ?? []
        for code in [googleVersionCode, googleApkVersionCode].compactMap({ $0 })
        where !codes.contains(code) {
            codes.append(code)
        }
        guard !codes.isEmpty else { return }

        var release: [String: Any] = [
            "status": "draft",
            "versionCodes": codes.map(String.init),
        ]
        if let priority = manifest.release?.google?.inAppUpdatePriority {
            release["inAppUpdatePriority"] = priority
        }
        if let targeting = manifest.googleCountryTargeting {
            release["countryTargeting"] = targeting
        }
        let notes = releaseNotes()
        if !notes.isEmpty { release["releaseNotes"] = notes }
        if let name = manifest.versionName(for: .google) { release["name"] = name }

        try await api.google("PATCH", try editPath("/tracks/\(track)"),
                             body: ["track": track, "releases": [release]])
    }

    /// The Google Groups that may install one track.
    ///
    /// Google replaces the whole list, so the manifest names every group that
    /// the track keeps. An empty list in the manifest clears the track, and
    /// the planner only writes a track that the manifest actually names.
    func googleTesters(_ track: String) async throws {
        let groups = (manifest.release?.google?.testers?[track] ?? [])
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
        try await api.google("PUT", try editPath("/testers/\(StateReader.escape(track))"),
                             body: ["googleGroups": groups])
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
            var requests: [[String: Any]] = []
            for purchase in purchases {
                var product: [String: Any] = [
                    "packageName": manifest.apps.google?.packageName ?? "",
                    "productId": purchase.id,
                ]
                if let tax = Self.taxSettings(purchase.tax) {
                    product["taxAndComplianceSettings"] = tax
                }
                let locales = purchase.locales ?? [:]
                if locales.isEmpty {
                    product["listings"] = [[
                        "languageCode": manifest.listing?.defaultLocale ?? "en-US",
                        "title": purchase.name ?? purchase.id]]
                } else {
                    product["listings"] = locales.sorted(by: { $0.key < $1.key }).map {
                        ["languageCode": $0.key,
                         "title": $0.value.name ?? purchase.name ?? purchase.id,
                         "description": $0.value.description ?? ""]
                    }
                }
                if let price = purchase.price {
                    let pricing = try await googleRegionalPricing(price)
                    product["regionsVersion"] = pricing.version
                    product["purchaseOptions"] = [[
                        "purchaseOptionId": purchase.id,
                        "buyOption": [:],
                        "regionalPricingAndAvailabilityConfigs": pricing.configs,
                    ]]
                }
                requests.append(["updateOneTimeProductRequest": ["oneTimeProduct": product,
                                                                  "allowMissing": true]])
            }
            try await api.google("POST", "\(base)/oneTimeProducts:batchUpdate",
                                 body: ["requests": requests])
        }

        for group in manifest.subscriptions ?? [] {
            var requests: [[String: Any]] = []
            for plan in group.plans {
                var subscription: [String: Any] = [
                    "packageName": manifest.apps.google?.packageName ?? "",
                    "productId": plan.id,
                ]
                if let tax = Self.taxSettings(plan.tax) {
                    subscription["taxAndComplianceSettings"] = tax
                }
                let locales = plan.locales ?? group.locales ?? [:]
                subscription["listings"] = locales.isEmpty ? [[
                    "languageCode": manifest.listing?.defaultLocale ?? "en-US",
                    "title": group.groupName ?? group.groupId,
                ]] : locales.sorted(by: { $0.key < $1.key }).map {
                    ["languageCode": $0.key,
                     "title": $0.value.name ?? group.groupName ?? group.groupId,
                     "description": $0.value.description ?? ""]
                }
                var basePlan: [String: Any] = [
                    "basePlanId": plan.basePlanId ?? "default",
                    "autoRenewingBasePlanType": ["billingPeriodDuration": plan.duration],
                ]
                if let price = plan.price {
                    let pricing = try await googleRegionalPricing(price)
                    subscription["regionsVersion"] = pricing.version
                    basePlan["regionalConfigs"] = pricing.configs.map { config in
                        var value = config
                        value.removeValue(forKey: "availability")
                        return value
                    }
                }
                subscription["basePlans"] = [basePlan]
                requests.append(["updateSubscriptionRequest": ["subscription": subscription,
                                                                "allowMissing": true]])
            }
            guard !requests.isEmpty else { continue }
            try await api.google("POST", "\(base)/subscriptions:batchUpdate",
                                 body: ["requests": requests])
        }
    }

    private func googleRegionalPricing(_ price: Price) async throws
        -> (configs: [[String: Any]], version: [String: Any]) {
        guard manifest.pricing?.autoConvertOtherTerritories != false else {
            return ([["regionCode": Self.googleRegion(price.territory ?? "US"),
                      "price": Self.money(price),
                      "availability": "AVAILABLE"]], ["version": "2022/02"])
        }
        let response = try await api.google(
            "POST", "\(googleBase)/pricing:convertRegionPrices",
            body: ["price": Self.money(price)])
        let object = (try JSONSerialization.jsonObject(with: response.data)) as? [String: Any]
            ?? [:]
        let converted = object["convertedRegionPrices"] as? [String: Any] ?? [:]
        let configs: [[String: Any]] = converted.keys.sorted().compactMap { region in
            guard let value = converted[region] as? [String: Any],
                  let money = value["price"] as? [String: Any] else { return nil }
            return ["regionCode": region, "price": money, "availability": "AVAILABLE"]
        }
        let version = object["regionVersion"] as? [String: Any] ?? ["version": "2022/02"]
        return (configs.isEmpty
            ? [["regionCode": Self.googleRegion(price.territory ?? "US"),
                "price": Self.money(price),
                "availability": "AVAILABLE"]]
            : configs, version)
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

    /// The Google tax block, or nil when the manifest names nothing. An
    /// absent block leaves the Play Console value untouched.
    static func taxSettings(_ tax: Manifest.Tax?) -> [String: Any]? {
        guard let tax else { return nil }
        var result: [String: Any] = [:]
        if let category = tax.category, !category.isEmpty {
            result["taxRateInfoByRegionCode"] = [:]
            result["googlePlayTaxCategory"] = category
        }
        if let withdrawal = tax.withdrawalRight, !withdrawal.isEmpty {
            result["withdrawalRightType"] = withdrawal
        }
        if let eea = tax.eeaWithdrawalRight {
            result["isTokenizedDigitalAsset"] = false
            result["eeaWithdrawalRightType"] = eea
                ? "WITHDRAWAL_RIGHT_DIGITAL_CONTENT"
                : "WITHDRAWAL_RIGHT_SERVICE"
        }
        return result.isEmpty ? nil : result
    }

    static func money(_ price: Price) -> [String: Any] {
        // Google takes units and nanos, never a float. A float would round a
        // real price on a real store.
        let value = GoogleCatalogClient.nanoUnits(price.amount)
        return [
            "currencyCode": price.currency,
            "units": String(value.units),
            "nanos": value.nanos,
        ]
    }

    /// One territory code, the way Google names it.
    ///
    /// The manifest holds one territory field and both stores read it. The
    /// App Store spells a territory in ISO 3166-1 alpha-3 and Google wants
    /// alpha-2, so `USA` has to leave here as `US`. ICU already normalises a
    /// real alpha-3 to its alpha-2, which is the same trick the territory
    /// chooser uses, so no table of 250 rows is typed out here.
    ///
    /// A code ICU cannot place goes out as it came in. Google then names it
    /// in the error, which beats this file guessing at a country.
    static func googleRegion(_ code: String) -> String {
        guard code.count == 3,
              let two = Locale(identifier: "und_\(code)").region?.identifier,
              two.count == 2 else { return code.uppercased() }
        return two
    }

    /// The regions one offer sells in. An empty list means the United States,
    /// which is the fallback every other Google price in this file uses.
    static func googleRegions(_ regions: [String]?) -> [String] {
        let named = (regions ?? []).filter { !$0.isEmpty }.map(googleRegion)
        return named.isEmpty ? ["US"] : named
    }
}
