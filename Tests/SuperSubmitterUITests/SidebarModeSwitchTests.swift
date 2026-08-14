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

    /// Every group wears its heading, including the job that has only one.
    ///
    /// Manage drew none for a while, on the grounds that the switch two rows
    /// above says the same word. It cost more than it saved: the four rows
    /// stood loose under the app list with nothing naming them, and the heading
    /// is also the control that folds a group, so the one job that could not be
    /// collapsed was the job with no heading.
    @Test func everyGroupIsNamedByItsHeading() {
        #expect(SidebarSection.allCases.map(\.title) == ["Publish", "Send", "Manage"])
    }

    @Test func everyGroupBelongsToOneJob() {
        #expect(SidebarSection.publish.mode == .publishing)
        #expect(SidebarSection.send.mode == .publishing)
        #expect(SidebarSection.manage.mode == .managing)

        #expect(SidebarSection.allCases.filter { $0.mode == .publishing } == [.publish, .send])
        #expect(SidebarSection.allCases.filter { $0.mode == .managing } == [.manage])
    }

    /// Stores holds the keys both jobs read, and it is in neither group.
    ///
    /// It was listed under Publish, which was right while every group was on
    /// screen at once. With one job showing, that rule hid the credentials from
    /// a manager, and listing it under Manage as well put one screen in two
    /// rows of a column whose selection can only stand on one of them. It is in
    /// the box at the foot of the column now, with the other two screens that
    /// are about this Mac rather than about an app, and the switch above cannot
    /// reach it at all.
    @Test func theGroupsHoldNoScreenThatIsAboutTheMachine() {
        for mode in Mode.allCases {
            let shown = SidebarSection.allCases
                .filter { $0.mode == mode }
                .flatMap { Destination.rows(in: $0, hasApp: true) }

            #expect(shown.allSatisfy { !$0.tab.standsAlone },
                    "\(mode.title) lists a screen the footer already holds")
        }
    }

    /// Nothing leaves the app with the switch. Every step of the work is still
    /// reachable, and the three screens about this Mac are in the footer box,
    /// which no mode can hide.
    @Test func theSwitchHidesNoTab() {
        let reachable = Set(Mode.allCases.flatMap { mode in
            SidebarSection.allCases
                .filter { $0.mode == mode }
                .flatMap { Destination.rows(in: $0, hasApp: true) }
                .map(\.tab)
        })
        #expect(Set(Tab.allCases).subtracting(reachable) == [.stores, .settings, .account])
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

    /// An empty window has no app, and every row in these groups is a step of
    /// one app's submission. Both jobs draw nothing, and the footer box below
    /// still holds the store keys, the settings and the account.
    @Test func anEmptyWindowListsNothingInEitherJob() {
        for mode in Mode.allCases {
            let shown = SidebarSection.allCases
                .filter { $0.mode == mode }
                .flatMap { Destination.rows(in: $0, hasApp: false) }
            #expect(shown.isEmpty, "\(mode.title) lists a step with no app to take it")
        }
    }

    /// The footer box is drawn from the tabs that stand alone, so a fourth one
    /// added to that set appears there without a second list to maintain.
    @Test func theFooterBoxHoldsTheThreeScreensAboutThisMac() throws {
        let sidebar = try source("Sources/SuperSubmitter/Shell/Sidebar.swift")

        #expect(sidebar.contains("FooterRow(tab: .stores)"))
        #expect(sidebar.contains("FooterRow(tab: .settings)"))
        #expect(sidebar.contains("AccountControl()"))
    }
}
