import SubmitKit
import SwiftUI

/// Tab 3. Everything a tester meets before a customer does.
///
/// It was spread across the Build tab: TestFlight was a fold beside the drop
/// wells, the Google tester groups were the last block of the track section,
/// and internal app sharing was inside the "Store tooling" fold, three folds
/// away from either of them. Between them they answer one question — who gets
/// this build early, and what do they read when it arrives — and no screen
/// asked it.
///
/// **One column per store, and neither one is the other's twin.** Apple runs a
/// beta programme: named groups, invited addresses, a page of its own, and a
/// licence every external tester accepts. Google has no such thing. It gives a
/// closed track to a Google Group, and it gives a private install link that
/// belongs to no track at all. The two columns say so rather than pretending
/// to be symmetric.
struct BetaTestingTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            if state.stores.isEmpty {
                empty
            } else {
                HStack(alignment: .top, spacing: 14) {
                    if state.stores.contains(.apple) {
                        TestFlightSection()
                            .frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
                    }
                    if state.stores.contains(.google) {
                        VStack(alignment: .leading, spacing: 14) {
                            GoogleTestersSection()
                            InternalSharingPanel()
                        }
                        .frame(minWidth: 0, maxWidth: .infinity, alignment: .top)
                    }
                }
            }
        }
        .frame(maxWidth: 1040, alignment: .leading)
    }

    private var empty: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.teal)
            Text("Turn a store on in Stores. A tester is invited by a store, so this tab has nothing to offer until one is on.")
                .font(Theme.font(size: 12.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: 700, alignment: .leading)
        .background(Theme.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

/// Who may install a closed track.
///
/// Production reaches everybody, so it takes no list and gets no row. Every
/// other track the apply writes reaches nobody until a group is named here,
/// and the apply has always sent this field.
///
/// The tracks themselves stay on Build. Which tracks an edit writes is the
/// same decision as which one the Release tab sends, so splitting the list
/// across two tabs would ask it twice; this reads that answer and says where
/// it was given.
struct GoogleTestersSection: View {
    @Environment(AppState.self) private var state

    private var closedTracks: [String] {
        state.manifest.googleTracks.filter { $0 != "production" }
    }

    var body: some View {
        Section_("Track testers", icon: "person.2.fill", tint: Theme.playBlue,
                 anchor: "build.googleTesters") {
            VStack(alignment: .leading, spacing: 9) {
                if closedTracks.isEmpty {
                    Text("Google keeps its testers on a closed track. Pick internal, alpha or beta under Google tracks and rollout on the Build tab, and each one gets a row here.")
                        .font(Theme.font(size: 11.5)).foregroundStyle(Theme.text2)
                        .fixedSize(horizontal: false, vertical: true)
                } else {
                    ForEach(closedTracks, id: \.self) { track in
                        LabeledField(track, note: "Google Groups, comma-separated") {
                            TextField("beta-testers@googlegroups.com",
                                      text: state.googleTestersBinding(track: track))
                        }
                    }
                    Text("Google takes group addresses only. It keeps the single tester list in the Play Console, and it replaces the whole list on every apply.")
                        .font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
            .storePanel(padding: 14)
        }
    }
}
