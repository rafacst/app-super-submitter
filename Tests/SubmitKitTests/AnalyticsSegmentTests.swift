import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// The last mile of the analytics feed: the bytes.
///
/// `AppleReportsClient` could already ask for the feeds, the reports, the
/// instances and the segments, and a segment is a URL nothing ever fetched, so
/// the feed stopped one call short of any number. These cover the fetch, the
/// unpacking, and the one thing the App Store Connect API reference does not
/// answer: which columns a report actually carries.
private final class SegmentStub: URLProtocol, @unchecked Sendable {
    nonisolated(unsafe) private static var body = Data()
    nonisolated(unsafe) private static var seen: [URLRequest] = []
    private static let lock = NSLock()

    static func start(_ payload: Data) {
        lock.withLock { body = payload; seen = [] }
    }

    static var requests: [URLRequest] { lock.withLock { seen } }

    override class func canInit(with request: URLRequest) -> Bool { true }
    override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

    override func startLoading() {
        Self.lock.withLock { Self.seen.append(request) }
        let response = HTTPURLResponse(url: request.url!, statusCode: 200,
                                       httpVersion: nil, headerFields: nil)!
        client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
        client?.urlProtocol(self, didLoad: Self.lock.withLock { Self.body })
        client?.urlProtocolDidFinishLoading(self)
    }

    override func stopLoading() {}
}

@Suite(.serialized)
struct AnalyticsSegmentTests {

    private func client(_ payload: Data) throws -> AppleReportsClient {
        SegmentStub.start(payload)
        let configuration = URLSessionConfiguration.ephemeral
        configuration.protocolClasses = [SegmentStub.self]
        let credential = AppleCredential(
            keyID: "ABCD123456", issuerID: "issuer",
            privateKeyPEM: P256.Signing.PrivateKey().pemRepresentation,
            fileName: "AuthKey_ABCD123456.p8")
        return AppleReportsClient(api: StoreAPI(
            credentials: StoreCredentials(apple: credential), record: { _ in },
            session: URLSession(configuration: configuration)))
    }

    /// A gzip container, built the way `Gzip` unpacks one.
    private func gzipped(_ text: String) throws -> Data {
        let raw = Data(text.utf8)
        let deflated = try (raw as NSData).compressed(using: .zlib) as Data
        var out = Data([0x1f, 0x8b, 0x08, 0x00, 0, 0, 0, 0, 0x00, 0x03])
        out.append(deflated)
        var crc = UInt32(0).littleEndian
        var size = UInt32(raw.count).littleEndian
        withUnsafeBytes(of: &crc) { out.append(contentsOf: $0) }
        withUnsafeBytes(of: &size) { out.append(contentsOf: $0) }
        return out
    }

    // MARK: - The fetch

    @Test func aSegmentIsFetchedAndUnpacked() async throws {
        let csv = "Date,Product Page ID,Impressions\n2026-08-01,dinner,120\n"
        let reports = try client(try gzipped(csv))

        let text = try await reports.segmentText(AppleReportsClient.Segment(
            id: "s1", url: "https://reportstorage.example.com/segment-1?sig=abc"))

        #expect(text == csv)
    }

    /// The token may not travel to the segment host.
    ///
    /// A segment lives on a signed storage URL and not on
    /// `api.appstoreconnect.apple.com`. A bearer token sent to a host outside
    /// the API is a token handed to that host, and the signature in the URL is
    /// the whole of the authorisation.
    @Test func theSegmentFetchCarriesNoBearerToken() async throws {
        let reports = try client(try gzipped("a,b\n1,2\n"))

        _ = try await reports.segmentText(AppleReportsClient.Segment(
            id: "s1", url: "https://reportstorage.example.com/segment-1?sig=abc"))

        let request = try #require(SegmentStub.requests.last)
        #expect(request.value(forHTTPHeaderField: "Authorization") == nil)
        #expect(request.url?.host == "reportstorage.example.com")
    }

    /// A reader that throws on a file it can read shows nothing for it.
    @Test func aSegmentThatIsNotGzippedIsStillRead() async throws {
        let csv = "Date,Impressions\n2026-08-01,7\n"
        let reports = try client(Data(csv.utf8))

        let text = try await reports.segmentText(AppleReportsClient.Segment(
            id: "s1", url: "https://reportstorage.example.com/segment-1"))

        #expect(text == csv)
    }

    @Test func aSegmentWithNoURLIsNotAFetch() async throws {
        let reports = try client(Data())
        await #expect(throws: (any Error).self) {
            _ = try await reports.segmentText(AppleReportsClient.Segment(id: "s1"))
        }
    }

    // MARK: - What the account actually returns

    /// The API reference documents the transport and never the columns, so the
    /// only way to know what a report carries is to read its header row.
    @Test func theColumnsAreTheHeaderRowWhicheverSeparatorIsUsed() {
        #expect(AppleReportsClient.columns("Date,Product Page ID,Impressions\n2026,x,1")
                == ["Date", "Product Page ID", "Impressions"])
        #expect(AppleReportsClient.columns("Date\tImpressions\n2026\t1")
                == ["Date", "Impressions"])
        #expect(AppleReportsClient.columns("").isEmpty)
    }

    /// Nothing in the App Store Connect API reference names an experiment or a
    /// treatment dimension in any analytics report. So the app looks for one
    /// rather than assuming it, and says so when there is none.
    @Test func aTreatmentColumnIsFoundOnlyWhenTheReportCarriesOne() {
        #expect(AppleReportsClient.treatmentColumns(
            ["Date", "Experiment Treatment", "Impressions"]) == ["Experiment Treatment"])
        #expect(AppleReportsClient.treatmentColumns(
            ["Date", "Product Page ID", "Impressions"]).isEmpty)
    }

    /// A report holds a daily, a weekly and a monthly instance at once, and an
    /// experiment that has run nine days is a daily question. Picking the
    /// newest of all three answered it with last month's figures.
    @Test func theNewestInstanceIsPickedWithinOneGranularity() {
        let all = [
            AppleReportsClient.Instance(id: "d1", granularity: "DAILY",
                                        processingDate: "2026-08-08"),
            AppleReportsClient.Instance(id: "d2", granularity: "DAILY",
                                        processingDate: "2026-08-09"),
            AppleReportsClient.Instance(id: "m1", granularity: "MONTHLY",
                                        processingDate: "2026-08-31"),
        ]
        #expect(AppleReportsClient.newest(all, granularity: "DAILY")?.id == "d2")
        #expect(AppleReportsClient.newest(all, granularity: "WEEKLY") == nil)
        #expect(AppleReportsClient.newest([], granularity: "DAILY") == nil)
    }

    /// The report the engagement numbers would come from, picked by category
    /// rather than by a name this app invented.
    @Test func theEngagementReportsArePickedByCategory() {
        let all = [
            AppleReportsClient.Report(id: "1", name: "App Store Discovery and Engagement",
                                      category: "APP_STORE_ENGAGEMENT"),
            AppleReportsClient.Report(id: "2", name: "App Sessions", category: "APP_USAGE"),
        ]
        #expect(AppleReportsClient.engagement(all).map(\.id) == ["1"])
    }
}
