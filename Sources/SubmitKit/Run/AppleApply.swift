import Foundation

/// Spec section 7.3. The order matters: the app performs the reversible
/// writes first, and every write here ends in a draft.
extension Runner {

    // MARK: - The version

    func appleEnsureVersion(_ versionString: String) async throws {
        if let existing = appleVersionID {
            try await api.apple("PATCH", "/v1/appStoreVersions/\(existing)", body: [
                "data": ["type": "appStoreVersions", "id": existing,
                         "attributes": ["versionString": versionString]],
            ])
            return
        }
        let created = JSON(data: try await api.apple("POST", "/v1/appStoreVersions", body: [
            "data": [
                "type": "appStoreVersions",
                "attributes": ["platform": applePlatform, "versionString": versionString],
                "relationships": ["app": ["data": ["type": "apps", "id": appleAppID]]],
            ],
        ]).data)
        guard let id = created["data"]["id"].string else { throw RunError.missingVersion }
        appleVersionID = id
    }

    func appleVersionAttributes() async throws {
        guard let versionID = appleVersionID else { throw RunError.missingVersion }
        var attributes: [String: Any] = [:]
        if let releaseType = manifest.release?.apple?.releaseType {
            attributes["releaseType"] = releaseType.rawValue
        }
        guard !attributes.isEmpty else { return }
        try await api.apple("PATCH", "/v1/appStoreVersions/\(versionID)", body: [
            "data": ["type": "appStoreVersions", "id": versionID, "attributes": attributes],
        ])
    }

    func appleCategories() async throws {
        guard let infoID = appleInfoID else { return }
        var relationships: [String: Any] = [:]
        if let primary = manifest.review?.applePrimaryCategory, !primary.isEmpty {
            relationships["primaryCategory"] = ["data": ["type": "appCategories", "id": primary]]
        }
        if let secondary = manifest.review?.appleSecondaryCategory, !secondary.isEmpty {
            relationships["secondaryCategory"] = ["data": ["type": "appCategories",
                                                           "id": secondary]]
        }
        guard !relationships.isEmpty else { return }
        try await api.apple("PATCH", "/v1/appInfos/\(infoID)", body: [
            "data": ["type": "appInfos", "id": infoID, "relationships": relationships],
        ])
    }

    // MARK: - The two localization resources

    func appleInfoLocale(_ locale: String) async throws {
        guard let infoID = appleInfoID else { return }
        var attributes: [String: Any] = [:]
        put(&attributes, "name", manifest.listingText(locale: locale, field: .name))
        put(&attributes, "subtitle", manifest.listingText(locale: locale, field: .subtitle))
        put(&attributes, "privacyPolicyUrl",
            manifest.listingText(locale: locale, field: .privacyPolicyURL))
        guard !attributes.isEmpty else { return }

        if let id = appleInfoLocalizationIDs[locale] {
            try await api.apple("PATCH", "/v1/appInfoLocalizations/\(id)", body: [
                "data": ["type": "appInfoLocalizations", "id": id, "attributes": attributes],
            ])
            return
        }
        attributes["locale"] = locale
        let created = JSON(data: try await api.apple("POST", "/v1/appInfoLocalizations", body: [
            "data": [
                "type": "appInfoLocalizations",
                "attributes": attributes,
                "relationships": ["appInfo": ["data": ["type": "appInfos", "id": infoID]]],
            ],
        ]).data)
        appleInfoLocalizationIDs[locale] = created["data"]["id"].string
    }

