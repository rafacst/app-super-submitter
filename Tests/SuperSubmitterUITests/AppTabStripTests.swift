import Foundation
import Testing
@testable import SuperSubmitter

/// The bar across the top is a tab strip and not a segmented control.
///
/// Every tab used to be a segment inside one sunken pill: the chosen one drew a
/// small rounded rectangle with a shadow and the rest drew nothing, which is
/// the control the Mac uses for choosing a mode of one screen. This bar chooses
/// which document the window is showing, so it is shaped like a browser's tabs:
/// rounded across the top, a shoulder into the neighbour, and the chosen one
/// joined to the screen below it.
@Suite struct AppTabStripTests {

    private var bar: String {
        get throws {
            let root = URL(fileURLWithPath: #filePath)
                .deletingLastPathComponent().deletingLastPathComponent()
                .deletingLastPathComponent()
            return try String(
                contentsOf: root.appending(path: "Sources/SuperSubmitter/Shell/AppTabBar.swift"),
                encoding: .utf8)
        }
    }

    @Test func theTabsStandInAStripAndNotInAPill() throws {
        let bar = try bar

        // The strip, and the rule that ends it. Both behind the tabs.
        #expect(bar.contains(".background(alignment: .bottom)"))
        #expect(bar.contains("HStack(alignment: .bottom, spacing: 0)"))
        // The pill is gone: no track around the row, and no shadow lifting the
        // chosen segment off it.
        #expect(!bar.contains("RoundedRectangle(cornerRadius: 8)"))
        #expect(!bar.contains(".shadow(color: .black.opacity(0.18)"))
    }

    /// The chosen tab carries the surface of the screen below it and meets it
    /// with no seam. `Theme.content` is that surface: the header follows the
    /// scroll, and the entry screen draws no header at all.
    @Test func theChosenTabIsTheSurfaceUnderIt() throws {
        let bar = try bar

        #expect(bar.contains("if selected { return Theme.content }"))
        #expect(bar.contains("hovering ? Theme.raised : Theme.sunken"))
        // The join: the tab's own fill covers its bottom edge and the strip's
        // rule where it stands.
        #expect(bar.contains("Rectangle().fill(fill).frame(height: 1.5)"))
    }

    /// Rounded top corners and a shoulder at each bottom corner. Without the
    /// shoulders a row of these is a row of cards.
    @Test func aTabHasRoundedTopCornersAndAShoulder() throws {
        let bar = try bar

        #expect(bar.contains("struct TabShape: Shape"))
        #expect(bar.contains("var shoulder: CGFloat"))
        #expect(bar.contains("addQuadCurve"))
    }

    /// Everything the bar already did, which the shape was not allowed to
    /// cost: the icon, the name, the truncation, the building dot, the
    /// tooltip, the context menu, the traits and the scroll into view.
    @Test func theTabKeepsEverythingItAlreadyCarried() throws {
        let bar = try bar

        #expect(bar.contains("AppIconBadge(icon: app.icon, initials: app.initials, size: 15)"))
        #expect(bar.contains(".frame(maxWidth: 180)"))
        #expect(bar.contains("if state.isBuilding(appID: app.id) { BuildingDot() }"))
        #expect(bar.contains("state.appMark(appKey: app.key).explained"))
        #expect(bar.contains("Button(\"Update from the Stores…\")"))
        #expect(bar.contains("accessibilityAddTraits(selected ? [.isButton, .isSelected]"))
        #expect(bar.contains("proxy.scrollTo(state.appRows[state.selectedAppIndex].id)"))
        #expect(bar.contains("index == state.selectedAppIndex && !state.showsEntryScreen"))
    }

    /// Add app is not a tab. It opens the entry screen rather than choosing an
    /// app, so it never takes the tab shape, and it still reads as selected
    /// while the entry screen is showing.
    @Test func addAppIsAButtonInTheStripAndNotATab() throws {
        let bar = try bar
        let button = try #require(bar.range(of: "private var addButton"))
        let shape = try #require(bar.range(of: "private struct TabShape"))
        let body = String(bar[button.lowerBound..<shape.lowerBound])

        #expect(!body.contains("TabShape"))
        #expect(body.contains("Label(\"Add app\", systemImage: \"plus\")"))
        #expect(body.contains("state.showsEntryScreen ? [.isButton, .isSelected] : .isButton"))
    }
}
