import SwiftUI

/// One switch, nine tabs.
///
/// Every editing tab has a raw side, and the toolbar toggle picks which one
/// shows. Spec section 16.1.
struct TabContent: View {
    @Environment(AppState.self) private var state
    let tab: Tab

    var body: some View {
        if (tab == .details || tab == .media), state.locales.isEmpty {
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
        case .build: BuildTab()
        case .details: DetailsTab()
        case .media: MediaTab()
        case .money: MoneyTab()
        case .marketing: MarketingTab()
        case .reviewInfo: ReviewInfoTab()
        case .plan: PlanTab()
        case .release: ReleaseTab()
        case .liveApp: LiveAppTab()
        case .account: AccountTab()
        }
    }
}

private struct MissingLocaleView: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("Add the first locale")
                .font(.system(size: 14, weight: .semibold))
            Text("Details and media belong to a locale. Add the app’s real default locale before entering listing content.")
                .font(.system(size: 12.5))
                .foregroundStyle(Theme.text2)
            Button("Add locale") { state.showAddLocale = true }
                .buttonStyle(.borderedProminent)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
