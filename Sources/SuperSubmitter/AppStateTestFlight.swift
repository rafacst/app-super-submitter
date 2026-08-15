import SubmitKit
import SwiftUI

/// The TestFlight block of tab 2.
///
/// Every value here reaches a real person. An address in a group receives an
/// invitation, and the beta review is a queue. So no binding calls Apple: each
/// one writes `store.yaml`, and the plan on the Summary tab still decides what
/// the run sends. `AppleTestFlight.swift` is the other half.
extension AppState {

    var testFlight: Manifest.Release.TestFlight? {
        manifest.release?.apple?.testFlight
    }

    var betaGroups: [Manifest.Release.TestFlight.Group] { testFlight?.groups ?? [] }

    /// The selected TestFlight build platforms. A manifest from an older
    /// version keeps the first app platform until the developer changes it.
    var testFlightPlatforms: [Manifest.Platform] {
        let supported = testFlightPlatformChoices
        let selected = testFlight?.platforms?.filter(supported.contains) ?? []
        if !selected.isEmpty { return selected }
        if supported.contains(applePlatform) { return [applePlatform] }
        return supported.first.map { [$0] } ?? [applePlatform]
    }

    /// TestFlight supports more platforms, but this control answers the two
    /// build choices that one iOS and macOS app can hold under one app id.
    var testFlightPlatformChoices: [Manifest.Platform] {
        let supported = manifest.apps.apple?.platforms ?? []
        return [Manifest.Platform.ios, .macOS].filter(supported.contains)
    }

    func testFlightPlatformBinding(_ platform: Manifest.Platform) -> Binding<Bool> {
        Binding(get: {
            self.testFlightPlatforms.contains(platform)
        }, set: { selected in
            self.editTestFlight { block in
                var platforms = self.testFlightPlatforms
                if selected, !platforms.contains(platform) {
                    platforms.append(platform)
                } else if !selected, platforms.count > 1 {
                    platforms.removeAll { $0 == platform }
                }
                block.platforms = [Manifest.Platform.ios, .macOS].filter(platforms.contains)
            }
        })
    }

    func addTestFlight() {
        guard manifest.release?.apple?.testFlight == nil else { return }
        editTestFlight { _ in }
    }

    /// Drops the whole block. The plan then writes nothing to TestFlight, and
    /// the groups Apple already holds stay exactly as they are.
    func removeTestFlight() {
        manifest.release?.apple?.testFlight = nil
        saveManifestReportingErrors()
    }

    // MARK: - The groups

    func addBetaGroup() {
        editTestFlight { block in
            var groups = block.groups ?? []
            groups.append(.init(name: "Group \(groups.count + 1)"))
            block.groups = groups
        }
    }

    func removeBetaGroup(at index: Int) {
        editTestFlight { block in
            var groups = block.groups ?? []
            guard groups.indices.contains(index) else { return }
            groups.remove(at: index)
            block.groups = groups.isEmpty ? nil : groups
        }
    }

    enum BetaGroupField { case name, testers, publicLinkLimit }

    func betaGroupBinding(index: Int, field: BetaGroupField) -> Binding<String> {
        Binding(get: {
            guard let group = self.betaGroups[safe: index] else { return "" }
            return switch field {
            case .name: group.name
            case .testers: (group.testers ?? []).joined(separator: ", ")
            case .publicLinkLimit: group.publicLinkLimit.map(String.init) ?? ""
            }
        }, set: { value in
            self.editTestFlight { block in
                guard block.groups?.indices.contains(index) == true else { return }
                switch field {
                case .name:
                    block.groups?[index].name = value.trimmingCharacters(in: .whitespaces)
                case .testers:
                    // Apple matches an address case-insensitively and the plan
                    // compares against the lowercased list it read back, so a
                    // capital here is not a second invitation.
                    let list = Self.splitList(value)
                    block.groups?[index].testers = list.isEmpty ? nil : list
                case .publicLinkLimit:
                    block.groups?[index].publicLinkLimit = Int(value)
                }
            }
        })
    }

