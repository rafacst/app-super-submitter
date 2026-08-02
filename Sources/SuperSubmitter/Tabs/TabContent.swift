import SwiftUI

/// One switch, nine tabs.
///
/// Every editing tab has a raw side, and the toolbar toggle picks which one
/// shows. Spec section 16.1.
struct TabContent: View {
    @Environment(AppState.self) private var state
    let tab: Tab

    var body: some View {
        if state.showYAML, let block = state.yamlBlock {
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
        case .reviewInfo: ReviewInfoTab()
        case .plan: PlanTab()
        case .submit: SubmitTab()
        case .release: ReleaseTab()
        }
    }
}
