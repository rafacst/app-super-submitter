import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The signing panel folds every group away.
///
/// It lives in the build inspector, which is a column about a third of the
/// window wide, and a real team holds forty identities. Drawn open, one fetch
/// pushed the panels above it off the screen and buried the line that matters,
/// which is the count of the ones that lapse.
///
/// Two rules make the folds bearable, and both are the kind that break in
/// silence: the fetch opens the groups with a problem in them, and a capability
/// list collapses to one row per name.
@MainActor
struct SigningIdentityFoldTests {
    private func item(_ kind: AppleProvisioningClient.Item.Kind, _ name: String,
                      days: Int? = nil) -> AppleProvisioningClient.Item {
        AppleProvisioningClient.Item(
            id: "\(kind.rawValue).\(name)", kind: kind, name: name,
            expiresAt: days.map { Date().addingTimeInterval(TimeInterval($0) * 86_400) })
    }

    /// A fetch opens the problem and nothing else. A panel that opened every
    /// group would be the wall of rows the fold exists to prevent.
    @Test func aFetchOpensOnlyTheGroupsThatHoldSomethingLapsing() {
        let open = SigningIdentitiesPanel.groupsToOpen([
            item(.certificate, "Apple Distribution", days: 300),
            item(.profile, "App Store profile", days: 12),
            item(.certificate, "Apple Development", days: -4),
            item(.device, "Anna's iPhone"),
        ])

        #expect(open == [.profile, .certificate])
    }

    /// Nothing lapsing means nothing opens, so the panel stays a list of counts.
    @Test func aCleanAccountOpensNothing() {
        #expect(SigningIdentitiesPanel.groupsToOpen([
            item(.certificate, "Apple Distribution", days: 300),
            item(.device, "Anna's iPhone"),
        ]).isEmpty)
    }

    /// Apple returns one capability row per bundle ID that holds it, and the
    /// read keeps no owner, so the raw list was "In app purchase" nine times
    /// down the column.
    @Test func theCapabilitiesFoldToOneRowPerName() {
        let rows = SigningIdentitiesPanel.rows(.capability, [
            item(.capability, "In app purchase"),
            item(.capability, "Push notifications"),
            item(.capability, "In app purchase"),
            item(.capability, "In app purchase"),
        ])

        #expect(rows.map(\.name) == ["In app purchase", "Push notifications"])
        #expect(rows.map(\.detail) == ["×3", nil])
        // The identity has to stay unique, or `ForEach` reconciles two rows
        // onto one.
        #expect(Set(rows.map(\.id)).count == rows.count)
    }

    /// Only the capabilities fold. A device list of four identical names is
    /// four phones, and collapsing them would hide three.
    @Test func everyOtherGroupKeepsItsRows() {
        let devices = [item(.device, "iPhone"), item(.device, "iPhone")]
        #expect(SigningIdentitiesPanel.rows(.device, devices) == devices)
    }
}
