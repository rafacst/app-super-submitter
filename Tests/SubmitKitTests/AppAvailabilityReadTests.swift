import Foundation
import Testing
@testable import SubmitKit

/// The read behind the Availability tab.
///
/// The territory id is on the relationship and never on the row itself, so a
/// parser that reads the row's own id fills the screen with opaque record ids
/// instead of countries.
@Test func theTerritoryIdComesOffTheRelationship() {
    let payload = JSON(data: Data("""
    {"included":[
      {"id":"ta-bra","type":"territoryAvailabilities",
       "attributes":{"available":true},
       "relationships":{"territory":{"data":{"id":"BRA","type":"territories"}}}},
      {"id":"ta-usa","type":"territoryAvailabilities",
       "attributes":{"available":false},
       "relationships":{"territory":{"data":{"id":"USA","type":"territories"}}}},
      {"id":"BRA","type":"territories","attributes":{"currency":"BRL"}}
    ]}
    """.utf8))

    var result = StoreDiagnostics.Availability()
    StoreDiagnostics.readTerritoryAvailabilities(payload["included"], into: &result)

    // The territories in the same payload are not availabilities, and counting
    // them would report an app as selling where it does not.
    #expect(result.territories == ["BRA": true, "USA": false])
}

/// A row with no territory behind it is skipped, not counted as a country.
@Test func aRowWithNoTerritoryIsNotACountry() {
    let payload = JSON(data: Data("""
    {"data":[{"id":"ta-1","type":"territoryAvailabilities",
              "attributes":{"available":true}}]}
    """.utf8))

    var result = StoreDiagnostics.Availability()
    StoreDiagnostics.readTerritoryAvailabilities(payload["data"], into: &result)

    #expect(result.territories.isEmpty)
}