    func appleVersionLocale(_ locale: String) async throws {
        guard let versionID = appleVersionID else { throw RunError.missingVersion }
        var attributes: [String: Any] = [:]
        put(&attributes, "description", manifest.listingText(locale: locale, field: .description))
        put(&attributes, "whatsNew", manifest.listingText(locale: locale, field: .whatsNew))
        put(&attributes, "keywords", manifest.listingText(locale: locale, field: .keywords))
        put(&attributes, "promotionalText",
            manifest.listingText(locale: locale, field: .promotionalText))
        put(&attributes, "supportUrl", manifest.listingText(locale: locale, field: .supportURL))
        put(&attributes, "marketingUrl", manifest.listingText(locale: locale, field: .marketingURL))
        guard !attributes.isEmpty else { return }

        if let id = appleVersionLocalizationIDs[locale] {
            try await api.apple("PATCH", "/v1/appStoreVersionLocalizations/\(id)", body: [
                "data": ["type": "appStoreVersionLocalizations", "id": id,
                         "attributes": attributes],
            ])
            return
        }
        attributes["locale"] = locale
        let created = JSON(data: try await api.apple(
            "POST", "/v1/appStoreVersionLocalizations", body: [
                "data": [
                    "type": "appStoreVersionLocalizations",
                    "attributes": attributes,
                    "relationships": ["appStoreVersion": [
                        "data": ["type": "appStoreVersions", "id": versionID]]],
                ],
            ]).data)
        guard let id = created["data"]["id"].string else {
            throw RunError.missingLocalization(locale)
        }
        appleVersionLocalizationIDs[locale] = id
    }

    // MARK: - The reservation upload, section 7.5

    func appleScreenshots(locale: String, files: [MediaUpload], index: Int) async throws {
        guard let localizationID = appleVersionLocalizationIDs[locale] else {
            throw RunError.missingLocalization(locale)
        }
        var setsByBucket: [String: String] = [:]
        var uploaded = 0

        for file in files {
            try Task.checkCancellation()
            let setID: String
            if let existing = setsByBucket[file.bucket] {
                setID = existing
            } else {
                setID = try await appleScreenshotSet(displayType: file.bucket,
                                                     localizationID: localizationID)
                setsByBucket[file.bucket] = setID
            }
            let data = try Data(contentsOf: file.url, options: .mappedIfSafe)
            let reservation = JSON(data: try await api.apple("POST", "/v1/appScreenshots", body: [
                "data": [
                    "type": "appScreenshots",
                    "attributes": ["fileName": file.url.lastPathComponent,
                                   "fileSize": data.count],
                    "relationships": ["appScreenshotSet": [
                        "data": ["type": "appScreenshotSets", "id": setID]]],
                ],
            ]).data)
            guard let screenshotID = reservation["data"]["id"].string else {
                throw RunError.uploadFailed(file.url.lastPathComponent)
            }
            try await executeUploadOperations(reservation["data"]["attributes"]["uploadOperations"],
                                              data: data)
            try await api.apple("PATCH", "/v1/appScreenshots/\(screenshotID)", body: [
                "data": ["type": "appScreenshots", "id": screenshotID,
                         "attributes": ["uploaded": true,
                                        "sourceFileChecksum": Checksums.md5(data)]],
            ])
            try await waitForDelivery(path: "/v1/appScreenshots/\(screenshotID)")
            uploaded += 1
            report(index: index, fraction: Double(uploaded) / Double(files.count),
                   detail: "\(uploaded) of \(files.count) screenshots")
        }
    }

    private func appleScreenshotSet(displayType: String,
                                    localizationID: String) async throws -> String {
        // Reuse the set when it exists. Spec 7.5, step 1.
        let existing = JSON(data: try await api.apple(
            "GET",
            "/v1/appStoreVersionLocalizations/\(localizationID)/appScreenshotSets?limit=50").data)
        for item in existing["data"].array
        where item["attributes"]["screenshotDisplayType"].string == displayType {
            if let id = item["id"].string { return id }
        }
        let created = JSON(data: try await api.apple("POST", "/v1/appScreenshotSets", body: [
            "data": [
                "type": "appScreenshotSets",
                "attributes": ["screenshotDisplayType": displayType],
                "relationships": ["appStoreVersionLocalization": [
                    "data": ["type": "appStoreVersionLocalizations", "id": localizationID]]],
            ],
        ]).data)
        guard let id = created["data"]["id"].string else {
            throw RunError.uploadFailed(displayType)
        }
        return id
    }

