import Foundation
import Testing
@testable import SubmitKit

/// One app id, two platforms, two different answers.
///
/// The case this exists for: a Mac app on sale while its iOS twin has never
/// shipped. `/v1/apps/{id}/appStoreVersions` returns both trains mixed, every
/// other reader narrows that to one platform, and the developer was left with
/// one line that did not say which platform it meant.
struct ApplePlatformStandingTests {
    private func payload(_ versions: [(String, String, String)]) -> JSON {
        let data = try! JSONSerialization.data(withJSONObject: [
            "data": versions.map { platform, version, state in
                ["type": "appStoreVersions",
                 "id": "\(platform)-\(version)",
                 "attributes": ["platform": platform,
                                "versionString": version,
                                "appVersionState": state]]
            },
        ])
        return JSON(data: data)
    }

    @Test func aLiveMacAndAnUnshippedPhoneReadAsTwoDifferentStates() {
        let standings = StoreImportReader.applePlatformStandings(payload([
            ("MAC_OS", "1.5", "READY_FOR_DISTRIBUTION"),
            ("IOS", "1.0", "PREPARE_FOR_SUBMISSION"),
        ]))
        #expect(standings.count == 2)
        let mac = standings.first { $0.platform == "MAC_OS" }
        #expect(mac?.liveState == "READY_FOR_DISTRIBUTION")
        #expect(mac?.live == "1.5")
        #expect(mac?.pending == nil)
        let ios = standings.first { $0.platform == "IOS" }
        #expect(ios?.pendingState == "PREPARE_FOR_SUBMISSION")
        #expect(ios?.live == nil)
        #expect(ios?.pending == "1.0")
    }

    /// The live number is the highest released one, and not whichever the API
    /// listed first. App Store Connect fixes no order here.
    @Test func theLiveNumberIsTheHighestAndNotTheFirst() {
        let standings = StoreImportReader.applePlatformStandings(payload([
            ("IOS", "1.9", "REPLACED_WITH_NEW_VERSION"),
            ("IOS", "1.10", "READY_FOR_DISTRIBUTION"),
            ("IOS", "2.0", "WAITING_FOR_REVIEW"),
        ]))
        let ios = standings.first { $0.platform == "IOS" }
        #expect(ios?.live == "1.10")
        #expect(ios?.pending == "2.0")
        // Both answers are kept: the chip asks "is it out?" and the tooltip
        // asks "what is happening to it?".
        #expect(ios?.liveState == "READY_FOR_DISTRIBUTION")
        #expect(ios?.pendingState == "WAITING_FOR_REVIEW")
    }

    /// A version row with no platform is an iOS row. Apple omitted the key on
    /// single-platform apps for years, and the reader beside this one makes the
    /// same assumption.
    @Test func aVersionWithNoPlatformCountsAsPhone() {
        let data = try! JSONSerialization.data(withJSONObject: [
            "data": [["type": "appStoreVersions", "id": "1",
                      "attributes": ["versionString": "3.0",
                                     "appStoreState": "READY_FOR_SALE"]]],
        ])
        let standings = StoreImportReader.applePlatformStandings(JSON(data: data))
        #expect(standings.map(\.platform) == ["IOS"])
        #expect(standings.first?.live == "3.0")
    }

    @Test func anAppWithNoVersionsAnswersWithNothing() {
        #expect(StoreImportReader.applePlatformStandings(payload([])).isEmpty)
    }
}
