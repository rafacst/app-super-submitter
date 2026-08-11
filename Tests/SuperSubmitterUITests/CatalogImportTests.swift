import Foundation
import Testing
@testable import SubmitKit
@testable import SuperSubmitter

/// The products the App Store already holds, brought in so they can be edited.
///
/// The gap this closes: the read has always fetched every product on the store
/// and the tab only ever drew the ones `store.yaml` named. An app with approved
/// purchases showed an empty catalog, and the only way to manage one was to
/// retype its id exactly and hope the apply matched it rather than creating a
/// second product beside it.
@MainActor
struct CatalogImportTests {

    private func state(_ build: (inout ActualState.Apple) -> Void) -> AppState {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.manifest.apps.apple = Manifest.Apps.Apple(
            appId: "123", platforms: [.ios], bundleId: "com.example.app")
        var apple = ActualState.Apple()
        build(&apple)
        var actual = ActualState()
        actual.apple = apple
        state.actualState = actual
        return state
    }

    private func product(_ id: String, name: String? = nil, state: String? = nil,
                         duration: String? = nil, group: String? = nil)
        -> ActualState.Apple.CatalogProduct {
        var product = ActualState.Apple.CatalogProduct()
        product.productId = id
        product.id = "apple-\(id)"
        product.name = name
        product.state = state
        product.duration = duration
        product.groupName = group
        return product
    }

    @Test func aPurchaseTheStoreHoldsComesIn() {
        let state = state {
            $0.catalog = ["com.example.lifetime": product("com.example.lifetime",
                                                          name: "Lifetime",
                                                          state: "APPROVED")]
        }

        #expect(state.appleCatalogNotImported == 1)
        #expect(state.importAppleCatalog() == 1)

        #expect(state.manifest.purchases?.count == 1)
        #expect(state.manifest.purchases?.first?.id == "com.example.lifetime")
        #expect(state.manifest.purchases?.first?.name == "Lifetime")
        #expect(state.appleCatalogNotImported == 0)
    }

    /// A subscription is nested under its group, so the group has to come with
    /// it. Apple returns the two flat and the link has to be carried across.
    @Test func aSubscriptionLandsInsideItsGroup() {
        let state = state {
            $0.catalog = ["com.example.monthly": product("com.example.monthly",
                                                         state: "APPROVED",
                                                         duration: "P1M",
                                                         group: "Pro")]
        }

        #expect(state.importAppleCatalog() == 1)

        #expect(state.manifest.subscriptions?.count == 1)
        #expect(state.manifest.subscriptions?.first?.groupName == "Pro")
        #expect(state.manifest.subscriptions?.first?.plans.first?.id == "com.example.monthly")
        #expect(state.manifest.subscriptions?.first?.plans.first?.duration == "P1M")
    }

    /// Inventing a group would create a second one on the next apply, beside
    /// the one Apple already has.
    @Test func aSubscriptionWithNoGroupIsLeftAlone() {
        let state = state {
            $0.catalog = ["com.example.monthly": product("com.example.monthly",
                                                         duration: "P1M")]
        }

        #expect(state.importAppleCatalog() == 0)
        #expect(state.manifest.subscriptions == nil)
    }

    /// The rule the listing import already obeys. What the developer typed is
    /// theirs, and a store value must never land on top of it.
    @Test func aProductTheManifestAlreadyNamesIsNotWrittenOver() {
        let state = state {
            $0.catalog = ["com.example.lifetime": product("com.example.lifetime",
                                                          name: "Apple's name")]
        }
        state.manifest.purchases = [Manifest.Purchase(id: "com.example.lifetime",
                                                      kind: .consumable,
                                                      name: "My name")]

        #expect(state.appleCatalogNotImported == 0)
        #expect(state.importAppleCatalog() == 0)
        #expect(state.manifest.purchases?.first?.name == "My name")
        #expect(state.manifest.purchases?.first?.kind == .consumable)
    }

    @Test func nothingReadMeansNothingToBringIn() {
        let state = state { _ in }

        #expect(state.appleCatalogNotImported == 0)
        #expect(state.importAppleCatalog() == 0)
    }

    // MARK: - What a change costs

    /// The whole point of showing the state. A product carries its own review,
    /// and an approved one goes back through it when its text changes.
    @Test func anApprovedProductIsNamedAsApproved() {
        let approved = product("a", state: "APPROVED")
        let offSale = product("b", state: "REMOVED_FROM_SALE")

        #expect(approved.isApproved)
        #expect(!approved.isWithReview)
        // It went through review once. Putting it back on sale is not a fresh
        // submission.
        #expect(offSale.isApproved)
    }

    @Test func aProductWithAppleIsNamedAsWithReview() {
        #expect(product("a", state: "WAITING_FOR_REVIEW").isWithReview)
        #expect(product("a", state: "IN_REVIEW").isWithReview)
        #expect(!product("a", state: "IN_REVIEW").isApproved)
    }

    /// A product that has never been submitted is neither, and the tab says
    /// nothing about it rather than guessing.
    @Test func aDraftProductIsNeither() {
        let draft = product("a", state: "READY_TO_SUBMIT")

        #expect(!draft.isApproved)
        #expect(!draft.isWithReview)
        #expect(!product("a").isApproved)
    }

    @Test func theStateReachesTheTabFromTheRead() {
        let state = state {
            $0.catalog = ["com.example.lifetime": product("com.example.lifetime",
                                                          state: "APPROVED")]
        }

        #expect(state.appleProductState("com.example.lifetime")?.isApproved == true)
        #expect(state.appleProductState("com.example.unknown") == nil)
    }
}