    // MARK: - The groups Apple already holds

    /// The groups on the App Store that this manifest does not name.
    ///
    /// The read has fetched every group of the app all along, with its testers
    /// and its switches, and nothing on this panel showed the ones the manifest
    /// was silent about. The list drew the manifest alone, so a group made in
    /// App Store Connect was invisible here and the obvious next move was to
    /// make it a second time.
    var unlistedBetaGroups: [AppleTestFlightClient.BetaGroup] {
        let named = Set(betaGroups.map { $0.name })
        return (actualState.apple?.betaGroups ?? [:]).values
            .filter { !named.contains($0.name) }
            .sorted { $0.name < $1.name }
    }

    /// Copies a group Apple holds into the manifest, with the switches and the
    /// testers it already carries.
    ///
    /// This writes `store.yaml` and calls nobody. The values match what the
    /// read returned, so the plan finds nothing to change and no address is
    /// invited a second time.
    func adoptBetaGroup(_ live: AppleTestFlightClient.BetaGroup) {
        editTestFlight { block in
            var groups = block.groups ?? []
            guard !groups.contains(where: { $0.name == live.name }) else { return }
            groups.append(.init(name: live.name,
                                testers: live.testers.isEmpty
                                    ? nil : live.testers.sorted(),
                                publicLink: live.publicLink,
                                publicLinkLimit: live.publicLinkLimit,
                                automaticBuilds: live.automaticBuilds,
                                internalGroup: live.internalGroup,
                                feedback: live.feedback,
                                iosBuildsOnMac: live.iosBuildsOnMac,
                                iosBuildsOnVision: live.iosBuildsOnVision))
            block.groups = groups
        }
    }

    // MARK: - Testers from a file

    /// Reads the addresses out of a CSV and adds them to a group.
    ///
    /// Nothing here reaches Apple. The addresses land in `store.yaml` beside
    /// the typed ones, exactly as the field beside the button writes them, and
    /// "Send to TestFlight" is still the only thing that invites anybody.
    func importTesters(index: Int) {
        guard let url = chooseOneFile(allowedExtensions: ["csv"]) else { return }
        do {
            let data = try Data(contentsOf: url)
            // A CSV out of Excel may be UTF-16. Anything else is UTF-8, or
            // close enough that the addresses survive the replacements: a
            // Latin-1 byte lands in a name column, and no name is imported.
            let text = String(data: data, encoding: .utf8)
                ?? String(data: data, encoding: .utf16)
                ?? String(decoding: data, as: UTF8.self)
            let found = Self.addresses(inCSV: text)
            guard !found.isEmpty else {
                errorMessage = "No email address in \(url.lastPathComponent)."
                return
            }
            addTesters(found, index: index)
        } catch {
            errorMessage = "\(url.lastPathComponent) could not be read."
        }
    }

    /// Adds addresses to a group and keeps the ones already there.
    ///
    /// Apple matches an address case-insensitively, so the same file imported
    /// twice adds nobody the second time and no address is invited twice.
    func addTesters(_ addresses: [String], index: Int) {
        guard !addresses.isEmpty else { return }
        editTestFlight { block in
            guard block.groups?.indices.contains(index) == true else { return }
            var list = block.groups?[index].testers ?? []
            var seen = Set(list.map { $0.lowercased() })
            for address in addresses where seen.insert(address.lowercased()).inserted {
                list.append(address)
            }
            block.groups?[index].testers = list
        }
    }

