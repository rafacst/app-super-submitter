import SubmitKit
import SwiftUI

/// The linked apps, across the top of the window.
///
/// They were a group at the head of the sidebar, under the destinations of the
/// app you were standing in. That put two levels of one hierarchy in one
/// column: which app, and which screen of it. Pressing an app there opened its
/// store page, so switching app also moved you off whatever you were reading,
/// and there was nowhere for an app to say it was busy once it left the screen.
///
/// A tab bar answers "which app" above "which screen", the way a browser does.
/// Switching keeps the screen you are on, so comparing the Details of two apps
/// is two clicks, and a build running on another app has a place to say so.
struct AppTabBar: View {
    @Environment(AppState.self) private var state

    var body: some View {
        // A scroll, because the number of apps is the developer's business.
        // Twelve linked apps used to squeeze the sidebar groups; here they run
        // off the side and the bar keeps its height.
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                // Bottom-aligned, and that is the whole shape of a tab strip:
                // the tabs stand on the strip's own bottom edge, and the
                // chosen one carries on into the screen below it.
                //
                // They were segments inside one sunken pill before, which is
                // the control the Mac uses for choosing a mode of one screen
                // and not for choosing which document the window is showing.
                // It read as a squeezed segmented control, because it was one.
                HStack(alignment: .bottom, spacing: 0) {
                    ForEach(Array(state.appRows.enumerated()),
                            id: \.element.id) { index, app in
                        AppTab(index: index, app: app)
                            .id(app.id)
                    }
                    addButton
                }
                .padding(.horizontal, 6)
                .frame(maxHeight: .infinity, alignment: .bottom)
            }
            .scrollIndicators(.never)
            // An app opened from anywhere else — the entry screen, an import,
            // the File menu — scrolls itself into view. Without this the tab of
            // the app being worked on can sit off the end of the bar.
            .onChange(of: state.selectedAppIndex) {
                guard state.appRows.indices.contains(state.selectedAppIndex) else { return }
                withAnimation(.easeInOut(duration: 0.2)) {
                    proxy.scrollTo(state.appRows[state.selectedAppIndex].id)
                }
            }
        }
        .frame(maxWidth: .infinity, minHeight: Theme.headerHeight,
               maxHeight: Theme.headerHeight, alignment: .leading)
        // The strip the tabs stand in, and the rule that ends it. Both are
        // behind the tabs, so the chosen tab covers the rule where it sits and
        // its fill runs into the screen below with no seam.
        .background(alignment: .bottom) {
            ZStack(alignment: .bottom) {
                Theme.sunken
                Rectangle().fill(Theme.sep).frame(height: Theme.hairline)
            }
        }
    }

    /// Not a tab. It opens the entry screen rather than choosing an app, so it
    /// keeps the shape of a button: standing in the strip beside the tabs, and
    /// never carrying the surface of the screen the way a chosen tab does.
    private var addButton: some View {
        Button { state.showEntryScreen = true } label: {
            Label("Add app", systemImage: "plus")
                .font(Theme.font(size: 12, weight: state.showsEntryScreen ? .semibold : .regular))
                .foregroundStyle(state.showsEntryScreen ? Theme.text : Theme.text2)
                .padding(.horizontal, 10)
                .padding(.vertical, 4)
                .background {
                    if state.showsEntryScreen {
                        RoundedRectangle(cornerRadius: 6).fill(Theme.raised)
                    }
                }
                .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .padding(.leading, 6)
        .padding(.bottom, 7)
        .accessibilityAddTraits(state.showsEntryScreen ? [.isButton, .isSelected] : .isButton)
    }
}

/// One tab of the strip: rounded across the top, and a shoulder at each bottom
/// corner that curves out into the surface beside it instead of stopping at a
/// vertical edge. It is what makes a row of these read as tabs rather than as
/// a row of cards.
private struct TabShape: Shape {
    var radius: CGFloat = 8
    var shoulder: CGFloat = 7

    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.maxY))
        path.addQuadCurve(to: CGPoint(x: rect.minX + shoulder, y: rect.maxY - shoulder),
                          control: CGPoint(x: rect.minX + shoulder, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX + shoulder, y: rect.minY + radius))
        path.addQuadCurve(to: CGPoint(x: rect.minX + shoulder + radius, y: rect.minY),
                          control: CGPoint(x: rect.minX + shoulder, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - shoulder - radius, y: rect.minY))
        path.addQuadCurve(to: CGPoint(x: rect.maxX - shoulder, y: rect.minY + radius),
                          control: CGPoint(x: rect.maxX - shoulder, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX - shoulder, y: rect.maxY - shoulder))
        path.addQuadCurve(to: CGPoint(x: rect.maxX, y: rect.maxY),
                          control: CGPoint(x: rect.maxX - shoulder, y: rect.maxY))
        path.closeSubpath()
        return path
    }
}

