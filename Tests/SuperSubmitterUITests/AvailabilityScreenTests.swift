import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// The tab that says where an app sells.
///
/// The bug it exists for: an app on sale in Brazil alone had no screen in this
/// program that said so. The read fetched the territories on every plan and
/// nothing drew them, and the one field that could change them sat inside a
/// price panel on a tab named after the in-app purchases.
@MainActor
@Suite struct AvailabilityScreenTests {

    /// A count of one country is not "1 countries", and no country at all is
    /// not "0 countries".
    @Test func theCountryCountReadsAsASentence() {
        #expect(AvailabilityTab.countLine(1) == "1 country")
        #expect(AvailabilityTab.countLine(175) == "175 countries")
        #expect(AvailabilityTab.countLine(0) == "no country")
    }

    /// The number of countries an app sells in is the number of rows the record
    /// marks available, and never the number of rows.
    ///
    /// The reported bug: App Store Connect said "1 Available, 174 Not
    /// Available" and this app said the store sells it in 175 countries. The
    /// record holds a row per territory Apple sells in, carrying a yes or a no,
    /// and the row count was being read as the answer.
    @MainActor
    @Test func theCountIsWhatTheRecordSaysYesTo() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        var apple = ActualState.Apple()
        apple.territoryAvailability = ["BRA": true, "USA": false, "PRT": false]
        apple.territoryCount = 3
        state.actualState.apple = apple

