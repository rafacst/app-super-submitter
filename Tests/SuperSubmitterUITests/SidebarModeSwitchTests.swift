import Foundation
import Testing
@testable import SuperSubmitter

/// The two jobs are a switch again, and the column holds one of them at a time.
///
/// Every group went into the column when the shell became a `NavigationSplitView`,
/// so nothing hid behind a control that named neither half. It cost the height:
/// twelve destinations and three headings stand in a column that only ever needs
/// the four or the eight, and the app list at the top is what gets squeezed.
///
/// The switch decides which groups exist. It does not decide which tabs exist:
/// `Tab.modes` still does that, and choosing a tab of the other job still moves
/// the switch rather than the other way round.
@MainActor
@Suite struct SidebarModeSwitchTests {

    private static let root = URL(fileURLWithPath: #filePath)
        .deletingLastPathComponent().deletingLastPathComponent().deletingLastPathComponent()

    private func source(_ path: String) throws -> String {
        try String(contentsOf: Self.root.appending(path: path), encoding: .utf8)
    }

    /// The switch uses the sidebar's own two words.
    ///
    /// "Publishing" and "Managing" named the same two jobs in a longer voice
    /// than every other label in the column, and the groups under the switch
    /// say "Publish", "Send" and "Manage". One word per job, and the switch
    /// takes the one the group already uses.
    @Test func theSwitchIsNamedTheWayTheGroupsAre() {
        #expect(Mode.publishing.title == "Publish")
        #expect(Mode.managing.title == "Manage")
    }

    /// A job with one group needs no heading over it.
    ///
    /// The switch names the job two rows above, so a lone "Manage" heading
    /// under a "Manage" button is the same word twice with nothing between
    /// them. Publishing has two steps and they still have to be told apart.
    @Test func aLoneGroupDoesNotRepeatTheSwitch() {
        #expect(!SidebarSection.manage.showsHeader(in: .managing))
        #expect(SidebarSection.publish.showsHeader(in: .publishing))
        #expect(SidebarSection.send.showsHeader(in: .publishing))
    }

    @Test func everyGroupBelongsToOneJob() {
        #expect(SidebarSection.publish.mode == .publishing)
        #expect(SidebarSection.send.mode == .publishing)
        #expect(SidebarSection.manage.mode == .managing)

        #expect(SidebarSection.allCases.filter { $0.mode == .publishing } == [.publish, .send])
        #expect(SidebarSection.allCases.filter { $0.mode == .managing } == [.manage])
    }

    /// Stores holds the keys both jobs read, so it stands in the column
    /// whichever job is showing.
    ///
    /// It was listed once, under Publish, which was right while every group was
    /// on screen at once. With one job showing, that same rule hides the
    /// credentials from a manager entirely.
    @Test func storesStandsInBothJobsAndOnceInEach() {
        for mode in Mode.allCases {
            let shown = SidebarSection.allCases
                .filter { $0.mode == mode }
                .flatMap { Destination.rows(in: $0, hasApp: true) }

            #expect(shown.contains { $0.tab == .stores }, "\(mode.title) hides Stores")
            // And once. Two rows to one screen is a `List` selection that
            // cannot say which of them you are standing on.
            #expect(shown.filter { $0.tab == .stores }.count == 1,
                    "\(mode.title) lists Stores twice")
        }
    }

    /// Nothing leaves the app with the switch. Every tab is still reachable,
    /// and Account is still the one the control at the foot opens.
    @Test func theSwitchHidesNoTab() {
        let reachable = Set(Mode.allCases.flatMap { mode in
            SidebarSection.allCases
                .filter { $0.mode == mode }
                .flatMap { Destination.rows(in: $0, hasApp: true) }
                .map(\.tab)
        })
        #expect(Set(Tab.allCases).subtracting(reachable) == [.account])
    }

    /// The column is shorter for it. That is the whole point: a manager reads
    /// four rows rather than twelve.
    @Test func eachJobIsShorterThanTheTwoTogether() {
        func rows(_ mode: Mode) -> Int {
            SidebarSection.allCases
                .filter { $0.mode == mode }
                .reduce(0) { $0 + Destination.rows(in: $1, hasApp: true).count }
        }
        let both = Destination.all(hasApp: true).count
        #expect(rows(.publishing) < both)
        #expect(rows(.managing) < both)
        #expect(rows(.managing) <= 5)
    }

    @Test func theSwitchStandsAboveTheColumn() throws {
        let sidebar = try source("Sources/SuperSubmitter/Shell/Sidebar.swift")

        #expect(sidebar.contains("ModeSwitch"))
        // And the groups follow it. A switch that draws every group is a
        // switch that changes nothing.
        #expect(sidebar.contains("$0.mode == state.mode"))
    }

    /// An empty window has no app to manage, so the switch still lands on the
    /// one row that survives it.
    @Test func anEmptyWindowKeepsStoresInBothJobs() {
        for mode in Mode.allCases {
            let shown = SidebarSection.allCases
                .filter { $0.mode == mode }
                .flatMap { Destination.rows(in: $0, hasApp: false) }
            #expect(shown.map(\.title) == ["Stores"], "\(mode.title) is not just Stores")
        }
    }
}