    func applePreviews(locale: String, files: [MediaUpload], index: Int) async throws {
        guard let localizationID = appleVersionLocalizationIDs[locale] else {
            throw RunError.missingLocalization(locale)
        }
        var uploaded = 0
        for file in files {
            try Task.checkCancellation()
            _ = try await AssetInspector.validatePreview(at: file.url)
            // ponytail: one display type for the previews. Add a video-track
            // probe when a developer ships previews for two display types at
            // once and complains that both landed in the same set.
            let displayType = "APP_IPHONE_67"

            let sets = JSON(data: try await api.apple(
                "GET",
                "/v1/appStoreVersionLocalizations/\(localizationID)/appPreviewSets?limit=50").data)
            var setID = sets["data"].array.first {
                $0["attributes"]["previewType"].string == displayType
            }?["id"].string
            if setID == nil {
                let created = JSON(data: try await api.apple("POST", "/v1/appPreviewSets", body: [
                    "data": [
                        "type": "appPreviewSets",
                        "attributes": ["previewType": displayType],
                        "relationships": ["appStoreVersionLocalization": [
                            "data": ["type": "appStoreVersionLocalizations",
                                     "id": localizationID]]],
                    ],
                ]).data)
                setID = created["data"]["id"].string
            }
            guard let setID else { throw RunError.uploadFailed(file.url.lastPathComponent) }

            let data = try Data(contentsOf: file.url, options: .mappedIfSafe)
            let reservation = JSON(data: try await api.apple("POST", "/v1/appPreviews", body: [
                "data": [
                    "type": "appPreviews",
                    "attributes": ["fileName": file.url.lastPathComponent,
                                   "fileSize": data.count],
                    "relationships": ["appPreviewSet": [
                        "data": ["type": "appPreviewSets", "id": setID]]],
                ],
            ]).data)
            guard let previewID = reservation["data"]["id"].string else {
                throw RunError.uploadFailed(file.url.lastPathComponent)
            }
            try await executeUploadOperations(reservation["data"]["attributes"]["uploadOperations"],
                                              data: data)
            try await api.apple("PATCH", "/v1/appPreviews/\(previewID)", body: [
                "data": ["type": "appPreviews", "id": previewID,
                         "attributes": ["uploaded": true,
                                        "sourceFileChecksum": Checksums.md5(data)]],
            ])
            uploaded += 1
            report(index: index, fraction: Double(uploaded) / Double(files.count),
                   detail: "\(uploaded) of \(files.count) previews")
        }
    }

    // MARK: - The build upload, section 7.6

    func appleBuildUpload(path: String, index: Int) async throws {
        guard let url = resolve(path) else { throw RunError.missingBuild }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let versionName = manifest.release?.versionName ?? ""
        let buildNumber = appleBuildNumber()

        let upload = JSON(data: try await api.apple("POST", "/v1/buildUploads", body: [
            "data": [
                "type": "buildUploads",
                "attributes": [
                    "cfBundleShortVersionString": versionName,
                    "cfBundleVersion": buildNumber,
                    "platform": applePlatform,
                ],
                "relationships": ["app": ["data": ["type": "apps", "id": appleAppID]]],
            ],
        ]).data)
        guard let uploadID = upload["data"]["id"].string else {
            throw RunError.uploadFailed(url.lastPathComponent)
        }

        let uti = url.pathExtension.lowercased() == "pkg" ? "com.apple.pkg" : "com.apple.ipa"
        let file = JSON(data: try await api.apple("POST", "/v1/buildUploadFiles", body: [
            "data": [
                "type": "buildUploadFiles",
                "attributes": [
                    "fileName": url.lastPathComponent,
                    "fileSize": data.count,
                    "assetType": "ASSET",
                    "uti": uti,
                ],
                "relationships": ["buildUpload": [
                    "data": ["type": "buildUploads", "id": uploadID]]],
            ],
        ]).data)
        guard let fileID = file["data"]["id"].string else {
            throw RunError.uploadFailed(url.lastPathComponent)
        }

        try await executeUploadOperations(file["data"]["attributes"]["uploadOperations"],
                                          data: data, index: index,
                                          label: url.lastPathComponent)

        try await api.apple("PATCH", "/v1/buildUploadFiles/\(fileID)", body: [
            "data": ["type": "buildUploadFiles", "id": fileID,
                     "attributes": ["uploaded": true,
                                    "sourceFileChecksum": Checksums.md5(data)]],
        ])

        // Apple takes minutes to process a build. The tab shows a live timer
        // and a cancel button while this polls. Spec 7.6, steps 5 and 6.
        let started = Date()
        while true {
            try Task.checkCancellation()
            try await Task.sleep(for: .seconds(15))
            let state = JSON(data: try await api.apple("GET", "/v1/buildUploads/\(uploadID)").data)
            let value = state["data"]["attributes"]["state"]["state"].string ?? "IN_PROGRESS"
            let elapsed = Int(Date().timeIntervalSince(started))
            report(index: index, fraction: 1,
                   detail: "Apple is processing the build · \(elapsed / 60):\(String(format: "%02d", elapsed % 60))")
            if value == "COMPLETE" || value == "COMPLETED" { break }
            if value.contains("FAIL") {
                let detail = state["data"]["attributes"]["state"]["errors"][0]["message"].string
                    ?? "The build upload failed."
                throw RunError.processingFailed(detail)
            }
        }

        let builds = JSON(data: try await api.apple(
            "GET", "/v1/builds?filter%5Bapp%5D=\(appleAppID)&limit=20").data)
        appleBuildID = builds["data"].array.first {
            $0["attributes"]["version"].string == buildNumber
                || $0["attributes"]["version"].int == Int(buildNumber)
        }?["id"].string ?? builds["data"].array.first?["id"].string
    }

