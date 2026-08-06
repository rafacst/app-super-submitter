import Foundation

/// The App Store resources that shape how the store sells the app.
///
/// Google offers no equivalent for any of these, so nothing here has a
/// Google twin. Every write ends in a draft or in an unsubmitted state, the
/// same rule as the rest of the apply.
extension Runner {

    // MARK: - The custom product pages

    func appleCustomProductPages() async throws {
        let pages = manifest.marketing?.customProductPages ?? []
        guard !pages.isEmpty else { return }

        let existing = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appleAppID)/appCustomProductPages?limit=200").data)
        var byName: [String: String] = [:]
        for item in existing["data"].array {
            guard let name = item["attributes"]["name"].string,
                  let id = item["id"].string else { continue }
            byName[name] = id
        }

        for page in pages {
            try Task.checkCancellation()
            let pageID: String
            if let id = byName[page.key] {
                pageID = id
                try await api.apple("PATCH", "/v1/appCustomProductPages/\(id)", body: [
                    "data": ["type": "appCustomProductPages", "id": id,
                             "attributes": ["name": page.name,
                                            "visible": page.visible ?? true]],
                ])
            } else {
                let created = JSON(data: try await api.apple(
                    "POST", "/v1/appCustomProductPages", body: [
                        "data": [
                            "type": "appCustomProductPages",
                            "attributes": ["name": page.key, "visible": page.visible ?? true],
                            "relationships": ["app": [
                                "data": ["type": "apps", "id": appleAppID]]],
                        ],
                    ]).data)
                guard let id = created["data"]["id"].string else { continue }
                pageID = id
            }

            try await appleCustomProductPageLocales(page, pageID: pageID)
        }
    }

    /// A page holds versions, and a version holds the localizations. The app
    /// writes the newest version and creates one when the page has none.
    private func appleCustomProductPageLocales(
        _ page: Manifest.Marketing.CustomProductPage, pageID: String) async throws {
        guard let locales = page.locales, !locales.isEmpty else { return }

        let versions = JSON(data: try await api.apple(
            "GET",
            "/v1/appCustomProductPages/\(pageID)/appCustomProductPageVersions?limit=200").data)
        var versionID = versions["data"].array.first?["id"].string
        if versionID == nil {
            let created = JSON(data: try await api.apple(
                "POST", "/v1/appCustomProductPageVersions", body: [
                    "data": [
                        "type": "appCustomProductPageVersions",
                        "relationships": ["appCustomProductPage": [
                            "data": ["type": "appCustomProductPages", "id": pageID]]],
                    ],
                ]).data)
            versionID = created["data"]["id"].string
        }
        guard let versionID else { return }

        let existing = JSON(data: try await api.apple(
            "GET",
            "/v1/appCustomProductPageVersions/\(versionID)/appCustomProductPageLocalizations?limit=200").data)
        let byLocale = existing.idsByLocale

        for (locale, text) in locales.sorted(by: { $0.key < $1.key }) {
            var attributes: [String: Any] = [:]
            put(&attributes, "promotionalText", text.promotionalText ?? "")
            var localizationID: String?
            if let id = byLocale[locale] {
                localizationID = id
                try await api.apple(
                    "PATCH", "/v1/appCustomProductPageLocalizations/\(id)", body: [
                        "data": ["type": "appCustomProductPageLocalizations", "id": id,
                                 "attributes": attributes],
                    ])
            } else {
                attributes["locale"] = locale
                let created = JSON(data: try await api.apple(
                    "POST", "/v1/appCustomProductPageLocalizations", body: [
                        "data": [
                            "type": "appCustomProductPageLocalizations",
                            "attributes": attributes,
                            "relationships": ["appCustomProductPageVersion": [
                                "data": ["type": "appCustomProductPageVersions",
                                         "id": versionID]]],
                        ],
                    ]).data)
                localizationID = created["data"]["id"].string
            }
            if let localizationID {
                for (device, paths) in text.screenshots ?? [:] {
                    try await appleMarketingScreenshots(
                        paths, device: device,
                        relationship: "appCustomProductPageLocalization",
                        relationshipType: "appCustomProductPageLocalizations",
                        relationshipID: localizationID)
                }
            }
        }
    }

    // MARK: - The product page experiments

    /// The app creates the experiment and its treatments, and it never starts
    /// one. A running experiment changes what a real customer sees, and
    /// section 7.9 keeps that decision on a button.
    func appleExperiments() async throws {
        let experiments = manifest.marketing?.experiments ?? []
        guard !experiments.isEmpty else { return }

        let existing = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appleAppID)/appStoreVersionExperimentsV2?limit=200").data)
        var byName: [String: String] = [:]
        for item in existing["data"].array {
            guard let name = item["attributes"]["name"].string,
                  let id = item["id"].string else { continue }
            byName[name] = id
        }

        for experiment in experiments {
            try Task.checkCancellation()
            let experimentID: String
            if let id = byName[experiment.key] {
                experimentID = id
                try await api.apple("PATCH", "/v2/appStoreVersionExperiments/\(id)", body: [
                    "data": ["type": "appStoreVersionExperiments", "id": id,
                             "attributes": [
                                 "name": experiment.name,
                                 "trafficProportion": experiment.trafficProportion ?? 50,
                             ]],
                ])
            } else {
                let created = JSON(data: try await api.apple(
                    "POST", "/v2/appStoreVersionExperiments", body: [
                        "data": [
                            "type": "appStoreVersionExperiments",
                            "attributes": [
                                "name": experiment.key,
                                "trafficProportion": experiment.trafficProportion ?? 50,
                                "platform": experiment.platform?.rawValue ?? applePlatform,
                            ],
                            "relationships": ["app": [
                                "data": ["type": "apps", "id": appleAppID]]],
                        ],
                    ]).data)
                guard let id = created["data"]["id"].string else { continue }
                experimentID = id
            }

            let treatments = JSON(data: try await api.apple(
                "GET",
                "/v2/appStoreVersionExperiments/\(experimentID)/appStoreVersionExperimentTreatments?limit=200").data)
            var known: [String: String] = [:]
            for item in treatments["data"].array {
                if let name = item["attributes"]["name"].string,
                   let id = item["id"].string { known[name] = id }
            }
            for treatment in experiment.treatments {
                var treatmentID = known[treatment.key]
                if treatmentID == nil {
                    let created = JSON(data: try await api.apple(
                        "POST", "/v1/appStoreVersionExperimentTreatments", body: [
                            "data": [
                                "type": "appStoreVersionExperimentTreatments",
                                "attributes": ["name": treatment.key,
                                               "appIconName": NSNull()],
                                "relationships": ["appStoreVersionExperiment": [
                                    "data": ["type": "appStoreVersionExperiments",
                                             "id": experimentID]]],
                            ],
                        ]).data)
                    treatmentID = created["data"]["id"].string
                }
                guard let treatmentID else { continue }
                let existingLocales = JSON(data: try await api.apple(
                    "GET", "/v1/appStoreVersionExperimentTreatments/\(treatmentID)"
                        + "/appStoreVersionExperimentTreatmentLocalizations?limit=50").data)
                var localized: [String: String] = [:]
                for item in existingLocales["data"].array {
                    if let locale = item["attributes"]["locale"].string,
                       let id = item["id"].string { localized[locale] = id }
                }
                for (locale, devices) in treatment.screenshots ?? [:] {
                    var localizationID = localized[locale]
                    if localizationID == nil {
                        let created = JSON(data: try await api.apple(
                            "POST", "/v1/appStoreVersionExperimentTreatmentLocalizations",
                            body: [
                                "data": [
                                    "type": "appStoreVersionExperimentTreatmentLocalizations",
                                    "attributes": ["locale": locale],
                                    "relationships": ["appStoreVersionExperimentTreatment": [
                                        "data": ["type": "appStoreVersionExperimentTreatments",
                                                 "id": treatmentID]]],
                                ],
                            ]).data)
                        localizationID = created["data"]["id"].string
                    }
                    guard let localizationID else { continue }
                    for (device, paths) in devices {
                        try await appleMarketingScreenshots(
                            paths, device: device,
                            relationship: "appStoreVersionExperimentTreatmentLocalization",
                            relationshipType: "appStoreVersionExperimentTreatmentLocalizations",
                            relationshipID: localizationID)
                    }
                }
            }
        }
    }

    // MARK: - The in-app events

    func appleAppEvents() async throws {
        let events = manifest.marketing?.events ?? []
        guard !events.isEmpty else { return }

        let existing = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appleAppID)/appEvents?limit=200").data)
        var byName: [String: String] = [:]
        for item in existing["data"].array {
            guard let name = item["attributes"]["referenceName"].string,
                  let id = item["id"].string else { continue }
            byName[name] = id
        }

        for event in events {
            try Task.checkCancellation()
            var attributes: [String: Any] = ["referenceName": event.key]
            put(&attributes, "badge", event.badge ?? "")
            put(&attributes, "priority", event.priority ?? "")
            put(&attributes, "purpose", event.purpose ?? "")

            let eventID: String
            if let id = byName[event.key] {
                eventID = id
                try await api.apple("PATCH", "/v1/appEvents/\(id)", body: [
                    "data": ["type": "appEvents", "id": id, "attributes": attributes],
                ])
            } else {
                let created = JSON(data: try await api.apple("POST", "/v1/appEvents", body: [
                    "data": [
                        "type": "appEvents",
                        "attributes": attributes,
                        "relationships": ["app": ["data": ["type": "apps", "id": appleAppID]]],
                    ],
                ]).data)
                guard let id = created["data"]["id"].string else { continue }
                eventID = id
            }

            try await appleEventLocales(event, eventID: eventID)
        }
    }

    private func appleEventLocales(_ event: Manifest.Marketing.AppEvent,
                                   eventID: String) async throws {
        guard let locales = event.locales, !locales.isEmpty else { return }
        let existing = JSON(data: try await api.apple(
            "GET", "/v1/appEvents/\(eventID)/localizations?limit=200").data)
        let byLocale = existing.idsByLocale

        for (locale, text) in locales.sorted(by: { $0.key < $1.key }) {
            var attributes: [String: Any] = [:]
            put(&attributes, "name", text.name ?? "")
            put(&attributes, "shortDescription", text.shortDescription ?? "")
            put(&attributes, "longDescription", text.longDescription ?? "")
            var localizationID: String?
            if let id = byLocale[locale] {
                localizationID = id
                try await api.apple("PATCH", "/v1/appEventLocalizations/\(id)", body: [
                    "data": ["type": "appEventLocalizations", "id": id,
                             "attributes": attributes],
                ])
            } else {
                attributes["locale"] = locale
                let created = JSON(data: try await api.apple(
                    "POST", "/v1/appEventLocalizations", body: [
                        "data": [
                            "type": "appEventLocalizations",
                            "attributes": attributes,
                            "relationships": ["appEvent": [
                                "data": ["type": "appEvents", "id": eventID]]],
                        ],
                    ]).data)
                localizationID = created["data"]["id"].string
            }
            if let localizationID {
                for (kind, screenshots) in text.screenshots ?? [:] {
                    try await appleEventScreenshots(
                        screenshots, assetType: Self.appleEventAssetType(kind),
                        localizationID: localizationID)
                }
                for (kind, clip) in (text.videoClips ?? [:]).sorted(by: { $0.key < $1.key }) {
                    try await appleEventVideoClip(
                        clip, assetType: Self.appleEventAssetType(kind),
                        localizationID: localizationID)
                }
            }
        }
    }

    // MARK: - The licence agreement

    func appleEULA() async throws {
        guard let eula = manifest.marketing?.eula, !eula.text.isEmpty else { return }
        let territories = (eula.territories ?? []).filter { !$0.isEmpty }
        let relationships: [String: Any] = territories.isEmpty
            ? ["app": ["data": ["type": "apps", "id": appleAppID]]]
            : ["app": ["data": ["type": "apps", "id": appleAppID]],
               "territories": ["data": territories.map {
                   ["type": "territories", "id": $0]
               }]]

        let existing = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appleAppID)/endUserLicenseAgreement").data)
        if let id = existing["data"]["id"].string {
            try await api.apple("PATCH", "/v1/endUserLicenseAgreements/\(id)", body: [
                "data": ["type": "endUserLicenseAgreements", "id": id,
                         "attributes": ["agreementText": eula.text],
                         "relationships": territories.isEmpty ? [:] : [
                             "territories": ["data": territories.map {
                                 ["type": "territories", "id": $0]
                             }]]],
            ])
            return
        }
        try await api.apple("POST", "/v1/endUserLicenseAgreements", body: [
            "data": [
                "type": "endUserLicenseAgreements",
                "attributes": ["agreementText": eula.text],
                "relationships": relationships,
            ],
        ])
    }

    // MARK: - The routing app coverage

    /// A GeoJSON file. Apple reserves it and takes the bytes through the
    /// same `uploadOperations` list as a screenshot, so this reuses that path.
    func appleRoutingCoverage(path: String, index: Int) async throws {
        guard let versionID = appleVersionID else { throw RunError.missingVersion }
        guard let url = resolve(path) else { throw RunError.missingBuild }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)

        // One coverage file per version. A second reservation replaces it.
        let existing = JSON(data: try await api.apple(
            "GET", "/v1/appStoreVersions/\(versionID)/routingAppCoverage").data)
        if let id = existing["data"]["id"].string {
            _ = try? await api.apple("DELETE", "/v1/routingAppCoverages/\(id)")
        }

        let reservation = JSON(data: try await api.apple("POST", "/v1/routingAppCoverages", body: [
            "data": [
                "type": "routingAppCoverages",
                "attributes": ["fileName": url.lastPathComponent, "fileSize": data.count],
                "relationships": ["appStoreVersion": [
                    "data": ["type": "appStoreVersions", "id": versionID]]],
            ],
        ]).data)
        guard let coverageID = reservation["data"]["id"].string else {
            throw RunError.uploadFailed(url.lastPathComponent)
        }
        try await executeUploadOperations(reservation["data"]["attributes"]["uploadOperations"],
                                           data: data)
        try await api.apple("PATCH", "/v1/routingAppCoverages/\(coverageID)", body: [
            "data": ["type": "routingAppCoverages", "id": coverageID,
                     "attributes": ["uploaded": true,
                                    "sourceFileChecksum": Checksums.md5(data)]],
        ])
        report(index: index, fraction: 1, detail: url.lastPathComponent)
    }

    // MARK: - The nomination

    /// A request to the editorial team. The app creates it as a draft and
    /// never submits it, the same rule as every other write.
    func appleNomination() async throws {
        guard let nomination = manifest.marketing?.nomination else { return }
        let existing = JSON(data: try await api.apple("GET", "/v1/nominations?limit=200").data)
        if let id = existing["data"].array.first(where: {
            $0["attributes"]["name"].string == nomination.name
        })?["id"].string {
            var attributes: [String: Any] = ["name": nomination.name]
            put(&attributes, "description", nomination.description ?? "")
            try await api.apple("PATCH", "/v1/nominations/\(id)", body: [
                "data": ["type": "nominations", "id": id, "attributes": attributes],
            ])
            return
        }

        var attributes: [String: Any] = [
            "name": nomination.name,
            "type": nomination.type,
        ]
        put(&attributes, "description", nomination.description ?? "")
        put(&attributes, "publishStartDate", nomination.publishStartDate ?? "")
        put(&attributes, "publishEndDate", nomination.publishEndDate ?? "")
        try await api.apple("POST", "/v1/nominations", body: [
            "data": [
                "type": "nominations",
                "attributes": attributes,
                "relationships": ["relatedApps": [
                    "data": [["type": "apps", "id": appleAppID]]]],
            ],
        ])
    }

    // MARK: - The accessibility declaration

    func appleAccessibility() async throws {
        guard let accessibility = manifest.marketing?.accessibility,
              !accessibility.supports.isEmpty else { return }
        var attributes: [String: Any] = ["state": "DRAFT"]
        for feature in accessibility.supports {
            attributes[Self.accessibilityKey(feature)] = true
        }

        let existing = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appleAppID)/accessibilityDeclarations?limit=200").data)
        if let id = existing["data"].array.first?["id"].string {
            try await api.apple("PATCH", "/v1/accessibilityDeclarations/\(id)", body: [
                "data": ["type": "accessibilityDeclarations", "id": id,
                         "attributes": attributes],
            ])
            return
        }
        try await api.apple("POST", "/v1/accessibilityDeclarations", body: [
            "data": [
                "type": "accessibilityDeclarations",
                "attributes": attributes,
                "relationships": ["app": ["data": ["type": "apps", "id": appleAppID]]],
            ],
        ])
    }

    /// `VOICE_OVER` becomes `supportsVoiceOver`. Apple names one attribute
    /// per feature, and the manifest names the feature.
    static func accessibilityKey(_ feature: String) -> String {
        let words = feature.split(separator: "_").map { $0.lowercased() }
        let camel = words.enumerated().map { index, word in
            index == 0 ? word : word.prefix(1).uppercased() + word.dropFirst()
        }.joined()
        return "supports" + camel.prefix(1).uppercased() + camel.dropFirst()
    }

    // MARK: - The App Clip

    /// The default experience of the first App Clip that the app holds. The
    /// Xcode target creates the clip; this writes what the store shows.
    func appleAppClip() async throws {
        guard let clip = manifest.marketing?.appClip else { return }
        guard let versionID = appleVersionID else { throw RunError.missingVersion }

        let clips = JSON(data: try await api.apple(
            "GET", "/v1/apps/\(appleAppID)/appClips?limit=1").data)
        guard let clipID = clips["data"].array.first?["id"].string else { return }

        let experiences = JSON(data: try await api.apple(
            "GET", "/v1/appClips/\(clipID)/appClipDefaultExperiences?limit=200").data)
        let experienceID: String
        if let id = experiences["data"].array.first?["id"].string {
            experienceID = id
            if let action = clip.action, !action.isEmpty {
                try await api.apple("PATCH", "/v1/appClipDefaultExperiences/\(id)", body: [
                    "data": ["type": "appClipDefaultExperiences", "id": id,
                             "attributes": ["action": action]],
                ])
            }
        } else {
            var attributes: [String: Any] = [:]
            put(&attributes, "action", clip.action ?? "")
            let created = JSON(data: try await api.apple(
                "POST", "/v1/appClipDefaultExperiences", body: [
                    "data": [
                        "type": "appClipDefaultExperiences",
                        "attributes": attributes,
                        "relationships": [
                            "appClip": ["data": ["type": "appClips", "id": clipID]],
                            "releaseWithAppStoreVersion": [
                                "data": ["type": "appStoreVersions", "id": versionID]],
                        ],
                    ],
                ]).data)
            guard let id = created["data"]["id"].string else { return }
            experienceID = id
        }

        for advanced in clip.advancedExperiences ?? [] {
            var attributes: [String: Any] = ["action": advanced.action]
            put(&attributes, "businessCategory", advanced.businessCategory ?? "")
            put(&attributes, "defaultLanguage", advanced.defaultLanguage ?? "")
            put(&attributes, "link", advanced.link ?? "")
            try await api.apple("POST", "/v1/appClipAdvancedExperiences", body: [
                "data": [
                    "type": "appClipAdvancedExperiences",
                    "attributes": attributes,
                    "relationships": ["appClip": [
                        "data": ["type": "appClips", "id": clipID]]],
                ],
            ])
        }

        guard let locales = clip.locales, !locales.isEmpty else { return }
        let existing = JSON(data: try await api.apple(
            "GET",
            "/v1/appClipDefaultExperiences/\(experienceID)/appClipDefaultExperienceLocalizations?limit=200").data)
        let byLocale = existing.idsByLocale

        for (locale, text) in locales.sorted(by: { $0.key < $1.key }) {
            var attributes: [String: Any] = [:]
            put(&attributes, "subtitle", text.subtitle ?? "")
            put(&attributes, "title", text.title ?? "")
            guard !attributes.isEmpty else { continue }
            if let id = byLocale[locale] {
                try await api.apple(
                    "PATCH", "/v1/appClipDefaultExperienceLocalizations/\(id)", body: [
                        "data": ["type": "appClipDefaultExperienceLocalizations", "id": id,
                                 "attributes": attributes],
                    ])
                continue
            }
            attributes["locale"] = locale
            try await api.apple("POST", "/v1/appClipDefaultExperienceLocalizations", body: [
                "data": [
                    "type": "appClipDefaultExperienceLocalizations",
                    "attributes": attributes,
                    "relationships": ["appClipDefaultExperience": [
                        "data": ["type": "appClipDefaultExperiences", "id": experienceID]]],
                ],
            ])
        }
    }

    // MARK: - Marketing Screenshots

    private func appleMarketingScreenshots(
        _ paths: [String], device: String, relationship: String,
        relationshipType: String, relationshipID: String) async throws {
        guard let deviceClass = Manifest.DeviceClass(rawValue: device) else { return }
        for path in paths {
            guard let url = resolve(path),
                  let info = try? AssetInspector.image(at: url),
                  let displayType = try AssetInspector.appleDisplayType(
                    for: info, deviceClass: deviceClass) else { continue }
            let set = JSON(data: try await api.apple("POST", "/v1/appScreenshotSets", body: [
                "data": [
                    "type": "appScreenshotSets",
                    "attributes": ["screenshotDisplayType": displayType],
                    "relationships": [relationship: [
                        "data": ["type": relationshipType, "id": relationshipID]]],
                ],
            ]).data)
            guard let setID = set["data"]["id"].string else { continue }
            try await appleUploadMarketingScreenshot(url, setID: setID)
        }
    }

    private func appleUploadMarketingScreenshot(_ url: URL, setID: String) async throws {
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let reservation = JSON(data: try await api.apple("POST", "/v1/appScreenshots", body: [
            "data": [
                "type": "appScreenshots",
                "attributes": ["fileName": url.lastPathComponent, "fileSize": data.count],
                "relationships": ["appScreenshotSet": [
                    "data": ["type": "appScreenshotSets", "id": setID]]],
            ],
        ]).data)
        guard let id = reservation["data"]["id"].string else { return }
        try await executeUploadOperations(
            reservation["data"]["attributes"]["uploadOperations"], data: data)
        try await api.apple("PATCH", "/v1/appScreenshots/\(id)", body: [
            "data": ["type": "appScreenshots", "id": id,
                     "attributes": ["uploaded": true,
                                    "sourceFileChecksum": Checksums.md5(data)]],
        ])
    }

    /// `card` and `details` are what the manifest writes. Apple names the two
    /// asset types, and a screenshot and a video clip share the pair.
    static func appleEventAssetType(_ kind: String) -> String {
        kind.lowercased() == "card" ? "EVENT_CARD" : "EVENT_DETAILS_PAGE"
    }

    /// The video clip of one app event asset type.
    ///
    /// Apple takes one clip for the card and one for the details page, so the
    /// manifest holds a path and not a list. The three calls are the
    /// reservation, the bytes, and the commit, exactly as the screenshot below
    /// does it.
    private func appleEventVideoClip(_ path: String, assetType: String,
                                     localizationID: String) async throws {
        guard let url = resolve(path) else { return }
        let data = try Data(contentsOf: url, options: .mappedIfSafe)
        let reservation = JSON(data: try await api.apple(
            "POST", "/v1/appEventVideoClips", body: [
                "data": [
                    "type": "appEventVideoClips",
                    "attributes": ["fileName": url.lastPathComponent,
                                   "appEventAssetType": assetType,
                                   "fileSize": data.count],
                    "relationships": ["appEventLocalization": [
                        "data": ["type": "appEventLocalizations",
                                 "id": localizationID]]],
                ],
            ]).data)
        guard let id = reservation["data"]["id"].string else { return }
        try await executeUploadOperations(
            reservation["data"]["attributes"]["uploadOperations"], data: data)
        try await api.apple("PATCH", "/v1/appEventVideoClips/\(id)", body: [
            "data": ["type": "appEventVideoClips", "id": id,
                     "attributes": ["uploaded": true]],
        ])
    }

    private func appleEventScreenshots(_ paths: [String], assetType: String,
                                       localizationID: String) async throws {
        for path in paths {
            guard let url = resolve(path) else { continue }
            let data = try Data(contentsOf: url, options: .mappedIfSafe)
            let reservation = JSON(data: try await api.apple(
                "POST", "/v1/appEventScreenshots", body: [
                    "data": [
                        "type": "appEventScreenshots",
                        "attributes": ["fileName": url.lastPathComponent,
                                       "appEventAssetType": assetType,
                                       "fileSize": data.count],
                        "relationships": ["appEventLocalization": [
                            "data": ["type": "appEventLocalizations",
                                     "id": localizationID]]],
                    ],
                ]).data)
            guard let id = reservation["data"]["id"].string else { continue }
            try await executeUploadOperations(
                reservation["data"]["attributes"]["uploadOperations"], data: data)
            try await api.apple("PATCH", "/v1/appEventScreenshots/\(id)", body: [
                "data": ["type": "appEventScreenshots", "id": id,
                         "attributes": ["uploaded": true]],
            ])
        }
    }
}
