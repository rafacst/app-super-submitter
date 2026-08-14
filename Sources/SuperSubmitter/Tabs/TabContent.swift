import SwiftUI

/// One switch, nine tabs.
///
/// Every editing tab has a raw side, and the toolbar toggle picks which one
/// shows. Spec section 16.1.
struct TabContent: View {
    @Environment(AppState.self) private var state
    let tab: Tab

    var body: some View {
        // The store page joins the two: a page is a listing in a locale, and
        // with no locale there is no name, no description and no screenshot to
        // draw. A mockup of nothing at all is a screen with nothing to act on,
        // and this one names the single thing that unblocks it.
        if (tab == .details || tab == .media || tab == .storePage), state.locales.isEmpty {
            MissingLocaleView()
        } else if state.showYAML, let block = state.yamlBlock {
            YAMLEditor(block: block)
        } else {
            form
        }
    }

    @ViewBuilder
    private var form: some View {
        switch tab {
        case .stores: StoresTab()
        case .storePage: StorePage()
        case .build: BuildTab()
        case .betaTesting: BetaTestingTab()
        case .details: DetailsTab()
        case .media: MediaTab()
        case .gaming: GamingTab()
        case .availability: AvailabilityTab()
        case .money: MoneyTab()
        case .marketing: MarketingTab()
        case .reviewInfo: ReviewInfoTab()
        case .plan: PlanTab()
        case .release: ReleaseTab()
        case .liveApp: LiveAppTab()
        case .account: AccountTab()
        case .settings: SettingsTab()
        }
    }
}

private struct MissingLocaleView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add the first locale")
                .font(Theme.font(size: 14, weight: .semibold))
            Text("Details and media belong to a locale. Add the app’s real default locale before entering listing content.")
                .font(Theme.font(size: 12.5))
                .foregroundStyle(Theme.text2)
            Button("Add locale") { state.showAddLocale = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
