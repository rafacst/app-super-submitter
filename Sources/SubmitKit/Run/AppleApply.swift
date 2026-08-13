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

        // The run seeded the localization ids from the read, and that read
        // found no version to write to. Whatever sits in the map now belongs
        // to another version, and every later step writes through this map:
        // `appleVersionLocale` patches these ids, and `appleScreenshots`
        // deletes and re-uploads inside them. A stale id here would edit the
        // listing the customers are reading.
        //
        // Apple pre-fills a new version from the last one, so this read
        // usually returns the copied localizations and the later steps patch
        // them. When it returns nothing, they create their own. Both are
        // correct, and neither one guesses.
        appleVersionLocalizationIDs = [:]
        let localizations = JSON(data: try await api.apple(
            "GET", "/v1/appStoreVersions/\(id)/appStoreVersionLocalizations?limit=200").data)
        for item in localizations["data"].array {
            guard let locale = item["attributes"]["locale"].string,
                  let localizationID = item["id"].string else { continue }
            appleVersionLocalizationIDs[locale] = localizationID
        }
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
        try await appleDropEmptyMediaSets(locale)

        // What this localization already holds, and only when it exists.
        //
        // An update inherits the released version, so most of these fields are
        // already on the resource before the run starts, and sending them
        // writes the same bytes over the same bytes. The plan says so: it
        // names the fields that differ and no others, and this sends what the
        // plan named. The two guards below are `Planner.appendChange`, which
        // is why they agree.
        //
        // The id is the whole test. A localization this run is about to create
        // holds nothing, so nothing may be skipped against it, and Apple does
        // not always carry one across. `appleEnsureVersion` re-reads the map
        // from the version it just made, so by here the id is the truth about
        // what exists rather than what the plan hoped for.
        let existingID = appleVersionLocalizationIDs[locale]
        let starting = existingID == nil ? nil : actual.apple?.startingVersionLocale(locale)
        var attributes: [String: Any] = [:]
        func send(_ key: String, _ field: ListingTextField, _ current: String?) {
            let wanted = manifest.listingText(locale: locale, field: field)
            guard !wanted.isEmpty, wanted != (current ?? "") else { return }
            attributes[key] = wanted
        }
        send("description", .description, starting?.description)
        send("whatsNew", .whatsNew, starting?.whatsNew)
        send("keywords", .keywords, starting?.keywords)
        send("promotionalText", .promotionalText, starting?.promotionalText)
        send("supportUrl", .supportURL, starting?.supportUrl)
        send("marketingUrl", .marketingURL, starting?.marketingUrl)
        guard !attributes.isEmpty else { return }

        if let id = existingID {
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

    /// Every screenshot bucket the manifest names for one locale.
    ///
    /// The display type comes from the image's own pixels, the same way the
    /// plan picks it, so this and the upload can never disagree about which
    /// bucket a file belongs in. It reads image headers and no pixel data.
    func appleWantedBuckets(locale: String) -> Set<String> {
        var result: Set<String> = []
        for deviceClass in Manifest.DeviceClass.allCases {
            // Apple's own list. An override sends this store its pictures
            // and never Play's.
            for path in manifest.mediaPaths(locale: locale, deviceClass: deviceClass,
                                            store: .apple) {
                guard let url = resolve(path),
                      let info = try? AssetInspector.image(at: url),
                      let bucket = try? AssetInspector.appleDisplayType(for: info,
                                                                        deviceClass: deviceClass)
                else { continue }
                result.insert(bucket)
            }
        }
        return result
    }

    /// The device classes the manifest fills for one locale, which are the only
    /// ones a run is allowed to clear.
    ///
    /// The Media tab makes one promise twice: "An empty size keeps what is
    /// live", and "Leave this size empty to keep them". A group the developer
    /// left alone is a group this app was never given anything for, and it is
    /// not an instruction to take the App Store's pictures down.
    func appleFilledDeviceClasses(locale: String, previews: Bool) -> Set<Manifest.DeviceClass> {
        var result: Set<Manifest.DeviceClass> = []
        for deviceClass in Manifest.DeviceClass.allCases {
            let paths = previews
                ? manifest.mediaPaths(locale: locale, deviceClass: deviceClass, previews: true)
                : manifest.mediaPaths(locale: locale, deviceClass: deviceClass, store: .apple)
            if !paths.isEmpty { result.insert(deviceClass) }
        }
        return result
    }

    func appleScreenshots(locale: String, files: [MediaUpload], index: Int) async throws {
        guard let localizationID = appleVersionLocalizationIDs[locale] else {
            throw RunError.missingLocalization(locale)
        }
        var setsByBucket: [String: String] = [:]
        var uploaded = 0

        // Replacing the relationship is the only reliable way to make both
        // deletion and ordering match the manifest. Checksums in the planner
        // keep this path off a no-op apply.
        let wantedBuckets = Set(files.map(\.bucket))
        // A device class the manifest dropped leaves a whole set behind, and
        // the loop below never visits it. Apple keeps showing those
        // screenshots, so the set goes before anything else runs.
        //
        // What it keeps is every bucket the manifest names, and not this
        // step's. One step is planned per device class, so keeping only its
        // own buckets meant the phone step deleted the iPad set and the iPad
        // step deleted the phone set: an app with screenshots for two device
        // classes published whichever class the run happened to write last.
        try await appleDropMediaSets(
            localizationID: localizationID, collection: "appScreenshotSets",
            typeKey: "screenshotDisplayType", path: "/v1/appScreenshotSets",
            keeping: appleWantedBuckets(locale: locale),
            replacing: appleFilledDeviceClasses(locale: locale, previews: false))

        for bucket in wantedBuckets {
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
        let versionName = manifest.versionName(for: .apple) ?? ""
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

    /// The build this run may write to.
    ///
    /// The one it just uploaded comes first. Then the one App Store Connect
    /// already holds for this version, which is how a Build from Project
    /// upload reaches these steps. The attached one is the last answer,
    /// because a second apply finds it there and nothing else.
    ///
    /// `// ponytail: one lookup, three callers. Three copies drifted the day
    /// // the upload stopped being the only way in.`
    var appleTargetBuildID: String? {
        appleBuildID ?? actual.apple?.buildIdForVersion ?? actual.apple?.attachedBuildId
    }

    func appleAttachBuild() async throws {
        guard let versionID = appleVersionID else { throw RunError.missingVersion }
        guard let buildID = appleTargetBuildID else { return }
        try await api.apple("PATCH", "/v1/appStoreVersions/\(versionID)/relationships/build",
                            body: ["data": ["type": "builds", "id": buildID]])
    }

    /// Apple's yes or no question, written on the build that ships.
    ///
    /// Apple fills this from `ITSAppUsesNonExemptEncryption` inside the binary
    /// while it processes the build, and it answers 409 to a PATCH once the
    /// value is there. So the build is asked first: one that already carries
    /// the answer needs no write, and one that carries the other answer is a
    /// fact of the binary that no call changes. The run stopped here with "the
    /// store already holds something that conflicts with this", which named
    /// neither of those two states.
    func appleBuildCompliance() async throws {
        guard let buildID = appleTargetBuildID,
              let value = manifest.review?.usesNonExemptEncryption else { return }
        let build = JSON(data: try await api.apple("GET", "/v1/builds/\(buildID)").data)
        let held = build["data"]["attributes"]["usesNonExemptEncryption"].bool
        guard held != value else { return }
        if let held {
            throw RunError.encryptionAnswerFixed(held: held, wanted: value)
        }
        try await api.apple("PATCH", "/v1/builds/\(buildID)", body: [
            "data": ["type": "builds", "id": buildID,
                     "attributes": ["usesNonExemptEncryption": value]],
        ])
    }

    /// The export compliance declaration.
    ///
    /// The build flag answers Apple's yes or no question. An app that uses
    /// non-exempt encryption and claims no exemption also owes this
    /// declaration, and Apple attaches it to the build that ships.
    func appleEncryptionDeclaration() async throws {
        guard let encryption = manifest.review?.encryption else { return }
        var attributes: [String: Any] = [
            "appEncryptionDeclarationState": "IN_REVIEW",
            "usesEncryption": manifest.review?.usesNonExemptEncryption ?? true,
        ]
        put(&attributes, "exempt", encryption.exempt)
        put(&attributes, "availableOnFrenchStore", encryption.availableOnFrenchStore)
        put(&attributes, "containsProprietaryCryptography",
            encryption.containsProprietaryCryptography)
        put(&attributes, "containsThirdPartyCryptography",
            encryption.containsThirdPartyCryptography)
        put(&attributes, "codeValue", encryption.codeValue)

        let created = JSON(data: try await api.apple(
            "POST", "/v1/appEncryptionDeclarations", body: [
                "data": [
                    "type": "appEncryptionDeclarations",
                    "attributes": attributes,
                    "relationships": ["app": ["data": ["type": "apps", "id": appleAppID]]],
                ],
            ]).data)
        guard let declarationID = created["data"]["id"].string else { return }

        // The CCATS or ERN document, when the manifest names one. Apple takes
        // it through the same reserve and upload that a screenshot uses.
        if let path = encryption.documentPath, let url = resolve(path) {
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let reservation = JSON(data: try await api.apple(
                "POST", "/v1/appEncryptionDeclarationDocuments", body: [
                    "data": [
                        "type": "appEncryptionDeclarationDocuments",
                        "attributes": [
                            "fileName": url.lastPathComponent,
                            "fileSize": data.count,
                        ],
                        "relationships": [
                            "appEncryptionDeclaration": [
                                "data": ["type": "appEncryptionDeclarations",
                                         "id": declarationID],
                            ],
                        ],
                    ],
                ]).data)
            try await executeUploadOperations(
                reservation["data"]["attributes"]["uploadOperations"], data: data)
            if let documentID = reservation["data"]["id"].string {
                try await api.apple(
                    "PATCH", "/v1/appEncryptionDeclarationDocuments/\(documentID)", body: [
                        "data": ["type": "appEncryptionDeclarationDocuments",
                                 "id": documentID,
                                 "attributes": ["uploaded": true]],
                    ])
            }
        }

        // The declaration only means something once a build carries it.
        if let buildID = appleTargetBuildID {
            try await api.apple(
                "PATCH", "/v1/builds/\(buildID)", body: [
                    "data": [
                        "type": "builds",
                        "id": buildID,
                        "relationships": ["appEncryptionDeclaration": [
                            "data": ["type": "appEncryptionDeclarations",
                                     "id": declarationID],
                        ]],
                    ],
                ])
        }
    }

    /// The offer codes of one purchase.
    ///
    /// A subscription offer code already rides inside the subscription offer
    /// step. Apple keeps the one-time purchase codes on their own collection,
    /// so they take their own step and name their product.
    ///
    /// Apple creates the offer in a draft state and creates no redeemable
    /// code. `codes:` writes the codes and `active: true` opens the offer, both
    /// through `appleOfferCodeValues`, exactly as the subscription twin does.
    /// An offer without `codes:` still reaches nobody, which is the state the
    /// validator names.
    func applePurchaseOfferCodes(productId: String) async throws {
        guard let purchase = (manifest.purchases ?? []).first(where: { $0.id == productId }),
              let offers = purchase.offers, !offers.isEmpty else { return }
        let existing = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appleAppID)/inAppPurchasesV2?limit=200").data)
        guard let purchaseID = existing["data"].array.first(where: {
            $0["attributes"]["productId"].string == productId
        })?["id"].string else { return }

        let known = JSON(data: try await api.apple(
            "GET", "/v2/inAppPurchases/\(purchaseID)/offerCodes?limit=200").data)
        // The id and not only the name. The offer Apple already holds keeps
        // its id, so a second pass fills in the codes that an earlier version
        // of this app never wrote.
        var heldIDs: [String: String] = [:]
        for item in known["data"].array {
            guard let name = item["attributes"]["name"].string,
                  let id = item["id"].string else { continue }
            heldIDs[name] = id
        }

        for offer in offers where offer.kind == .offerCode {
            try Task.checkCancellation()
            var offerCodeID = heldIDs[offer.id]
            if offerCodeID == nil {
                var attributes: [String: Any] = ["name": offer.id,
                                                 "customerEligibilities": ["NEW"]]
                if let eligibility = offer.eligibility {
                    attributes["customerEligibilities"] = [Self.appleEligibility(eligibility)]
                }
                if let duration = offer.duration,
                   let period = AppleDurations.offerDuration(for: duration) {
                    attributes["duration"] = period
                }
                attributes["offerMode"] = offer.price == nil ? "FREE" : "PAY_UP_FRONT"
                attributes["numberOfPeriods"] = offer.periods ?? 1
                let created = JSON(data: try await api.apple(
                    "POST", "/v1/inAppPurchaseOfferCodes", body: [
                        "data": [
                            "type": "inAppPurchaseOfferCodes",
                            "attributes": attributes,
                            "relationships": [
                                "inAppPurchaseV2": ["data": ["type": "inAppPurchases",
                                                             "id": purchaseID]],
                            ],
                        ],
                    ]).data)
                offerCodeID = created["data"]["id"].string
            }
            guard let offerCodeID else { continue }
            try await appleOfferCodeValues(offer, offerCodeID: offerCodeID, family: .purchase)
        }
    }

    static func appleEligibility(_ value: Manifest.Offer.Eligibility) -> String {
        switch value {
        case .new: "NEW"
        case .existing: "EXISTING"
        case .winBack: "EXPIRED"
        }
    }

    /// Ends the preorder, which puts the app on sale in every territory that
    /// holds one.
    ///
    /// **This reaches customers.** Everybody who pre-ordered is charged and
    /// the download starts. No call takes it back, so this only runs from a
    /// plan step that the developer read and acknowledged.
    func appleEndPreOrder() async throws {
        try await api.apple("POST", "/v1/endAppAvailabilityPreOrders", body: [
            "data": [
                "type": "endAppAvailabilityPreOrders",
                "relationships": ["app": ["data": ["type": "apps", "id": appleAppID]]],
            ],
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
        // An unanswered question is not the answer "no". Every other field
        // here goes through `put`, which skips nil and keeps the store's copy.
        put(&attributes, "demoAccountRequired", review.demoAccountRequired)
        if review.demoAccountRequired == true, let account = reviewerCredential {
            put(&attributes, "demoAccountName", account.username)
            put(&attributes, "demoAccountPassword", account.password)
        }

        // Apple gives every version a review detail, and copies one onto a
        // version this run created. The id from the read belongs to whatever
        // version the read saw, which on a first apply is no version at all,
        // and a retry starts at the failed step so it never creates one either.
        // A POST against a version that already carries a detail is a 409, and
        // it stopped the whole apply one step short of the submit.
        var detailID = actual.apple?.reviewDetailId
        if detailID == nil, let response = try? await api.apple(
            "GET", "/v1/appStoreVersions/\(versionID)/appStoreReviewDetail") {
            detailID = JSON(data: response.data)["data"]["id"].string
        }

        if let id = detailID {
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

    /// Writes only the age rating answers that differ from the store, and only
    /// the fields the store read returned.
    ///
    /// Everything the manifest does not name keeps whatever App Store Connect
    /// already holds. An app that is only shipping new release notes writes
    /// nothing here.
    func appleAgeRating() async throws {
        guard let id = actual.apple?.ageRatingDeclarationId else { return }
        let changes = Planner.appleAgeRatingChanges(manifest.review, actual.apple)
        var attributes: [String: Any] = changes.write.mapValues(\.body)
        if let band = manifest.review?.kidsAgeBand, !band.isEmpty,
           AgeRatingAnswer.text(band) != actual.apple?.ageRating["kidsAgeBand"] {
            attributes["kidsAgeBand"] = band
        }
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
            "GET", "/v2/inAppPurchases/\(purchaseID)/versions?limit=50").data)
        let heldVersions = versions["data"].array
        var purchaseVersionID = AppleVersionSelection.editable(heldVersions)?["id"].string
        if purchaseVersionID == nil,
           let current = AppleVersionSelection.preferred(heldVersions),
           AppleVersionSelection.blocksEdits(current),
           purchase.locales?.isEmpty == false {
            throw ConnectionError.http(
                409, "The in-app purchase \(purchase.id) has metadata in review and cannot be edited.")
        }
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
        // A purchase that names no locale manages none, so the drop below never
        // runs against an empty wanted set. It deletes every localization Apple
        // does not find in the manifest, and an absent `locales` key meant "all
        // of them": the apply stripped the names off products the developer
        // never asked it to touch, and Apple takes no purchase with no name.
        if let purchaseVersionID, purchase.locales?.isEmpty == false {
            let existing = JSON(data: try await api.apple(
                "GET", "/v1/inAppPurchaseVersions/\(purchaseVersionID)"
                    + "/localizations?limit=200").data)
            for item in existing["data"].array {
                if let locale = item["attributes"]["locale"].string,
                   let id = item["id"].string { localizationIDs[locale] = id }
            }
            try await appleDropLocalizations(
                existing, keeping: Set((purchase.locales ?? [:]).keys),
                path: "/v2/inAppPurchaseLocalizations")
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
                        "relationships": ["version": [
                            "data": ["type": "inAppPurchaseVersions",
                                     "id": purchaseVersionID]]],
                    ],
                ])
            }
        }
        if let price = purchase.price {
            let territory = price.territory ?? "USA"
            let points = try await ApplePricePoints.all(
                api, path: "/v2/inAppPurchases/\(purchaseID)/pricePoints"
                    + "?filter%5Bterritory%5D=\(territory)")
            if let point = ApplePricePoints.nearest(points, to: price.amount)?.id {
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
        if let promoted = purchase.promotedPurchase {
            try await applePromotedPurchase(promoted, purchaseID: purchaseID)
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
        try await appleProductImage(purchase.promotionalImage,
                                    productID: purchaseID, family: .purchase)
        // `purchase.content` writes nothing. Apple publishes a read for
        // `inAppPurchaseContents` and no create, so the hosted content upload
        // left the API. The validator names the key, so a silent skip here
        // never looks like a successful upload.
    }

    /// The promotion of one purchase, in both directions.
    ///
    /// `true` creates the promotion and `false` removes it. A missing key in
    /// the manifest never reaches this call, so an unmanaged promotion stays
    /// exactly as the developer left it in App Store Connect.
    ///
    /// Apple answers 404 for a purchase it never promoted, which is a state and
    /// not a failure.
    func applePromotedPurchase(_ wanted: Bool, purchaseID: String) async throws {
        let existing = try? await api.apple(
            "GET", "/v2/inAppPurchases/\(purchaseID)/promotedPurchase")
        let currentID = existing.flatMap { JSON(data: $0.data)["data"]["id"].string }

        switch (wanted, currentID) {
        case (true, .none):
            try await api.apple("POST", "/v1/promotedPurchases", body: [
                "data": ["type": "promotedPurchases",
                         "attributes": ["visibleForAllUsers": true],
                         "relationships": [
                            "app": ["data": ["type": "apps", "id": appleAppID]],
                            "inAppPurchaseV2": ["data": ["type": "inAppPurchases",
                                                           "id": purchaseID]],
                         ]],
            ])
        case (false, .some(let id)):
            try await api.apple("DELETE", "/v1/promotedPurchases/\(id)")
        case (true, .some), (false, .none):
            break
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

    /// The territories the app sells in, and whether a new one is added on its
    /// own.
    ///
    /// Three resources, because App Store Connect splits this three ways and
    /// answers an error for every route but the right one:
    ///
    /// - `POST /v2/appAvailabilities` creates the record, and only when the app
    ///   holds none. A second create answers 409 "already exists".
    /// - `PATCH /v2/appAvailabilities/{id}` does not exist. It answers 403 and
    ///   "Allowed operations are: CREATE, GET_INSTANCE", which this app read as
    ///   a role its key was denied and reported as one.
    /// - `PATCH /v1/territoryAvailabilities/{id}` is how an existing record
    ///   changes, one territory at a time.
    /// - `availableInNewTerritories` is an attribute of the create, and after
    ///   that it lives on the app: `PATCH /v1/apps/{id}` carries it.
    func appleAvailability() async throws {
        let requested = manifest.pricing?.territories ?? []
        // What the app holds now decides the route, and a stale answer here
        // sends the run down the branch that errors, so it is read fresh.
        let held = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appleAppID)/appAvailabilityV2").data)
        if let availabilityID = held["data"]["id"].string {
            try await appleUpdateTerritories(availabilityID: availabilityID,
                                             requested: requested)
            try await appleAvailableInNewTerritories()
            return
        }

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
        let data: [String: Any] = [
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
        // The app holds no availability, so the create carries the whole set,
        // `availableInNewTerritories` included.
        try await api.apple("POST", "/v2/appAvailabilities",
                            body: ["data": data, "included": included])
    }

    /// One PATCH per territory whose answer differs, and none for the rest.
    ///
    /// The whole set is written one territory at a time because that is the
    /// only route Apple offers for a record that already exists. An app on sale
    /// in every country holds 175 of these, so a run that sent them all would
    /// spend minutes writing the values the store already had.
    private func appleUpdateTerritories(
        availabilityID: String,
        requested: [Manifest.TerritoryAvailability]) async throws {
        guard !requested.isEmpty else { return }
        var held: [String: JSON] = [:]
        var path: String? = "/v2/appAvailabilities/\(availabilityID)"
            + "/territoryAvailabilities?limit=200"
        var pages = 0
        var seen: Set<String> = []
        while let current = path, pages < 20, seen.insert(current).inserted {
            pages += 1
            let page = JSON(data: try await api.apple("GET", current).data)
            for item in page["data"].array {
                guard let territory = item["relationships"]["territory"]["data"]["id"].string
                else { continue }
                held[territory] = item
            }
            path = page["links"]["next"].string.flatMap(UploadService.appleNextPagePath)
        }

        // A territory the store does not list is named rather than skipped. A
        // run that reports success and left a country out is the one outcome
        // this panel cannot recover from, because nothing says to look.
        var unknown: [String] = []
        for item in requested {
            guard let current = held[item.territory] else {
                unknown.append(item.territory)
                continue
            }
            let attributes = current["attributes"]
            var wanted: [String: Any] = [:]
            if attributes["available"].bool != item.available {
                wanted["available"] = item.available
            }
            if let preorder = item.preOrderEnabled,
               attributes["preOrderEnabled"].bool != preorder {
                wanted["preOrderEnabled"] = preorder
            }
            if let date = item.releaseDate, attributes["releaseDate"].string != date {
                wanted["releaseDate"] = date
            }
            guard !wanted.isEmpty, let id = current["id"].string else { continue }
            try await api.apple("PATCH", "/v1/territoryAvailabilities/\(id)", body: [
                "data": ["type": "territoryAvailabilities", "id": id,
                         "attributes": wanted],
            ])
        }
        guard unknown.isEmpty else { throw RunError.unknownTerritories(unknown.sorted()) }
    }

    /// Whether the App Store adds this app to a territory it opens later.
    ///
    /// It is an attribute of the app, not of the availability, once the
    /// availability exists. Skipped when the store already agrees, so a run
    /// that changes only a territory does not also write this.
    private func appleAvailableInNewTerritories() async throws {
        guard let wanted = manifest.pricing?.autoConvertOtherTerritories,
              wanted != actual.apple?.availableInNewTerritories else { return }
        try await api.apple("PATCH", "/v1/apps/\(appleAppID)", body: [
            "data": ["type": "apps", "id": appleAppID,
                     "attributes": ["availableInNewTerritories": wanted]],
        ])
    }

    func appleAppPrice() async throws {
        guard let price = manifest.pricing?.base else { return }
        let territory = price.territory ?? "USA"
        let points = try await ApplePricePoints.app(api, appID: appleAppID,
                                                    territory: territory)
        guard let point = ApplePricePoints.nearest(points, to: price.amount)?.id else { return }
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

    /// The same, for the optional flags and codes that a declaration carries.
    /// A nil answer is not an answer, so it never reaches the store.
    func put(_ attributes: inout [String: Any], _ key: String, _ value: Bool?) {
        guard let value else { return }
        attributes[key] = value
    }

    func put(_ attributes: inout [String: Any], _ key: String, _ value: String?) {
        guard let value, !value.isEmpty else { return }
        attributes[key] = value
    }

    /// Replaces the preview sets of a device class the manifest fills.
    ///
    /// The planner emits no upload step for a device class whose preview type
    /// changed, so nothing else visits the set it left. This runs from the
    /// locale writer, which every managed locale reaches on every apply.
    ///
    /// It used to clear the screenshots too, of any locale that named none at
    /// all. That is a locale the developer gave this app nothing for, and the
    /// Media tab promises such a locale keeps what the store shows, so the
    /// apply took down published screenshots that it had never been handed a
    /// replacement for. `appleScreenshots` clears a class the manifest fills,
    /// where the resolved buckets are in hand, and that is the only clearing
    /// screenshots get.
    func appleDropEmptyMediaSets(_ locale: String) async throws {
        guard let localizationID = appleVersionLocalizationIDs[locale] else { return }

        var previewTypes: Set<String> = []
        for deviceClass in Manifest.DeviceClass.allCases {
            if !manifest.mediaPaths(locale: locale, deviceClass: deviceClass,
                                    previews: true).isEmpty,
               let type = AssetInspector.applePreviewType(for: deviceClass) {
                previewTypes.insert(type)
            }
        }

        try await appleDropMediaSets(
            localizationID: localizationID, collection: "appPreviewSets",
            typeKey: "previewType", path: "/v1/appPreviewSets", keeping: previewTypes,
            replacing: appleFilledDeviceClasses(locale: locale, previews: true))
    }

    /// One removal, both set kinds. Apple deletes the screenshots or the
    /// previews with the set, so this needs no second pass over the children.
    ///
    /// `replacing` is the whole safety of this call: only a device class the
    /// manifest fills can lose anything. Without it the keep list was the
    /// buckets the manifest named and nothing else, so a run deleted every set
    /// of every class the developer had not filled, and a locale that named no
    /// picture at all deleted the lot. That is the opposite of what the Media
    /// tab tells the developer twice, and it took down screenshots that were
    /// published and were never this app's to remove.
    func appleDropMediaSets(localizationID: String, collection: String, typeKey: String,
                            path: String, keeping wanted: Set<String>,
                            replacing filled: Set<Manifest.DeviceClass>) async throws {
        guard !filled.isEmpty else { return }
        guard let response = try? await api.apple(
            "GET", "/v1/appStoreVersionLocalizations/\(localizationID)/\(collection)?limit=50")
        else { return }
        for item in JSON(data: response.data)["data"].array {
            guard let id = item["id"].string,
                  let type = item["attributes"][typeKey].string,
                  !wanted.contains(type) else { continue }
            // A display type this build cannot place belongs to no class the
            // manifest can have filled, so it stays. Guessing costs pictures.
            guard let device = AssetInspector.deviceClass(forAppleDisplayType: type),
                  filled.contains(device) else { continue }
            try await api.apple("DELETE", "\(path)/\(id)")
        }
    }

    /// Removes every localization whose locale the manifest dropped.
    ///
    /// Rule 3 of section 5.1 says a missing value means "do not manage this
    /// field". A locale is not a field. A developer who removes a locale from
    /// the manifest means it, and without this the store keeps selling the old
    /// text forever.
    ///
    /// The caller passes the payload it already read, so this costs no request
    /// when nothing is stale.
    ///
    /// `// ponytail: one reconciler, three resources. The App Store spells the
    /// // path differently for each one and the rule is identical.`
    func appleDropLocalizations(_ held: JSON, keeping wanted: Set<String>,
                                path: String) async throws {
        for item in held["data"].array {
            guard let locale = item["attributes"]["locale"].string,
                  let id = item["id"].string, !wanted.contains(locale) else { continue }
            try await api.apple("DELETE", "\(path)/\(id)")
        }
    }
}
