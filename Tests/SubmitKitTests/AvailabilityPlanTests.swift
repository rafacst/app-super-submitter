import Foundation
import Testing
@testable import SubmitKit

/// When the plan offers to write the territory availability, and when it does
/// not.
///
/// The bug this guards: an update whose countries nobody had touched ended with
/// "The run stopped at Write the territory availability", and the write it
/// stopped on cannot succeed at all. Two mistakes met.
///
/// The manifest carried `autoConvertOtherTerritories: true` because saving a
/// price wrote that default, not because a developer chose it. The planner then
/// compared it against `availableInNewTerritories`, which the store read leaves
/// nil, and a `Bool` against a nil `Bool?` differs. So the step was planned on
/// every run of every app, for ever, and the apply then sent a request Apple
/// refuses outright.

private func plan(_ pricing: Manifest.Pricing?,
                  _ build: (inout ActualState.Apple) -> Void = { _ in }) -> [PlanStep] {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.pricing = pricing
    var apple = ActualState.Apple()
    apple.liveVersionString = "1.4"
    build(&apple)
    var actual = ActualState()
    actual.apple = apple
    return Planner.plan(Planner.Input(manifest: manifest, actual: actual, stores: [.apple]))
        .steps(for: .apple)
}

private func hasAvailabilityStep(_ steps: [PlanStep]) -> Bool {
    steps.contains { $0.id == "apple.availability" }
}

private let freePrice = Price(amount: 0, currency: "USD", territory: "USA")

/// The reported shape: a price, the default that came with it, and a store that
/// answers nothing about new territories.
@Test func anUnreadAnswerPlansNoWrite() {
    let pricing = Manifest.Pricing(base: freePrice, autoConvertOtherTerritories: true)

    #expect(!hasAvailabilityStep(plan(pricing)))
}

/// And the manifest no longer carries an answer nobody gave, so the usual case
/// does not even reach the comparison.
@Test func aPriceWithNoAnswerPlansNoWrite() {
    #expect(!hasAvailabilityStep(plan(Manifest.Pricing(base: freePrice))))
}

/// The store's answer, when the store gives one and it agrees.
@Test func anAnswerTheStoreAlreadyHoldsPlansNoWrite() {
    let pricing = Manifest.Pricing(base: freePrice, autoConvertOtherTerritories: true)

    #expect(!hasAvailabilityStep(plan(pricing) { $0.availableInNewTerritories = true }))
}

/// A real disagreement is still planned. The rule is "unknown is not
/// different", never "never write".
@Test func anAnswerTheDeveloperChangedIsStillPlanned() {
    let pricing = Manifest.Pricing(base: freePrice, autoConvertOtherTerritories: false)

    #expect(hasAvailabilityStep(plan(pricing) { $0.availableInNewTerritories = true }))
}

/// A territory the store lists and the manifest disagrees with.
@Test func aTerritoryThatDiffersIsStillPlanned() {
    var pricing = Manifest.Pricing(base: freePrice)
    pricing.territories = [Manifest.TerritoryAvailability(territory: "BRA", available: false)]

    #expect(hasAvailabilityStep(plan(pricing) { $0.territoryAvailability["BRA"] = true }))
}

/// A territory the store already agrees with is not written, which is what
/// keeps an app on sale in 175 countries from writing 175 times.
@Test func aTerritoryThatAgreesPlansNoWrite() {
    var pricing = Manifest.Pricing(base: freePrice)
    pricing.territories = [Manifest.TerritoryAvailability(territory: "BRA", available: true)]

    #expect(!hasAvailabilityStep(plan(pricing) { $0.territoryAvailability["BRA"] = true }))
}

/// An app with no availability record at all still gets one. This is a first
/// submission, where the create is the only way the territories are ever set.
@Test func anAppTheStoreListsNoTerritoriesForIsStillWritten() {
    var pricing = Manifest.Pricing(base: freePrice)
    pricing.territories = [Manifest.TerritoryAvailability(territory: "BRA", available: true)]

    #expect(hasAvailabilityStep(plan(pricing)))
}
