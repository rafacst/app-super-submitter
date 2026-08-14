import SubmitKit
import SwiftUI

/// The countries the App Store sells the app in, as a box of tick boxes.
///
/// It was a wall of 175 country names in a paragraph, over a chooser that
/// opened a popover of 266 more. Reading that paragraph told you nothing you
/// could act on, and the two together never said which of the countries you
/// were reading was one you had asked for.
///
/// One control now. A tick is "sell here", and the continents are how a list of
/// 260 countries becomes a list you can find something in: ticking Europe is
/// the same as ticking its 54 countries one at a time, and the box at the top
/// is the same again for the whole planet.
struct TerritoryPicker: View {
    @Environment(AppState.self) private var state

    /// Read once per draw and handed down. `territoryTicks` walks the store
    /// answer and the manifest to build a set, and a row that asks for itself
    /// would build that set 260 times a frame.
    var body: some View {
        let groups = state.territoryGroups
        let ticks = state.territoryTicks
        let every = groups.flatMap { $0.territories.map(\.value) }
        VStack(alignment: .leading, spacing: 0) {
            head(every: every, ticks: ticks)
            Hairline()
            ScrollView {
                LazyVStack(alignment: .leading, spacing: 16) {
                    ForEach(groups) { group in continent(group, ticks: ticks) }
                }
                .padding(12)
            }
            // Tall enough to hold a continent and short enough to leave the
            // toggle under the box on the screen with it.
            .frame(maxHeight: 380)
        }
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        // No price, no block to keep them in. The note beside the box says so.
        .disabled(!state.canEditTerritories)
        .opacity(state.canEditTerritories ? 1 : 0.5)
    }

    /// The whole planet, and where the count stands.
    private func head(every: [String], ticks: Set<String>) -> some View {
        let selected = ticks.intersection(every).count
        return HStack(spacing: 9) {
            TickBox(state: Self.mark(selected: selected, of: every.count)) {
                state.setTerritories(every, selling: selected < every.count)
            }
            Text("Every country")
                .font(Theme.font(size: 12.5, weight: .semibold))
            Text("\(selected) of \(every.count)")
                .font(Theme.mono(11)).foregroundStyle(Theme.text3)
            Spacer(minLength: 8)
            if state.territoriesFollowTheStore, !state.liveAppleTerritories.isEmpty {
                Text("From the App Store. Nothing is written until you change one.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
            }
        }
        .padding(.horizontal, 12).padding(.vertical, 9)
    }

    private func continent(_ group: StoreValues.TerritoryGroup,
                           ticks: Set<String>) -> some View {
        let codes = group.territories.map(\.value)
        let selected = ticks.intersection(codes).count
        return VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 8) {
                TickBox(state: Self.mark(selected: selected, of: codes.count)) {
                    state.setTerritories(codes, selling: selected < codes.count)
                }
                Text(group.name)
                    .font(Theme.font(size: 12, weight: .semibold))
                Text("\(selected) of \(codes.count)")
                    .font(Theme.mono(10.5)).foregroundStyle(Theme.text3)
                Spacer(minLength: 0)
            }
            // As many columns as the panel has room for. A single column of 63
            // African countries is the wall of text this control replaced.
            LazyVGrid(columns: [GridItem(.adaptive(minimum: 190), spacing: 4,
                                         alignment: .leading)],
                      alignment: .leading, spacing: 3) {
                ForEach(group.territories) { territory in
                    country(territory, ticked: ticks.contains(territory.value))
                }
            }
            .padding(.leading, 22)
        }
    }

    private func country(_ territory: StoreValues.Choice, ticked: Bool) -> some View {
        Button {
            state.setTerritories([territory.value], selling: !ticked)
        } label: {
            HStack(spacing: 7) {
                TickBox.glyph(ticked ? .on : .off)
                Text(territory.label)
                    .font(Theme.font(size: 11.5))
                    .foregroundStyle(ticked ? Theme.text : Theme.text2)
                    .lineLimit(1).truncationMode(.tail)
                Spacer(minLength: 0)
            }
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .help(territory.label)
        .accessibilityLabel(territory.label)
        .accessibilityAddTraits(ticked ? [.isButton, .isSelected] : .isButton)
    }

    /// Some of a group, all of it, or none.
    static func mark(selected: Int, of total: Int) -> TickBox.Mark {
        if selected == 0 { return .off }
        return selected == total ? .on : .mixed
    }
}

/// A tick box with the third state a group needs.
///
/// `Toggle` has two states, and a continent has three: every country, no
/// country, and some of them. A checkbox that reads "off" over 40 ticked
/// countries is a checkbox that lies, and pressing it would then tick the 14
/// that were already off — the opposite of what the developer meant.
struct TickBox: View {
    enum Mark { case on, off, mixed }

    let state: Mark
    let press: () -> Void

    var body: some View {
        Button(action: press) {
            Self.glyph(state).contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(state == .on ? "Selected"
                            : state == .mixed ? "Partly selected" : "Not selected")
    }

    @ViewBuilder
    static func glyph(_ state: Mark) -> some View {
        Image(systemName: state == .on ? "checkmark.square.fill"
              : state == .mixed ? "minus.square.fill" : "square")
            .font(Theme.font(size: 12.5))
            .foregroundStyle(state == .off ? Theme.text3 : Theme.accent)
    }
}
