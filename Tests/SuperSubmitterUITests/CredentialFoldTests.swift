import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// A connected credential card folds itself away.
///
/// The key is entered once and covers every app on the account, so after the
/// connection passes the card is four controls nobody touches again, sitting
/// above the store picker they pushed down the tab. The rule has two halves and
/// only the first is obvious: the fold follows the connection, and a developer
/// who worked the fold by hand overrides it.
@MainActor
struct CredentialFoldTests {
    private func newState() -> AppState {
        AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                 storeAccount: "test-\(UUID().uuidString)")
    }

    @Test func anUnconnectedCardIsOpenAndAConnectedOneIsNot() {
        let state = newState()
        #expect(state.credentialDetailsOpen(.apple))

        state.appleConnection = .connected("App Store Connect answered.")
        #expect(!state.credentialDetailsOpen(.apple))
    }

    /// The one that stops the fold from being a trap. A refused key needs the
    /// fields, and a card that stayed shut on a failure would hide the only
    /// controls that fix it.
    @Test func aRefusedKeyKeepsItsFieldsInReach() {
        let state = newState()
        state.appleConnection = .connected("App Store Connect answered.")
        #expect(!state.credentialDetailsOpen(.apple))

        state.appleConnection = .failed("The store refused the key.")
        #expect(state.credentialDetailsOpen(.apple))
    }

    @Test func aCardOpenedByHandStaysOpenAfterItConnects() {
        let state = newState()
        state.appleConnection = .connected("App Store Connect answered.")
        state.toggleCredentialDetails(.apple)
        #expect(state.credentialDetailsOpen(.apple))

        // A reconnect must not fold the card the developer just opened.
        state.appleConnection = .connected("App Store Connect answered again.")
        #expect(state.credentialDetailsOpen(.apple))
    }

    @Test func theTwoStoresFoldApart() {
        let state = newState()
        state.appleConnection = .connected("App Store Connect answered.")
        #expect(!state.credentialDetailsOpen(.apple))
        #expect(state.credentialDetailsOpen(.google))
    }

    /// `FieldIndex` sends ⌘F at two fields that now live inside the fold.
    /// Scrolling to an anchor in a collapsed card lands on nothing, silently,
    /// which is the one failure the index exists to prevent.
    @Test func theFieldSearchOpensTheCardItLandsIn() {
        let state = newState()
        state.appleConnection = .connected("App Store Connect answered.")
        state.googleConnection = .connected("Google answered.")

        state.revealCredentialDetails(forAnchor: "stores.appleKeyID")
        #expect(state.credentialDetailsOpen(.apple))
        #expect(!state.credentialDetailsOpen(.google))

        // Every anchor in the index that reaches this tab has to route to the
        // right card, and nothing else may open one.
        state.revealCredentialDetails(forAnchor: "details.name")
        #expect(!state.credentialDetailsOpen(.google))
    }

    @Test func everyStoresAnchorInTheIndexReachesACard() {
        for entry in FieldIndex.all where entry.id.hasPrefix("stores.") {
            let state = newState()
            state.appleConnection = .connected("App Store Connect answered.")
            state.googleConnection = .connected("Google answered.")
            state.revealCredentialDetails(forAnchor: entry.id)
            #expect(state.credentialOpen.values.contains(true),
                    "\(entry.id) opens no credential card")
        }
    }
}
