import Foundation
import Testing
@testable import SubmitKit

private let everyList: [(String, [StoreValues.Choice])] = [
    ("appleCategories", StoreValues.appleCategories),
    ("kidsAgeBands", StoreValues.kidsAgeBands),
    ("eventBadges", StoreValues.eventBadges),
    ("eventPriorities", StoreValues.eventPriorities),
    ("eventPurposes", StoreValues.eventPurposes),
    ("nominationTypes", StoreValues.nominationTypes),
    ("appClipActions", StoreValues.appClipActions),
    ("accessibilityFeatures", StoreValues.accessibilityFeatures),
    ("googleTracks", StoreValues.googleTracks),
    ("taxCategories", StoreValues.taxCategories),
    ("withdrawalRights", StoreValues.withdrawalRights),
    ("listingLocales", StoreValues.listingLocales),
    ("subscriptionDurations", StoreValues.subscriptionDurations),
    ("offerDurations", StoreValues.offerDurations),
    ("currencies", StoreValues.currencies),
    ("appleTerritories", StoreValues.appleTerritories),
    ("googleCountries", StoreValues.googleCountries),
]

@Test func noListIsEmptyAndNoValueRepeats() {
    for (name, list) in everyList {
        #expect(!list.isEmpty, "\(name) is empty")
        #expect(Set(list.map(\.value)).count == list.count, "\(name) repeats a value")
        #expect(list.allSatisfy { !$0.value.isEmpty }, "\(name) holds an empty value")
        #expect(list.allSatisfy { !$0.label.isEmpty }, "\(name) holds an empty label")
    }
}

/// The value reaches the store, so a stray space would send one no store
/// answers for.
@Test func noValueCarriesWhitespace() {
    for (name, list) in everyList {
        #expect(list.allSatisfy { $0.value == $0.value.trimmingCharacters(in: .whitespaces) },
                "\(name) pads a value")
    }
}

/// The whole point of the map: nobody reads `FOOD_AND_DRINK` on the screen.
@Test func noLabelIsJustTheCodeBack() {
    let shouty = everyList.flatMap(\.1).filter {
        $0.label == $0.value && $0.value.contains("_")
    }
    #expect(shouty.isEmpty, "these still show the raw code: \(shouty.map(\.value))")
}

/// The currency and territory codes go straight into a price. Apple takes
/// three letters for both, and the case is not ours to fix later.
@Test func moneyCodesAreThreeUppercaseLetters() {
    for choice in StoreValues.currencies + StoreValues.appleTerritories {
        #expect(choice.value.count == 3, "\(choice.value) is not three letters")
        #expect(choice.value == choice.value.uppercased(), "\(choice.value) is not uppercase")
    }
}

/// Google targets a release by alpha-2.
@Test func googleCountriesAreTwoUppercaseLetters() {
    for choice in StoreValues.googleCountries {
        #expect(choice.value.count == 2, "\(choice.value) is not two letters")
        #expect(choice.value == choice.value.uppercased(), "\(choice.value) is not uppercase")
    }
}

/// The territory list comes out of ICU rather than a table typed by hand, so
/// this checks the derivation found the codes everybody knows.
@Test func theTerritoryListHoldsTheObviousCountries() {
    let values = Set(StoreValues.appleTerritories.map(\.value))
    for code in ["USA", "GBR", "DEU", "FRA", "BRA", "JPN", "AUS", "CAN", "IND", "ZAF"] {
        #expect(values.contains(code), "the derivation missed \(code)")
    }
    #expect(StoreValues.appleTerritories.count > 200)
}

/// Every duration is an ISO 8601 period, because the manifest sends it as one.
@Test func everyDurationIsAnISOPeriod() {
    for choice in StoreValues.subscriptionDurations + StoreValues.offerDurations {
        #expect(choice.value.range(of: #"^P\d+[DWMY]$"#, options: .regularExpression) != nil,
                "\(choice.value) is not an ISO 8601 period")
    }
}

/// The four tracks the planner treats as standard are the four the menu
/// offers. A fifth in one place and not the other is the drift this list
/// exists to stop.
@Test func theTrackMenuMatchesThePlanner() {
    #expect(Set(StoreValues.googleTracks.map(\.value)) == Planner.standardGoogleTracks)
}

/// `GoogleApply` sends one of two withdrawal rights. The menu offers both and
/// invents no third.
@Test func theWithdrawalRightsAreTheOnesTheRunSends() {
    #expect(Set(StoreValues.withdrawalRights.map(\.value))
        == ["WITHDRAWAL_RIGHT_DIGITAL_CONTENT", "WITHDRAWAL_RIGHT_SERVICE"])
}

// MARK: - ChoiceText

@Test func aKnownValueReadsAsWordsAndAnUnknownOneReadsAsItself() {
    #expect(ChoiceText.label(for: "FOOD_AND_DRINK", in: StoreValues.appleCategories)
        == "Food and drink")
    #expect(ChoiceText.label(for: "SOMETHING_APPLE_ADDED", in: StoreValues.appleCategories)
        == "SOMETHING_APPLE_ADDED")
}

@Test func aListRoundTripsThroughTheCommaText() {
    #expect(ChoiceText.values(from: " USA , GBR ,, DEU ") == ["USA", "GBR", "DEU"])
    #expect(ChoiceText.text(from: ["USA", "GBR"]) == "USA, GBR")
    #expect(ChoiceText.values(from: "").isEmpty)
}

/// The summary is the line the developer reads instead of the codes.
@Test func theSummaryNamesTheCountriesAndNotTheCodes() {
    let text = ChoiceText.summary(of: "USA, GBR", in: StoreValues.appleTerritories,
                                  empty: "Every territory")
    #expect(text.contains("United States"))
    #expect(text.contains("United Kingdom"))
    #expect(ChoiceText.summary(of: "", in: StoreValues.appleTerritories,
                               empty: "Every territory") == "Every territory")
}

/// Picking adds, picking again removes, and the order the developer built
/// survives both.
@Test func togglingAddsThenRemovesAndKeepsTheOrder() {
    var text = "USA, GBR"
    text = ChoiceText.toggling("DEU", in: text)
    #expect(text == "USA, GBR, DEU")
    text = ChoiceText.toggling("GBR", in: text)
    #expect(text == "USA, DEU")
    text = ChoiceText.toggling("USA", in: text)
    text = ChoiceText.toggling("DEU", in: text)
    #expect(text.isEmpty)
}

/// A value this build has never heard of has to appear in the chooser. Hiding
/// it would mean the next click silently dropped it from `store.yaml`.
@Test func aValueOutsideTheListStillGetsARow() {
    let rows = ChoiceText.rows(for: "ZZZ, USA", in: StoreValues.appleTerritories)
    #expect(rows.first?.value == "ZZZ")
    #expect(rows.first?.label == "ZZZ")
    #expect(rows.count == StoreValues.appleTerritories.count + 1)
}
