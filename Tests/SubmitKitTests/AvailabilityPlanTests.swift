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
/// The manifest carried this answer because saving a
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

/// The reported shape: a live app, a price, and the default that came with it.
///
/// The App Store already holds an availability record, so this setting cannot
/// be written at all. A step for it is a step that must fail, whatever the two
/// values are.
@Test func aLiveAppPlansNoWriteForNewTerritories() {
    let pricing = Manifest.Pricing(base: freePrice, appleNewTerritories: true)

    #expect(!hasAvailabilityStep(plan(pricing) { $0.availableInNewTerritories = false }))
}

/// And the manifest no longer carries an answer nobody gave, so the usual case
/// does not even reach the comparison.
@Test func aPriceWithNoAnswerPlansNoWrite() {
    #expect(!hasAvailabilityStep(plan(Manifest.Pricing(base: freePrice))))
}

/// The store's answer, when the store gives one and it agrees.
@Test func anAnswerTheStoreAlreadyHoldsPlansNoWrite() {
    let pricing = Manifest.Pricing(base: freePrice, appleNewTerritories: true)

    #expect(!hasAvailabilityStep(plan(pricing) { $0.availableInNewTerritories = true }))
}

/// A real disagreement is not silently dropped either. The plan cannot carry
/// it, so the Summary says it in words and names where to change it.
@Test func aDisagreementTheStoreWillNotTakeIsReported() {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.pricing = Manifest.Pricing(base: freePrice, appleNewTerritories: false)
    var apple = ActualState.Apple()
    apple.availableInNewTerritories = true
    var actual = ActualState()
    actual.apple = apple

    let finding = try! #require(
        Validator.findings(Planner.Input(manifest: manifest, actual: actual, stores: [.apple]))
            .first { $0.id == "availability.newTerritories" })

    #expect(finding.severity == .warning)
    #expect(finding.message.contains("App Store Connect"))
}

/// An app with no record yet is the create, and the create is the one call that
/// carries this attribute.
@Test func anAppWithNoRecordStillWritesTheSetting() {
    let pricing = Manifest.Pricing(base: freePrice, appleNewTerritories: false)

    #expect(hasAvailabilityStep(plan(pricing)))
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

/// Writing the store's answer into `store.yaml` ends the warning. That is the
/// button on the row, and it is the only end the developer has inside this app:
/// Apple takes the value on the create and by no call after it.
@Test func takingTheStoresAnswerClearsTheWarning() {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    manifest.pricing = Manifest.Pricing(base: freePrice, appleNewTerritories: false)
    var actual = ActualState()
    var apple = ActualState.Apple()
    apple.availableInNewTerritories = true
    actual.apple = apple

    func findings(_ manifest: Manifest) -> [Finding] {
        Validator.findings(Planner.Input(manifest: manifest, actual: actual, stores: [.apple]))
    }
    #expect(findings(manifest).contains { $0.id == Validator.newTerritoriesFindingID })

    manifest.pricing?.appleNewTerritories = true
    #expect(!findings(manifest).contains { $0.id == Validator.newTerritoriesFindingID })
}

/// Every key the app writes into the pricing block is a key the shipped schema
/// has. `appleNewTerritories` was not one, so the file the app saves failed to
/// validate against the schema the app ships beside it.
@Test func thePricingBlockTheAppWritesValidatesAgainstTheShippedSchema() throws {
    var manifest = Manifest()
    manifest.setAppleApp(appID: "1234567890", bundleID: "com.example.app")
    var pricing = Manifest.Pricing(base: freePrice, appleNewTerritories: false)
    pricing.autoConvertOtherTerritories = true
    pricing.territories = [Manifest.TerritoryAvailability(territory: "BRA", available: true)]
    manifest.pricing = pricing

    let written = try ManifestFile.decode(ManifestFile.encode(manifest))
    #expect(written.pricing?.appleNewTerritories == false)

    let schema = try JSONSerialization.jsonObject(
        with: Data(source("Sources/SubmitKit/Resources/store.schema.json").utf8))
    let properties = ((((schema as? [String: Any])?["properties"] as? [String: Any])?["pricing"]
        as? [String: Any])?["properties"] as? [String: Any]) ?? [:]
    #expect((properties["appleNewTerritories"] as? [String: Any])?["type"] as? String
        == "boolean")

    // The whole block, so the next key that reaches the file without reaching
    // the schema fails here rather than in somebody's editor.
    let encoded = try JSONSerialization.jsonObject(
        with: try JSONEncoder().encode(pricing)) as? [String: Any] ?? [:]
    #expect(Set(encoded.keys).subtracting(properties.keys).isEmpty)
}