/// One app's tab.
///
/// The icon and the name say which app, and the dot says this app is building
/// right now. The dot is the whole reason the bar exists: a build that is no
/// longer on the screen is still running, and before this there was no way for
/// the window to say so.
///
/// The store standing is not here. A tab bar answers "which app", and a chip
/// reading "Store draft" beside every name answered a question nobody asked at
/// the moment they were picking one — it doubled the width of each tab, so the
/// names got squeezed into an ellipsis and the one thing the bar is for became
/// the hardest thing on it to read. The standing is still on the screens that
/// are about it, and the tooltip carries it here.
private struct AppTab: View {
    @Environment(AppState.self) private var state
    let index: Int
    let app: AppSummary
    @State private var hovering = false

    private var selected: Bool {
        index == state.selectedAppIndex && !state.showsEntryScreen
    }

    /// The chosen tab is the screen below it, carried up into the strip. The
    /// rest are recessed, and hovering one lifts it towards the front.
    ///
    /// `Theme.content` and not the header's own fill. The header follows the
    /// scroll and the entry screen draws no header at all, and the tab cannot
    /// chase either: `content` is what both of those rest on.
    private var fill: Color {
        if selected { return Theme.content }
        return hovering ? Theme.raised : Theme.sunken
    }

    var body: some View {
        Button {
            // The screen stays. Switching app while reading Details lands on
            // the other app's Details, which is what the bar is for; the old
            // list opened the store page and lost your place every time.
            state.selectApp(at: index)
        } label: {
            HStack(spacing: 6) {
                AppIconBadge(icon: app.icon, initials: app.initials, size: 15)
                Text(app.name)
                    .font(Theme.font(size: 12, weight: selected ? .semibold : .regular))
                    .foregroundStyle(selected ? Theme.text : Theme.text2)
                    .lineLimit(1)
                if state.isBuilding(appID: app.id) { BuildingDot() }
            }
            // The shoulders take seven points at each end, so the words start
            // where the flat top starts and not on the curve.
            .padding(.horizontal, 15)
            .padding(.vertical, 5)
            .frame(maxHeight: .infinity)
            .background {
                let shape = TabShape()
                ZStack {
                    shape.fill(fill)
                    shape.stroke(selected ? Theme.sep : Theme.sep2,
                                 lineWidth: Theme.hairline)
                }
                // The chosen tab and the screen under it are one surface. This
                // covers the shape's own bottom edge and the strip's rule with
                // the tab's fill, which is the join a tab strip is for.
                .overlay(alignment: .bottom) {
                    if selected {
                        Rectangle().fill(fill).frame(height: 1.5)
                    }
                }
                // The unchosen ones stand a little lower, behind the chosen
                // one rather than beside it.
                .padding(.top, selected ? 3 : 6)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .motion(.easeOut(duration: 0.12), value: hovering)
        // The name truncates at 180 points. A tab bar of five apps whose names
        // all start "My Company " is five identical tabs otherwise.
        .frame(maxWidth: 180)
        // The standing, in the one place that costs the bar no width. It was a
        // chip on the tab itself.
        .help("\(app.name) · \(state.appMark(appKey: app.key).explained)")
        .contextMenu {
            Button("Update from the Stores…") {
                state.selectApp(at: index)
                state.startAppImport()
            }
            Divider()
            Button("Remove from Super Submitter…") { state.askToRemoveApp(at: index) }
        }
        .accessibilityLabel(app.name)
        .accessibilityValue(app.storeSummary)
        .accessibilityAddTraits(selected ? [.isButton, .isSelected] : .isButton)
    }
}

/// This app is building or sending, and you are looking at another one.
///
/// It pulses, because the state it reports is one that ends on its own. A
/// static dot beside a name says "something about this app"; a moving one says
/// "something is happening in it right now", which is the only reason to draw
/// it on a tab the developer has left.
private struct BuildingDot: View {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var dim = false

    var body: some View {
        Circle()
            .fill(Theme.accent)
            .frame(width: 5, height: 5)
            .opacity(dim ? 0.25 : 1)
            .animation(reduceMotion ? nil : .easeInOut(duration: 0.8).repeatForever(),
                       value: dim)
            .onAppear { dim = true }
            .accessibilityElement()
            .accessibilityLabel("Building")
    }
}