    func appleAttachBuild() async throws {
        guard let versionID = appleVersionID else { throw RunError.missingVersion }
        guard let buildID = appleBuildID else { return }
        try await api.apple("PATCH", "/v1/appStoreVersions/\(versionID)/relationships/build",
                            body: ["data": ["type": "builds", "id": buildID]])
    }

    /// Runs the `uploadOperations` from a reservation response. Each one names
    /// its own slice of the file.
    private func executeUploadOperations(_ operations: JSON, data: Data, index: Int? = nil,
                                         label: String = "") async throws {
        let list = operations.array
        var sent = 0
        for operation in list {
            try Task.checkCancellation()
            guard let method = operation["method"].string,
                  let urlString = operation["url"].string else { continue }
            let offset = operation["offset"].int ?? 0
            let length = operation["length"].int ?? data.count
            let end = min(offset + length, data.count)
            guard offset < end else { continue }
            var headers: [String: String] = [:]
            for header in operation["requestHeaders"].array {
                guard let name = header["name"].string,
                      let value = header["value"].string else { continue }
                headers[name] = value
            }
            try await api.appleUploadOperation(method: method, urlString: urlString,
                                               headers: headers,
                                               body: data.subdata(in: offset..<end))
            sent += 1
            if let index {
                report(index: index, fraction: Double(sent) / Double(max(1, list.count)),
                       detail: "\(label) · part \(sent) of \(list.count)")
            }
        }
    }

    /// Spec 7.5, step 4. A `FAILED` delivery carries its errors.
    private func waitForDelivery(path: String) async throws {
        for _ in 0..<20 {
            let state = JSON(data: try await api.apple("GET", path).data)
            let delivery = state["data"]["attributes"]["assetDeliveryState"]
            let value = delivery["state"].string ?? "UPLOAD_COMPLETE"
            if value == "COMPLETE" { return }
            if value == "FAILED" {
                throw RunError.processingFailed(
                    delivery["errors"][0]["description"].string ?? "The asset was rejected.")
            }
            try await Task.sleep(for: .seconds(2))
        }
    }

    // MARK: - The review resources

    func appleReviewDetails() async throws {
        guard let versionID = appleVersionID, let review = manifest.review else { return }
        var attributes: [String: Any] = [:]
        put(&attributes, "contactFirstName", review.contactFirstName ?? "")
        put(&attributes, "contactLastName", review.contactLastName ?? "")
        put(&attributes, "contactEmail", review.contactEmail ?? "")
        put(&attributes, "contactPhone", review.contactPhone ?? "")
        put(&attributes, "notes", review.notes ?? "")
        attributes["demoAccountRequired"] = review.demoAccountRequired ?? false
        if review.demoAccountRequired == true, let account = reviewerCredential {
            put(&attributes, "demoAccountName", account.username)
            put(&attributes, "demoAccountPassword", account.password)
        }

        if let id = actual.apple?.reviewDetailId {
            try await api.apple("PATCH", "/v1/appStoreReviewDetails/\(id)", body: [
                "data": ["type": "appStoreReviewDetails", "id": id, "attributes": attributes],
            ])
            return
        }
        try await api.apple("POST", "/v1/appStoreReviewDetails", body: [
            "data": [
                "type": "appStoreReviewDetails",
                "attributes": attributes,
                "relationships": ["appStoreVersion": [
                    "data": ["type": "appStoreVersions", "id": versionID]]],
            ],
        ])
    }

