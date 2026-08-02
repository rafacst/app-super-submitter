import SwiftUI

/// One switch, nine tabs.
struct TabContent: View {
    let tab: Tab

    var body: some View {
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
