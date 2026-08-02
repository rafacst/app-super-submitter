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
        put(&attributes, "privacyPolicyText",
            manifest.listingText(locale: locale, field: .privacyPolicyText))
        put(&attributes, "privacyChoicesUrl",
            manifest.listingText(locale: locale, field: .privacyChoicesURL))
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

        // Replacing the relationship is the only reliable way to make both
        // deletion and ordering match the manifest. Checksums in the planner
        // keep this path off a no-op apply.
        for bucket in Set(files.map(\.bucket)) {
            let setID = try await appleScreenshotSet(displayType: bucket,
                                                     localizationID: localizationID)
            setsByBucket[bucket] = setID
            let existing = JSON(data: try await api.apple(
                "GET", "/v1/appScreenshotSets/\(setID)/appScreenshots?limit=50").data)
            for item in existing["data"].array {
                if let id = item["id"].string {
                    try await api.apple("DELETE", "/v1/appScreenshots/\(id)")
                }
            }
        }

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

    func applePreviews(locale: String, displayType: String, files: [MediaUpload],
                       index: Int) async throws {
        guard let localizationID = appleVersionLocalizationIDs[locale] else {
            throw RunError.missingLocalization(locale)
        }
        var uploaded = 0
        let sets = JSON(data: try await api.apple(
            "GET", "/v1/appStoreVersionLocalizations/\(localizationID)/appPreviewSets?limit=50").data)
        if let setID = sets["data"].array.first(where: {
            $0["attributes"]["previewType"].string == displayType
        })?["id"].string {
            let existing = JSON(data: try await api.apple(
                "GET", "/v1/appPreviewSets/\(setID)/appPreviews?limit=50").data)
            for item in existing["data"].array {
                if let id = item["id"].string {
                    try await api.apple("DELETE", "/v1/appPreviews/\(id)")
                }
            }
        }
        for file in files {
            try Task.checkCancellation()
            _ = try await AssetInspector.validatePreview(at: file.url)
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
        let deadline = started.addingTimeInterval(60 * 60)
        while true {
            try Task.checkCancellation()
            guard Date() <= deadline else {
                throw RunError.processingFailed(
                    "Apple did not finish processing the build within one hour.")
            }
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

        for attempt in 0..<30 {
            let builds = JSON(data: try await api.apple(
                "GET", "/v1/builds?filter%5Bapp%5D=\(appleAppID)&sort=-uploadedDate&limit=200").data)
            if let match = Self.matchingBuildID(in: builds, buildNumber: buildNumber) {
                appleBuildID = match
                break
            }
            if attempt < 29 { try await Task.sleep(for: .seconds(2)) }
        }
        guard appleBuildID != nil else { throw RunError.missingBuild }
    }

    func appleAttachBuild() async throws {
        guard let versionID = appleVersionID else { throw RunError.missingVersion }
        guard let buildID = appleBuildID else { return }
        try await api.apple("PATCH", "/v1/appStoreVersions/\(versionID)/relationships/build",
                            body: ["data": ["type": "builds", "id": buildID]])
    }

    func appleBuildCompliance() async throws {
        guard let buildID = appleBuildID ?? actual.apple?.attachedBuildId,
              let value = manifest.review?.usesNonExemptEncryption else { return }
        try await api.apple("PATCH", "/v1/builds/\(buildID)", body: [
            "data": ["type": "builds", "id": buildID,
                     "attributes": ["usesNonExemptEncryption": value]],
        ])
    }

    /// Runs the `uploadOperations` from a reservation response. Each one names
    /// its own slice of the file.
    func executeUploadOperations(_ operations: JSON, data: Data, index: Int? = nil,
                                         label: String = "") async throws {
        let list = operations.array
        var sent = 0
        for operation in list {
            try Task.checkCancellation()
            guard let method = operation["method"].string,
                  let urlString = operation["url"].string else { continue }
            let offset = operation["offset"].int ?? 0
            let length = operation["length"].int ?? data.count
            guard let range = Self.validUploadRange(offset: offset, length: length,
                                                    dataCount: data.count) else { continue }
            var headers: [String: String] = [:]
            for header in operation["requestHeaders"].array {
                guard let name = header["name"].string,
                      let value = header["value"].string else { continue }
                headers[name] = value
            }
            try await api.appleUploadOperation(method: method, urlString: urlString,
                                               headers: headers,
                                               body: data.subdata(in: range))
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
        throw RunError.processingFailed("The uploaded asset did not finish processing in time.")
    }

    static func matchingBuildID(in response: JSON, buildNumber: String) -> String? {
        response["data"].array.first {
            $0["attributes"]["version"].string == buildNumber
                || $0["attributes"]["version"].int == Int(buildNumber)
        }?["id"].string
    }

    static func validUploadRange(offset: Int, length: Int, dataCount: Int) -> Range<Int>? {
        guard offset >= 0, length > 0, dataCount >= 0, offset < dataCount else { return nil }
        let (sum, overflow) = offset.addingReportingOverflow(length)
        let end = overflow ? dataCount : min(sum, dataCount)
        return offset < end ? offset..<end : nil
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
            try await appleReviewAttachments(review.attachments ?? [], reviewDetailID: id)
            return
        }
        let created = JSON(data: try await api.apple("POST", "/v1/appStoreReviewDetails", body: [
            "data": [
                "type": "appStoreReviewDetails",
                "attributes": attributes,
                "relationships": ["appStoreVersion": [
                    "data": ["type": "appStoreVersions", "id": versionID]]],
            ],
        ]).data)
        if let id = created["data"]["id"].string {
            try await appleReviewAttachments(review.attachments ?? [], reviewDetailID: id)
        }
    }

    private func appleReviewAttachments(_ paths: [String],
                                        reviewDetailID: String) async throws {
        for path in paths {
            guard let url = resolve(path) else { continue }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let reservation = JSON(data: try await api.apple(
                "POST", "/v1/appStoreReviewAttachments", body: [
                    "data": [
                        "type": "appStoreReviewAttachments",
                        "attributes": ["fileName": url.lastPathComponent,
                                       "fileSize": data.count],
                        "relationships": ["appStoreReviewDetail": [
                            "data": ["type": "appStoreReviewDetails",
                                     "id": reviewDetailID]]],
                    ],
                ]).data)
            guard let id = reservation["data"]["id"].string else { continue }
            try await executeUploadOperations(
                reservation["data"]["attributes"]["uploadOperations"], data: data)
            try await api.apple("PATCH", "/v1/appStoreReviewAttachments/\(id)", body: [
                "data": ["type": "appStoreReviewAttachments", "id": id,
                         "attributes": ["uploaded": true,
                                        "sourceFileChecksum": Checksums.md5(data)]],
            ])
        }
    }

    func appleAgeRating() async throws {
        guard let id = actual.apple?.ageRatingDeclarationId else { return }
        var attributes: [String: Any] = manifest.review?.ageRatingAnswers ?? [:]
        if let band = manifest.review?.kidsAgeBand { attributes["kidsAgeBand"] = band }
        guard !attributes.isEmpty else { return }
        try await api.apple("PATCH", "/v1/ageRatingDeclarations/\(id)", body: [
            "data": ["type": "ageRatingDeclarations", "id": id, "attributes": attributes],
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
            let purchaseID: String
            if let id = byProductID[purchase.id] {
                purchaseID = id
                try await api.apple("PATCH", "/v2/inAppPurchases/\(id)", body: [
                    "data": ["type": "inAppPurchases", "id": id,
                             "attributes": ["name": purchase.name ?? purchase.id,
                                            "reviewNote": purchase.reviewNote ?? ""]],
                ])
            } else {
                let created = JSON(data: try await api.apple("POST", "/v2/inAppPurchases", body: [
                    "data": [
                        "type": "inAppPurchases",
                        "attributes": attributes,
                        "relationships": ["app": ["data": ["type": "apps", "id": appleAppID]]],
                    ],
                ]).data)
                guard let id = created["data"]["id"].string else { continue }
                purchaseID = id
            }
            try await applePurchaseDetails(purchase, purchaseID: purchaseID)
        }
    }

    private func applePurchaseDetails(_ purchase: Manifest.Purchase,
                                      purchaseID: String) async throws {
        let versions = JSON(data: try await api.apple(
            "GET", "/v2/inAppPurchases/\(purchaseID)/inAppPurchaseVersions?limit=50").data)
        var purchaseVersionID = versions["data"].array.first?["id"].string
        if purchaseVersionID == nil, purchase.locales?.isEmpty == false {
            let created = JSON(data: try await api.apple(
                "POST", "/v1/inAppPurchaseVersions", body: [
                    "data": [
                        "type": "inAppPurchaseVersions",
                        "relationships": ["inAppPurchase": [
                            "data": ["type": "inAppPurchases", "id": purchaseID]]],
                    ],
                ]).data)
            purchaseVersionID = created["data"]["id"].string
        }
        var localizationIDs: [String: String] = [:]
        if let purchaseVersionID {
            let existing = JSON(data: try await api.apple(
                "GET", "/v1/inAppPurchaseVersions/\(purchaseVersionID)"
                    + "/inAppPurchaseLocalizations?limit=200").data)
            for item in existing["data"].array {
                if let locale = item["attributes"]["locale"].string,
                   let id = item["id"].string { localizationIDs[locale] = id }
            }
        }
        for (locale, text) in (purchase.locales ?? [:]).sorted(by: { $0.key < $1.key }) {
            let attributes = ["locale": locale, "name": text.name ?? purchase.id,
                              "description": text.description ?? ""]
            if let id = localizationIDs[locale] {
                try await api.apple("PATCH", "/v2/inAppPurchaseLocalizations/\(id)", body: [
                    "data": ["type": "inAppPurchaseLocalizations", "id": id,
                             "attributes": attributes],
                ])
            } else if let purchaseVersionID {
                try await api.apple("POST", "/v2/inAppPurchaseLocalizations", body: [
                    "data": [
                        "type": "inAppPurchaseLocalizations",
                        "attributes": attributes,
                        "relationships": ["inAppPurchaseVersion": [
                            "data": ["type": "inAppPurchaseVersions",
                                     "id": purchaseVersionID]]],
                    ],
                ])
            }
        }
        if let price = purchase.price {
            let territory = price.territory ?? "USA"
            let points = JSON(data: try await api.apple(
                "GET", "/v2/inAppPurchases/\(purchaseID)/pricePoints"
                    + "?filter%5Bterritory%5D=\(territory)&limit=200").data)
            if let point = Self.nearestPricePoint(points, to: price.amount) {
                let priceID = "price-\(UUID().uuidString)"
                try await api.apple("POST", "/v1/inAppPurchasePriceSchedules", body: [
                    "data": [
                        "type": "inAppPurchasePriceSchedules",
                        "relationships": [
                            "inAppPurchase": ["data": ["type": "inAppPurchases",
                                                        "id": purchaseID]],
                            "baseTerritory": ["data": ["type": "territories",
                                                        "id": territory]],
                            "manualPrices": ["data": [["type": "inAppPurchasePrices",
                                                         "id": priceID]]],
                        ],
                    ],
                    "included": [[
                        "type": "inAppPurchasePrices", "id": priceID,
                        "attributes": ["startDate": NSNull(), "endDate": NSNull()],
                        "relationships": ["inAppPurchasePricePoint": [
                            "data": ["type": "inAppPurchasePricePoints", "id": point]]],
                    ]],
                ])
            }
        }
        if let territories = purchase.availableTerritories, !territories.isEmpty {
            try await api.apple("POST", "/v1/inAppPurchaseAvailabilities", body: [
                "data": [
                    "type": "inAppPurchaseAvailabilities",
                    "attributes": ["availableInNewTerritories": false],
                    "relationships": [
                        "inAppPurchase": ["data": ["type": "inAppPurchases",
                                                    "id": purchaseID]],
                        "availableTerritories": ["data": territories.map {
                            ["type": "territories", "id": $0]
                        }],
                    ],
                ],
            ])
        }
        if let hosting = purchase.contentHosting {
            try await api.apple("PATCH", "/v2/inAppPurchases/\(purchaseID)", body: [
                "data": ["type": "inAppPurchases", "id": purchaseID,
                         "attributes": ["contentHosting": hosting]],
            ])
        }
        if purchase.promotedPurchase == true {
            try await api.apple("POST", "/v1/promotedPurchases", body: [
                "data": ["type": "promotedPurchases",
                         "attributes": ["visibleForAllUsers": true],
                         "relationships": [
                            "app": ["data": ["type": "apps", "id": appleAppID]],
                            "inAppPurchaseV2": ["data": ["type": "inAppPurchases",
                                                           "id": purchaseID]],
                         ]],
            ])
        }
        if let path = purchase.reviewScreenshot, let url = resolve(path) {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let reservation = JSON(data: try await api.apple(
                "POST", "/v1/inAppPurchaseAppStoreReviewScreenshots", body: [
                    "data": ["type": "inAppPurchaseAppStoreReviewScreenshots",
                             "attributes": ["fileName": url.lastPathComponent,
                                            "fileSize": data.count],
                             "relationships": ["inAppPurchaseV2": [
                                "data": ["type": "inAppPurchases", "id": purchaseID]]]],
                ]).data)
            if let id = reservation["data"]["id"].string {
                try await executeUploadOperations(
                    reservation["data"]["attributes"]["uploadOperations"], data: data)
                try await api.apple("PATCH",
                    "/v1/inAppPurchaseAppStoreReviewScreenshots/\(id)", body: [
                        "data": ["type": "inAppPurchaseAppStoreReviewScreenshots", "id": id,
                                 "attributes": ["uploaded": true]],
                    ])
            }
        }
        if let path = purchase.content, let url = resolve(path) {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let reservation = JSON(data: try await api.apple(
                "POST", "/v1/inAppPurchaseContents", body: [
                    "data": [
                        "type": "inAppPurchaseContents",
                        "attributes": ["fileName": url.lastPathComponent,
                                       "fileSize": data.count],
                        "relationships": ["inAppPurchaseV2": [
                            "data": ["type": "inAppPurchases", "id": purchaseID]]],
                    ],
                ]).data)
            if let id = reservation["data"]["id"].string {
                try await executeUploadOperations(
                    reservation["data"]["attributes"]["uploadOperations"], data: data)
                try await api.apple("PATCH", "/v1/inAppPurchaseContents/\(id)", body: [
                    "data": ["type": "inAppPurchaseContents", "id": id,
                             "attributes": ["uploaded": true,
                                            "sourceFileChecksum": Checksums.md5(data)]],
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
        let desired: String = switch manifest.release?.apple?.phasedReleaseState {
        case .paused: "PAUSED"
        case .active, nil: "ACTIVE"
        }
        let current = JSON(data: try await api.apple(
            "GET", "/v1/appStoreVersions/\(versionID)/appStoreVersionPhasedRelease").data)
        if let id = current["data"]["id"].string {
            try await api.apple("PATCH", "/v1/appStoreVersionPhasedReleases/\(id)", body: [
                "data": ["type": "appStoreVersionPhasedReleases", "id": id,
                         "attributes": ["phasedReleaseState": desired]],
            ])
            return
        }
        try await api.apple("POST", "/v1/appStoreVersionPhasedReleases", body: [
            "data": [
                "type": "appStoreVersionPhasedReleases",
                "attributes": ["phasedReleaseState": desired],
                "relationships": ["appStoreVersion": [
                    "data": ["type": "appStoreVersions", "id": versionID]]],
            ],
        ])
    }

    func appleAvailability() async throws {
        let requested = manifest.pricing?.territories ?? []
        let included: [[String: Any]] = requested.enumerated().map { index, item in
            var attributes: [String: Any] = ["available": item.available]
            if let preorder = item.preOrderEnabled { attributes["preOrderEnabled"] = preorder }
            if let date = item.releaseDate { attributes["releaseDate"] = date }
            return [
                "type": "territoryAvailabilities", "id": "territory-\(index)",
                "attributes": attributes,
                "relationships": ["territory": [
                    "data": ["type": "territories", "id": item.territory]]],
            ]
        }
        var data: [String: Any] = [
                "type": "appAvailabilities",
                "attributes": ["availableInNewTerritories":
                                manifest.pricing?.autoConvertOtherTerritories ?? true],
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appleAppID]],
                    "territoryAvailabilities": ["data": included.map {
                        ["type": "territoryAvailabilities", "id": $0["id"] as Any]
                    }],
                ],
            ]
        let method: String
        let path: String
        if let id = actual.apple?.appAvailabilityId {
            method = "PATCH"
            path = "/v2/appAvailabilities/\(id)"
            data["id"] = id
        } else {
            method = "POST"
            path = "/v2/appAvailabilities"
        }
        try await api.apple(method, path, body: ["data": data, "included": included])
    }

    func appleAppPrice() async throws {
        guard let price = manifest.pricing?.base else { return }
        let territory = price.territory ?? "USA"
        let points = JSON(data: try await api.apple(
            "GET", "/v3/appPricePoints?filter%5Bapp%5D=\(appleAppID)"
                + "&filter%5Bterritory%5D=\(territory)&limit=200").data)
        guard let point = Self.nearestPricePoint(points, to: price.amount) else { return }
        let appPriceID = "price-\(UUID().uuidString)"
        try await api.apple("POST", "/v1/appPriceSchedules", body: [
            "data": [
                "type": "appPriceSchedules",
                "relationships": [
                    "app": ["data": ["type": "apps", "id": appleAppID]],
                    "baseTerritory": ["data": ["type": "territories", "id": territory]],
                    "manualPrices": ["data": [["type": "appPrices", "id": appPriceID]]],
                ],
            ],
            "included": [[
                "type": "appPrices", "id": appPriceID,
                "attributes": ["startDate": NSNull(), "endDate": NSNull()],
                "relationships": ["appPricePoint": [
                    "data": ["type": "appPricePoints", "id": point]]],
            ]],
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