    /// Every address in a CSV, in the order it appears, without repeats.
    ///
    /// The file is read for addresses rather than for columns. An App Store
    /// Connect export carries "First Name,Last Name,Email", a list pasted out
    /// of a mail client carries `Name <address>`, and a plain column carries
    /// one address a line under no header at all. The one thing all of them
    /// agree on is that an address holds an "@" and a name does not, so a
    /// header row and a quoted "Doe, John" fall out on their own.
    ///
    /// // ponytail: a split, not an RFC 4180 parser. No address holds a comma
    /// // or a quote, so the fields that a real parser would keep together are
    /// // names, and names are dropped here anyway.
    static func addresses(inCSV text: String) -> [String] {
        var seen = Set<String>()
        // Whitespace separates as well as a comma does. No address holds a
        // space, and splitting on one is what turns a `Grace Hopper
        // <grace@example.com>` cell into an address and two names.
        return text.split(whereSeparator: { $0.isWhitespace || ",;\"".contains($0) })
            .map { $0.trimmingCharacters(in: addressEdges) }
            .filter { isEmailAddress($0) && seen.insert($0.lowercased()).inserted }
    }

    /// The angle brackets a mail client puts around an address.
    private static let addressEdges = CharacterSet(charactersIn: "<>")

    /// Enough of an address for Apple to email. Apple settles the rest, and it
    /// faults the whole request over one bad row, so a name column that holds
    /// an "@" may not reach it.
    static func isEmailAddress(_ value: String) -> Bool {
        let parts = value.split(separator: "@", omittingEmptySubsequences: false)
        guard parts.count == 2, !parts[0].isEmpty else { return false }
        let domain = parts[1]
        return domain.contains(".") && !domain.hasPrefix(".") && !domain.hasSuffix(".")
            && !value.contains(where: \.isWhitespace)
    }

    enum BetaGroupFlag {
        case publicLink, automaticBuilds, internalGroup, feedback
        case iosBuildsOnMac, iosBuildsOnVision
    }

    func betaGroupFlagBinding(index: Int, flag: BetaGroupFlag) -> Binding<Bool> {
        Binding(get: {
            guard let group = self.betaGroups[safe: index] else { return false }
            return switch flag {
            case .publicLink: group.publicLink ?? false
            case .automaticBuilds: group.automaticBuilds ?? false
            case .internalGroup:
                group.internalGroup ?? self.liveBetaGroup(index)?.internalGroup ?? false
            // A key the manifest leaves out sends nothing, so the switch shows
            // what Apple holds instead of a guess. Apple opens all three on a
            // new group, and that is the answer before any read.
            case .feedback: group.feedback ?? self.liveBetaGroup(index)?.feedback ?? true
            case .iosBuildsOnMac:
                group.iosBuildsOnMac ?? self.liveBetaGroup(index)?.iosBuildsOnMac ?? true
            case .iosBuildsOnVision:
                group.iosBuildsOnVision ?? self.liveBetaGroup(index)?.iosBuildsOnVision ?? true
            }
        }, set: { value in
            self.editTestFlight { block in
                guard block.groups?.indices.contains(index) == true else { return }
                switch flag {
                case .publicLink:
                    block.groups?[index].publicLink = value
                    // A limit without a link is a number Apple never reads.
                    if !value { block.groups?[index].publicLinkLimit = nil }
                case .automaticBuilds:
                    block.groups?[index].automaticBuilds = value
                case .internalGroup:
                    block.groups?[index].internalGroup = value
                    // Apple takes a public link on an external group only, so
                    // an internal group carries neither the link nor its cap.
                    if value {
                        block.groups?[index].publicLink = nil
                        block.groups?[index].publicLinkLimit = nil
                    }
                case .feedback:
                    block.groups?[index].feedback = value
                case .iosBuildsOnMac:
                    block.groups?[index].iosBuildsOnMac = value
                case .iosBuildsOnVision:
                    block.groups?[index].iosBuildsOnVision = value
                }
            }
        })
    }

    /// The group Apple holds under this name, from the last read of the store.
    func liveBetaGroup(_ index: Int) -> AppleTestFlightClient.BetaGroup? {
        guard let name = betaGroups[safe: index]?.name else { return nil }
        return actualState.apple?.betaGroups[name]
    }