        #expect(state.liveAppleTerritories == ["BRA"])
        #expect(AvailabilityTab.countLine(state.liveAppleTerritories.count) == "1 country")
        #expect(state.liveAppleTerritoryCount == 3)
    }

    /// The switch shows what the App Store holds while `store.yaml` says
    /// nothing about it.
    ///
    /// It used to show "on" whenever the manifest was silent. On an app whose
    /// record holds `false` the switch was already wrong when the screen
    /// opened, and one click then wrote a value that disagreed with a store
    /// that takes no write for it. The warning that followed had no end inside
    /// this app.
    @Test func theNewTerritoriesSwitchFollowsTheStoreUntilTheManifestSpeaks() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.priceCurrency = "USD"
        state.priceAmount = "0.99"
        state.updateBasePrice()
        var apple = ActualState.Apple()
        apple.availableInNewTerritories = false
        state.actualState.apple = apple

        #expect(state.appleNewTerritoriesBinding.wrappedValue == false)

        // The manifest wins the moment it has an answer of its own.
        state.appleNewTerritoriesBinding.wrappedValue = true
        #expect(state.appleNewTerritoriesBinding.wrappedValue == true)

        // And with neither an answer nor a read, the App Store's own default.
        let fresh = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        #expect(fresh.appleNewTerritoriesBinding.wrappedValue == true)
    }

    /// The row's button writes the store's answer into `store.yaml`, which is
    /// the only way the disagreement ends without leaving the app.
    @Test func theStoresAnswerCanBeWrittenIntoTheManifest() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.priceCurrency = "USD"
        state.priceAmount = "0.99"
        state.updateBasePrice()
        state.appleNewTerritoriesBinding.wrappedValue = true
        var apple = ActualState.Apple()
        apple.availableInNewTerritories = false
        state.actualState.apple = apple

        #expect(state.canTakeStoreNewTerritories)
        state.takeStoreNewTerritories()

        #expect(state.manifest.pricing?.appleNewTerritories == false)
        // Settled, so the button goes away with the warning it settles.
        #expect(!state.canTakeStoreNewTerritories)
        #expect(!Validator.findings(Planner.Input(
            manifest: state.manifest, actual: state.actualState, stores: [.apple]))
            .contains { $0.id == Validator.newTerritoriesFindingID })

        // With no read there is nothing to take, and the button is not offered.
        let unread = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                              storeAccount: "test-\(UUID().uuidString)")
        #expect(!unread.canTakeStoreNewTerritories)
    }

    /// The picker offers what Apple sells in, not what ICU knows about.
    ///
    /// ICU knows 262 regions and the App Store sells in 175. The difference is
    /// places with no store at all and codes that name one country twice —
    /// Congo - Kinshasa is both `COD` and `ZAR` — and every one of them was a
    /// row a developer could tick. A run that names a territory the store does
    /// not hold stops on it.
    @MainActor
    @Test func thePickerFollowsTheStoresOwnTerritoryList() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        var apple = ActualState.Apple()
        apple.territoryAvailability = ["BRA": true, "PRT": false, "AGO": false]
        apple.territoryCount = 3
        state.actualState.apple = apple

        let codes = state.territoryGroups.flatMap { $0.territories.map(\.value) }
        #expect(Set(codes) == ["BRA", "PRT", "AGO"])
        // Two continents, and each says how many of its own are ticked.
        #expect(state.territoryGroups.map(\.name).sorted() == ["Africa", "Americas", "Europe"])

        // Until a read lands there is no store list, and the picker falls back
        // to the general one. The count no longer decides that: both reads
        // page the record to the end and a page that fails throws away the
        // whole answer, so a list that arrives is the whole record.
        state.actualState.apple?.territoryAvailability = [:]
        #expect(state.storeTerritories.isEmpty)
        #expect(state.territoryGroups.flatMap { $0.territories }.count > 200)
    }

    /// The picker is continents, and every App Store territory is on one.
    @Test func everyCountrySitsUnderAContinent() {
        let groups = StoreValues.territoryGroups()
        let names = groups.map(\.name)

        #expect(names.contains("Europe"))
        #expect(names.contains("Africa"))
        #expect(names.contains("Oceania"))
        let codes = groups.flatMap { $0.territories.map(\.value) }
        #expect(codes.contains("BRA"))
        #expect(codes.contains("PRT"))
        // ICU still answers for four dead states — the Netherlands Antilles,
        // Serbia and Montenegro, the Soviet Union, Yugoslavia. Apple sells in
        // none of them, and a run that names a territory the store does not
        // hold stops on it.
        #expect(!codes.contains("SUN"))
        #expect(!codes.contains("YUG"))
        // No country is in two continents, and none is listed twice.
        #expect(Set(codes).count == codes.count)
        // The names read as countries.
        #expect(groups.flatMap { $0.territories }
            .first { $0.value == "BRA" }?.label == "Brazil (BRA)")
    }

    /// Apple uses current territory codes that ICU sometimes knows through an
    /// older alias. They still belong to their continent.
    @Test func aCodeOnlyTheStoreKnowsStillGetsARow() {
        let groups = StoreValues.territoryGroups(including: ["XKS", "ROU", "BRA", "ZZZ"])
        let europe = groups.first { $0.name == "Europe" }

        #expect(europe?.territories.contains { $0.value == "XKS" } == true)
        #expect(europe?.territories.contains { $0.value == "ROU" } == true)
        #expect(groups.first { $0.id == "other" }?.territories.map(\.value) == ["ZZZ"])
        // A code the list already holds does not get a second row.
        #expect(groups.filter { $0.territories.contains { $0.value == "BRA" } }.count == 1)
    }

    /// Ticking is the whole answer, not the change.
    ///
    /// The old field wrote the ticked countries and dropped the rest, so
    /// unticking a country did nothing at all to the store: a territory the
    /// manifest does not name is one the plan leaves alone. Turning a country
    /// off has to be written as an answer.
    @Test func untickingACountryTheStoreSellsInWritesItOff() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.priceCurrency = "USD"
        state.priceAmount = "0.99"
        state.updateBasePrice()
        var apple = ActualState.Apple()
        apple.territoryAvailability = ["BRA": true, "PRT": true]
        apple.territoryCount = 2
        state.actualState.apple = apple

        // The store's own list is what the box opens on.
        #expect(state.territoryTicks == ["BRA", "PRT"])

        state.setTerritories(["PRT"], selling: false)

        let rows = state.manifest.pricing?.territories ?? []
        #expect(rows.first { $0.territory == "BRA" }?.available == true)
        #expect(rows.first { $0.territory == "PRT" }?.available == false)
        #expect(state.territoryTicks == ["BRA"])
        // And a country nobody has mentioned, that the store does not sell in,
        // earns no row at all. 260 rows of `available: false` is not an answer.
        #expect(rows.count == 2)
    }

    /// A continent is a shortcut for its countries and nothing more.
    @Test func tickingAContinentTicksItsCountries() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.priceCurrency = "USD"
        state.priceAmount = "0.99"
        state.updateBasePrice()
        let europe = try! #require(StoreValues.territoryGroups()
            .first { $0.name == "Europe" })

        state.setTerritories(europe.territories.map(\.value), selling: true)

        #expect(state.territoryTicks == Set(europe.territories.map(\.value)))
        #expect(state.manifest.pricing?.territories?.allSatisfy(\.available) == true)
    }

    /// A tick keeps what the row already carried. A preorder date lives on the
    /// same row as the answer, and rebuilding the list would drop it.
    @Test func aTickKeepsThePreorderOnTheRow() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.priceCurrency = "USD"
        state.priceAmount = "0.99"
        state.updateBasePrice()
        state.manifest.pricing?.territories = [Manifest.TerritoryAvailability(
            territory: "BRA", available: true, preOrderEnabled: true,
            releaseDate: "2026-09-01")]

        state.setTerritories(["PRT"], selling: true)

        let brazil = state.manifest.pricing?.territories?.first { $0.territory == "BRA" }
        #expect(brazil?.preOrderEnabled == true)
        #expect(brazil?.releaseDate == "2026-09-01")
        #expect(brazil?.available == true)
    }

    /// A price problem opens the tab that holds the price field.
    ///
    /// Every finding about money used to name Monetization, because every field
    /// about money was on it. The base price is on Availability now, so a jump
    /// that still named the other tab would land on a screen with no price on
    /// it at all.
    @Test func aBasePriceFindingOpensTheAvailabilityTab() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")

        #expect(state.tab(for: .availability) == .availability)
        #expect(state.tab(for: .money) == .money)
    }

    /// The raw side of each tab writes its own keys. `pricing` follows the
    /// fields: it holds the base price and the territory list, and both are on
    /// Availability now.
    @Test func thePricingBlockFollowsTheFieldsThatWriteIt() {
        #expect(ManifestBlock.availability.keys == ["pricing"])
        #expect(!ManifestBlock.money.keys.contains("pricing"))
        // Once across the whole app, or one tab's save would drop the other's
        // block.
        let keys = ManifestBlock.allCases.flatMap(\.keys)
        #expect(Set(keys).count == keys.count)
    }

    /// Changing the price keeps the countries.
    ///
    /// `updateBasePrice` built a fresh pricing block out of the price and
    /// carried one key across by hand, so the territory list and the
    /// new-territory answer were dropped on the keystroke. Both controls are on
    /// one screen now: pick the countries, correct the amount, lose the
    /// countries, with nothing on screen saying so.
    @Test func editingThePriceKeepsEverythingElseInTheBlock() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.priceCurrency = "USD"
        state.priceAmount = "0.99"
        state.updateBasePrice()
        state.setTerritories(["BRA"], selling: true)
        state.appleNewTerritoriesBinding.wrappedValue = false

        state.priceAmount = "1.99"
        state.updateBasePrice()

        #expect(state.manifest.pricing?.base.amount == Decimal(string: "1.99"))
        #expect(state.manifest.pricing?.territories?.map(\.territory) == ["BRA"])
        #expect(state.manifest.pricing?.appleNewTerritories == false)
    }

    /// And a first price still invents no answer. An absent key means "do not
    /// manage this", and a default here queues a store write nobody asked for.
    @Test func aFirstPriceAnswersNoQuestionNobodyAsked() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        state.priceCurrency = "USD"
        state.priceAmount = "0.99"

        state.updateBasePrice()

        #expect(state.manifest.pricing?.appleNewTerritories == nil)
        #expect(state.manifest.pricing?.autoConvertOtherTerritories == nil)
        #expect(state.manifest.pricing?.territories == nil)
    }

    /// The store's answer, on the screen that asks the question.
    @Test func theLiveTerritoriesReadTheStoreAndNotTheManifest() {
        let state = AppState(defaults: UserDefaults(suiteName: UUID().uuidString)!,
                             storeAccount: "test-\(UUID().uuidString)")
        var apple = ActualState.Apple()
        apple.territoryAvailability = ["BRA": true, "USA": false]
        apple.territoryCount = 2
        state.actualState.apple = apple

        // Only where it sells. A territory the record names and marks
        // unavailable is not a country the app is in.
        #expect(state.liveAppleTerritories == ["BRA"])
        #expect(state.liveAppleTerritoryCount == 2)
    }
}
