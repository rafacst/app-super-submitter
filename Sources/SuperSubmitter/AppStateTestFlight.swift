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

    enum BetaGroupFlag { case publicLink, automaticBuilds }

    func betaGroupFlagBinding(index: Int, flag: BetaGroupFlag) -> Binding<Bool> {
        Binding(get: {
            guard let group = self.betaGroups[safe: index] else { return false }
            return switch flag {
            case .publicLink: group.publicLink ?? false
            case .automaticBuilds: group.automaticBuilds ?? false
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
                }
            }
        })
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