    /// The public link Apple minted for a group, from the last read.
    ///
    /// Apple writes the URL itself when the link opens, so the manifest cannot
    /// hold it and no apply produces it. It is the address a developer hands
    /// to a tester, and the read used to drop it on the floor.
    func betaGroupPublicLink(index: Int) -> String? {
        guard let link = liveBetaGroup(index)?.publicLinkURL, !link.isEmpty else { return nil }
        return link
    }

    // MARK: - What the tester reads

    /// "What to Test". Apple keys it to the build, so it is written again for
    /// every build, and it is the note a tester opens TestFlight to.
    func whatToTestBinding(locale: String) -> Binding<String> {
        Binding(get: { self.testFlight?.whatToTest?[locale] ?? "" }, set: { value in
            self.editTestFlight { block in
                var notes = block.whatToTest ?? [:]
                let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                if trimmed.isEmpty { notes.removeValue(forKey: locale) }
                else { notes[locale] = value }
                block.whatToTest = notes.isEmpty ? nil : notes
            }
        })
    }

    enum TestFlightPageField {
        case description, feedbackEmail, marketingUrl, privacyPolicyUrl
    }

    /// The TestFlight page of the app. It belongs to the app rather than to a
    /// build, so it survives every upload.
    func testFlightPageBinding(locale: String,
                               field: TestFlightPageField) -> Binding<String> {
        Binding(get: {
            let text = self.testFlight?.localizations?[locale]
            return switch field {
            case .description: text?.description ?? ""
            case .feedbackEmail: text?.feedbackEmail ?? ""
            case .marketingUrl: text?.marketingUrl ?? ""
            case .privacyPolicyUrl: text?.privacyPolicyUrl ?? ""
            }
        }, set: { value in
            self.editTestFlight { block in
                var all = block.localizations ?? [:]
                var text = all[locale] ?? .init()
                let stored: String? = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ? nil : value
                switch field {
                case .description: text.description = stored
                case .feedbackEmail: text.feedbackEmail = stored
                case .marketingUrl: text.marketingUrl = stored
                case .privacyPolicyUrl: text.privacyPolicyUrl = stored
                }
                let empty = text.description == nil && text.feedbackEmail == nil
                    && text.marketingUrl == nil && text.privacyPolicyUrl == nil
                if empty { all.removeValue(forKey: locale) } else { all[locale] = text }
                block.localizations = all.isEmpty ? nil : all
            }
        })
    }

    /// The licence every external tester accepts before the first install.
    ///
    /// Apple keeps one per app and fills it with its own standard text. An
    /// empty box here writes nothing, so the Apple text stays, and that is
    /// what most apps want.
    var betaLicenseAgreementBinding: Binding<String> {
        Binding(get: { self.testFlight?.licenseAgreement ?? "" }, set: { value in
            self.editTestFlight {
                $0.licenseAgreement = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    .isEmpty ? nil : value
            }
        })
    }

    // MARK: - The two switches

    var betaAutoNotifyBinding: Binding<Bool> {
        Binding(get: { self.testFlight?.autoNotify ?? false }, set: { value in
            self.editTestFlight { $0.autoNotify = value }
        })
    }

    /// The one irreversible switch on this tab. A build in the beta review
    /// queue takes its place in it, and no call gives that place back.
    var betaSubmitForReviewBinding: Binding<Bool> {
        Binding(get: { self.testFlight?.submitForBetaReview ?? false }, set: { value in
            self.editTestFlight { $0.submitForBetaReview = value ? true : nil }
        })
    }

    // MARK: - Shared

    /// One writer for the whole block, so a binding that fires before the
    /// block exists creates it rather than dropping the keystroke.
    private func editTestFlight(_ edit: (inout Manifest.Release.TestFlight) -> Void) {
        if manifest.release == nil { manifest.release = Manifest.Release() }
        if manifest.release?.apple == nil {
            manifest.release?.apple = Manifest.Release.AppleRelease()
        }
        var block = manifest.release?.apple?.testFlight ?? Manifest.Release.TestFlight()
        edit(&block)
        manifest.release?.apple?.testFlight = block
        saveManifestReportingErrors()
    }
}