    func appleAgeRating() async throws {
        guard let id = actual.apple?.ageRatingDeclarationId,
              let answers = manifest.review?.ageRatingAnswers, !answers.isEmpty else { return }
        try await api.apple("PATCH", "/v1/ageRatingDeclarations/\(id)", body: [
            "data": ["type": "ageRatingDeclarations", "id": id, "attributes": answers],
        ])
    }

    // MARK: - The purchases, section 7.7

    func applePurchases() async throws {
        let existing = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appleAppID)/inAppPurchasesV2?limit=200").data)
        var byProductID: [String: String] = [:]
        for item in existing["data"].array {
            guard let productID = item["attributes"]["productId"].string,
                  let id = item["id"].string else { continue }
            byProductID[productID] = id
        }

        for purchase in manifest.purchases ?? [] {
            try Task.checkCancellation()
            let attributes: [String: Any] = [
                "name": purchase.name ?? purchase.id,
                "productId": purchase.id,
                "inAppPurchaseType": Self.appleProductType(purchase.kind),
                "reviewNote": purchase.reviewNote ?? "",
            ]
            // Re-read by the natural key first. Spec section 14 forbids a
            // blind create.
            if let id = byProductID[purchase.id] {
                try await api.apple("PATCH", "/v2/inAppPurchases/\(id)", body: [
                    "data": ["type": "inAppPurchases", "id": id,
                             "attributes": ["name": purchase.name ?? purchase.id,
                                            "reviewNote": purchase.reviewNote ?? ""]],
                ])
            } else {
                try await api.apple("POST", "/v2/inAppPurchases", body: [
                    "data": [
                        "type": "inAppPurchases",
                        "attributes": attributes,
                        "relationships": ["app": ["data": ["type": "apps", "id": appleAppID]]],
                    ],
                ])
            }
        }
    }

    static func appleProductType(_ kind: Manifest.Purchase.Kind) -> String {
        switch kind {
        case .consumable: "CONSUMABLE"
        case .nonConsumable: "NON_CONSUMABLE"
        case .nonRenewing: "NON_RENEWING_SUBSCRIPTION"
        }
    }

    func applePhasedRelease() async throws {
        guard let versionID = appleVersionID else { throw RunError.missingVersion }
        try await api.apple("POST", "/v1/appStoreVersionPhasedReleases", body: [
            "data": [
                "type": "appStoreVersionPhasedReleases",
                "attributes": ["phasedReleaseState": "INACTIVE"],
                "relationships": ["appStoreVersion": [
                    "data": ["type": "appStoreVersions", "id": versionID]]],
            ],
        ])
    }

    func appleAvailability() async throws {
        try await api.apple("POST", "/v2/appAvailabilities", body: [
            "data": [
                "type": "appAvailabilities",
                "attributes": ["availableInNewTerritories":
                                manifest.pricing?.autoConvertOtherTerritories ?? true],
                "relationships": ["app": ["data": ["type": "apps", "id": appleAppID]]],
            ],
        ])
    }

    func appleBuildNumber() -> String {
        // The build carries the number. The manifest never holds a second copy.
        if let path = Planner.applePath(manifest), let url = resolve(path),
           let package = try? PackageReader().read(url), let number = package.buildNumber {
            return number
        }
        return "1"
    }

    /// Writes a value only when the manifest manages it. An empty string means
    /// "not managed", so the store keeps what it holds.
    func put(_ attributes: inout [String: Any], _ key: String, _ value: String) {
        guard !value.isEmpty else { return }
        attributes[key] = value
    }
}
