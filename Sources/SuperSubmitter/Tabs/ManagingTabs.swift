import SubmitKit
import SwiftUI

/// The tab that belongs to a live app.
///
/// Publishing ends at the Release tab. Everything here starts after it: the
/// customers are writing, the crash rate is real, and a bad release needs a
/// remedy. None of it is a desired state, so none of it goes through the plan.
/// Each panel acts on a button and confirms anything a customer would see.
///
/// This was three tabs. Between them they held six sentences and five buttons,
/// so a developer paid three navigation steps to read half a screen, and each
/// of the three showed its own "turn a store on first" line for the same
/// missing store. They ask one question — how is the shipped app doing — so
/// they are one tab with three sections and one empty state.
struct LiveAppTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            if state.stores.isEmpty {
                ManagingEmptyState(
                    line: "Turn a store on in Stores. The reviews, the numbers, and the remedies all come from a store, so this tab has nothing to read until one is on.")
            } else {
                // No group headings of our own. Every panel below already
                // carries its own, and wrapping them produced "How the
                // shipped app is doing" twice, one line under the other.
                if state.stores.contains(.apple) { AppStoreActionsPanel() }
                if state.stores.contains(.google) { GoogleReviewsPanel() }

                Hairline().padding(.vertical, 2)
                VitalsPanel()
                // The vitals answer "is it healthy" with a number, and this
                // answers the question that number raises. It reads the App
                // Store alone: Google keeps its crashes on the Play Console
                // and publishes no equivalent.
                if state.stores.contains(.apple) { CrashesPanel() }
                if state.stores.contains(.apple) { ReportsPanel() }
                if state.stores.contains(.apple) { WebhooksPanel() }

                Hairline().padding(.vertical, 2)
                if state.stores.contains(.google) {
                    GoogleRecoveryPanel()
                    GeneratedAPKPanel()
                } else {
                    ManagingEmptyState(
                        line: "Google Play offers the remote fix and the signed APKs. The App Store offers no equivalent, so the remedies have no Apple half.")
                }
            }
        }
        // Only the empty state capped itself, so the six panels below ran the
        // whole window: a sentence about a crash rate reached about 1500
        // points on a wide screen, which is roughly three times a readable
        // line. The cap is the tab's, so every panel inherits it.
        .frame(maxWidth: 980, alignment: .leading)
    }
}

/// The one line a managing tab shows before any store is on.
private struct ManagingEmptyState: View {
    let line: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.teal)
            Text(line)
                .font(Theme.font(size: 12.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: 700, alignment: .leading)
        .background(Theme.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
