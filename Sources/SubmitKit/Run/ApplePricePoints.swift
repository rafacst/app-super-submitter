import Foundation

/// Every price the App Store sells at, for one product and one territory.
///
/// App Store Connect does not accept a typed amount. It offers a ladder of
/// price points and takes one of them, which is why the web form's price field
/// is a menu and not a box.
///
/// Apple lists around 900 points per territory and answers 200 of them at a
/// time. Every call site here asked for one page and stopped, so the ladder the
/// app worked from was an arbitrary slice of the real one: the picker on the
/// Monetization tab offered a fraction of the prices, and the apply resolved
/// the developer's amount to the nearest point *in that fraction*. A request of
/// 49.99 could ship as the highest price on page one. Nothing is nearest until
/// the list is whole.
public enum ApplePricePoints {
    public struct Point: Sendable, Equatable {
        public let id: String
        public let amount: Decimal
    }

    /// The ladder one app sells at, in one territory. The Monetization tab
    /// reads this on its own, so a developer who has connected a key gets the
    /// prices without running a whole store read first.
    ///
    /// The path stays on one line. `StorePathTests` reads the sources for the
    /// spelling that App Store Connect answers, and a path split across a `+`
    /// is a path that test cannot see.
    public static func app(_ api: StoreAPI, appID: String,
                           territory: String) async throws -> [Point] {
        try await all(api, path: "/v1/apps/\(appID)/appPricePoints?filter%5Bterritory%5D=\(territory)")
    }

    /// Follows `links.next` to the end of the ladder.
    ///
    /// `path` carries the territory filter; the page size belongs here.
    static func all(_ api: StoreAPI, path: String) async throws -> [Point] {
        var next: String? = path + (path.contains("?") ? "&" : "?") + "limit=200"
        var seen: Set<String> = []
        var result: [Point] = []
        // A ladder is under a thousand rows. The cap stops a next link that
        // points at itself, and is not a budget for the pages.
        while let current = next, seen.insert(current).inserted, result.count < 4_000 {
            let payload = JSON(data: try await api.apple("GET", current).data)
            result.append(contentsOf: Self.points(in: payload))
            next = payload["links"]["next"].string.flatMap(StoreDiagnostics.appleNextPath)
        }
        return result
    }

    /// One page, as ids and amounts. Apple sends `customerPrice` as a string,
    /// so the decimal never goes near a `Double`.
    static func points(in payload: JSON) -> [Point] {
        payload["data"].array.compactMap { item in
            guard let id = item["id"].string,
                  let text = item["attributes"]["customerPrice"].string,
                  let amount = Decimal(string: text) else { return nil }
            return Point(id: id, amount: amount)
        }
    }

    /// The point Apple resolves a request to.
    static func nearest(_ points: [Point], to amount: Decimal) -> Point? {
        points.min { abs($0.amount - amount) < abs($1.amount - amount) }
    }
}
