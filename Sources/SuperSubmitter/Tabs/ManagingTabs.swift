import SubmitKit
import SwiftUI

/// The three tabs that belong to a live app.
///
/// Publishing ends at the Release tab. Everything here starts after it: the
/// customers are writing, the crash rate is real, and a bad release needs a
/// remedy. None of it is a desired state, so none of it goes through the plan.
/// Each panel acts on a button and confirms anything a customer would see.

/// Tab: Reviews. Both stores, side by side.
struct ReviewsTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if state.stores.isEmpty {
                ManagingEmptyState(
                    line: "Turn a store on in Stores, and the reviews of that store appear here.")
            }
            if state.stores.contains(.apple) { AppStoreActionsPanel() }
            if state.stores.contains(.google) { GoogleReviewsPanel() }
        }
    }
}

/// Tab: Analytics. What the two stores measure about the shipped app.
struct AnalyticsTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if state.stores.isEmpty {
                ManagingEmptyState(
                    line: "Turn a store on in Stores, and its measurements appear here.")
            } else {
                VitalsPanel()
                if state.stores.contains(.apple) { ReportsPanel() }
            }
        }
    }
}

/// Tab: App health. The remedies for a release that went wrong.
struct HealthTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            if state.stores.contains(.google) {
                GoogleRecoveryPanel()
                GeneratedAPKPanel()
            } else {
                ManagingEmptyState(
                    line: "Google Play offers the remote fix and the signed APKs. Turn it on in Stores to reach them. The App Store offers no equivalent, so nothing here has an Apple half.")
            }
        }
    }
}

/// The one line a managing tab shows before any store is on.
private struct ManagingEmptyState: View {
    let line: String

    var body: some View {
        HStack(alignment: .top, spacing: 9) {
            Image(systemName: "info.circle.fill").foregroundStyle(Theme.teal)
            Text(line)
                .font(.system(size: 12.5)).foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .padding(13)
        .frame(maxWidth: 700, alignment: .leading)
        .background(Theme.teal.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}
