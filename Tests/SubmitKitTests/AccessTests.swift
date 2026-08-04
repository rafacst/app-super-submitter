import CryptoKit
import Foundation
import Testing
@testable import SubmitKit

/// The gate a test uses when the subject under test is not the paywall.
struct GrantAll: AccessGate {
    func authorize(_ capability: AccessCapability) async throws {}
}

struct GrantNone: AccessGate {
    func authorize(_ capability: AccessCapability) async throws {
        throw AccessError.notEntitled(capability)
    }
}

// MARK: - Helpers

private let paidCapabilities: [AccessCapability] = [.storeWrite, .storeUpload, .storeRelease]

private func paid(at date: Date, subject: String = "usr_1",
                  plan: AccessPlan = .annual,
                  status: EntitlementStatus = .active,
                  refreshAfter: TimeInterval = 3_600,
                  expiresIn: TimeInterval = 7 * 24 * 3_600) -> Entitlement {
    Entitlement(subject: subject, status: status, plan: plan,
                capabilities: paidCapabilities, issuedAt: date,
                refreshAfter: date.addingTimeInterval(refreshAfter),
                expiresAt: date.addingTimeInterval(expiresIn))
}

private func sign(_ entitlement: Entitlement, with key: Curve25519.Signing.PrivateKey,
                  keyId: String = "k1") throws -> SignedEntitlement {
    let payload = Base64URL.encode(try LicensingJSON.encoder.encode(entitlement))
    let signature = try key.signature(for: Data(payload.utf8))
    return SignedEntitlement(payload: payload, signature: Base64URL.encode(signature),
                             keyId: keyId)
}

private func verifier(for key: Curve25519.Signing.PrivateKey,
                      keyId: String = "k1") -> EntitlementVerifier {
    EntitlementVerifier(keys: [keyId: key.publicKey])
}

/// A licensing service that answers with whatever the test set up.
private final class FakeLicensing: LicensingClient, @unchecked Sendable {
    var document: SignedEntitlement?
    var failure: Error?
    private(set) var entitlementCalls = 0

    init(document: SignedEntitlement? = nil, failure: Error? = nil) {
        self.document = document
        self.failure = failure
    }

    func entitlement(idToken: String) async throws -> SignedEntitlement {
        entitlementCalls += 1
        if let failure { throw failure }
        guard let document else { throw AccessError.serviceUnavailable("no document") }
        return document
    }

    func plans() async throws -> BillingPlans { BillingPlans(currency: "USD", plans: []) }
    func restore(idToken: String) async throws -> SignedEntitlement {
        try await entitlement(idToken: idToken)
    }
    func validate(promotionCode: String, plan: String,
                  idToken: String) async throws -> PromotionPreview {
        PromotionPreview(valid: false, plan: plan, subtotal: 0, discount: 0, total: 0,
                         currency: "USD")
    }
    func checkout(plan: String, promotionCode: String?, idempotencyKey: String,
                  idToken: String) async throws -> CheckoutSession {
        CheckoutSession(sessionId: "cs_1", url: URL(string: "https://checkout.example")!)
    }
    func portal(idToken: String) async throws -> PortalSession {
        PortalSession(url: URL(string: "https://portal.example")!)
    }
}

// MARK: - The signature

@Suite struct EntitlementVerifierTests {

    @Test func aDocumentSignedByTheServiceVerifies() throws {
        let key = Curve25519.Signing.PrivateKey()
        let now = Date()
        let result = try verifier(for: key).verify(try sign(paid(at: now), with: key), at: now)
        #expect(result.plan == .annual)
        #expect(result.grants(.storeRelease))
    }

    /// The whole point of the signature: an edited payload is refused.
    @Test func anAlteredPayloadIsRefused() throws {
        let key = Curve25519.Signing.PrivateKey()
        let now = Date()
        var document = try sign(paid(at: now), with: key)
        var forged = paid(at: now)
        forged.plan = .lifetime
        document.payload = Base64URL.encode(try LicensingJSON.encoder.encode(forged))
        #expect(throws: AccessError.invalidSignature) {
            _ = try verifier(for: key).verify(document, at: now)
        }
    }

    @Test func anotherKeysSignatureIsRefused() throws {
        let key = Curve25519.Signing.PrivateKey()
        let now = Date()
        let document = try sign(paid(at: now), with: Curve25519.Signing.PrivateKey())
        #expect(throws: AccessError.invalidSignature) {
            _ = try verifier(for: key).verify(document, at: now)
        }
    }

    @Test func anUnknownKeyIdIsRefused() throws {
        let key = Curve25519.Signing.PrivateKey()
        let now = Date()
        let document = try sign(paid(at: now), with: key, keyId: "retired")
        #expect(throws: AccessError.unknownSigningKey) {
            _ = try verifier(for: key).verify(document, at: now)
        }
    }

    @Test func anExpiredDocumentIsRefused() throws {
        let key = Curve25519.Signing.PrivateKey()
        let issued = Date()
        let document = try sign(paid(at: issued, expiresIn: 60), with: key)
        #expect(throws: AccessError.entitlementExpired) {
            _ = try verifier(for: key).verify(document, at: issued.addingTimeInterval(120))
        }
    }

    /// The clock rollback case, seen from the other side: a document issued
    /// well after this machine's clock is a machine whose clock is wrong.
    @Test func aDocumentFromTheFutureIsRefused() throws {
        let key = Curve25519.Signing.PrivateKey()
        let now = Date()
        let document = try sign(paid(at: now.addingTimeInterval(3_600)), with: key)
        #expect(throws: AccessError.clockMismatch) {
            _ = try verifier(for: key).verify(document, at: now)
        }
    }

    @Test func aDocumentForAnotherAccountIsRefused() throws {
        let key = Curve25519.Signing.PrivateKey()
        let now = Date()
        let document = try sign(paid(at: now, subject: "usr_1"), with: key)
        #expect(throws: AccessError.subjectMismatch) {
            _ = try verifier(for: key).verify(document, at: now, subject: "usr_2")
        }
    }

    @Test func anUnsupportedVersionIsRefused() throws {
        let key = Curve25519.Signing.PrivateKey()
        let now = Date()
        var future = paid(at: now)
        future.version = 2
        #expect(throws: AccessError.unsupportedVersion) {
            _ = try verifier(for: key).verify(try sign(future, with: key), at: now)
        }
    }

    /// The contract in `licensing-api.md`, from the server's side.
    ///
    /// A round trip through this app's own encoder proves nothing about a
    /// service written in another language. This payload is hand-written the
    /// way a Node service emits one: its own key order, a `Z` timestamp, no
    /// fractional seconds, and the optional fields absent.
    @Test func aHandWrittenServerPayloadVerifies() throws {
        let key = Curve25519.Signing.PrivateKey()
        let json = """
        {"status":"active","plan":"lifetime","version":1,\
        "capabilities":["store_write","store_upload","store_release"],\
        "subject":"usr_opaque","email":"developer@example.com",\
        "issuedAt":"2026-08-04T12:00:00Z","refreshAfter":"2026-08-05T00:00:00Z",\
        "expiresAt":"2026-09-03T12:00:00Z"}
        """
        let payload = Base64URL.encode(Data(json.utf8))
        let document = SignedEntitlement(
            payload: payload,
            signature: Base64URL.encode(try key.signature(for: Data(payload.utf8))),
            keyId: "k1")

        var components = DateComponents()
        components.year = 2026; components.month = 8; components.day = 10
        components.timeZone = TimeZone(identifier: "UTC")
        let now = try #require(Calendar(identifier: .gregorian).date(from: components))

        let result = try verifier(for: key).verify(document, at: now, subject: "usr_opaque")
        #expect(result.plan == .lifetime)
        #expect(result.email == "developer@example.com")
        #expect(AccessCapability.allCases.allSatisfy(result.grants))
    }

    /// `licensing-api.md`: a free account gets a signed document with no
    /// capabilities, never a 404. An unsigned answer would be a service
    /// failure, and the client would keep its previous document instead.
    @Test func aSignedFreeDocumentVerifiesAndGrantsNothing() throws {
        let key = Curve25519.Signing.PrivateKey()
        let now = Date()
        var free = paid(at: now)
        free.status = .free
        free.plan = .free
        free.capabilities = []
        let result = try verifier(for: key).verify(try sign(free, with: key), at: now)
        #expect(!result.isPaid)
        #expect(AccessCapability.allCases.allSatisfy { !result.grants($0) })
    }

    /// Small drift between two hosts must not lock a paying user out.
    @Test func aFewSecondsOfClockDriftIsTolerated() throws {
        let key = Curve25519.Signing.PrivateKey()
        let now = Date()
        let document = try sign(paid(at: now.addingTimeInterval(30)), with: key)
        #expect(throws: Never.self) {
            _ = try verifier(for: key).verify(document, at: now)
        }
    }
}

// MARK: - The capabilities

@Suite struct CapabilityTests {

    @Test func freeGrantsNothing() {
        let free = Entitlement.free(at: Date())
        for capability in AccessCapability.allCases {
            #expect(!free.grants(capability))
        }
    }

    @Test(arguments: [AccessPlan.monthly, .annual, .lifetime, .complimentary])
    func everyPaidPlanGrantsTheSameThree(plan: AccessPlan) {
        let entitlement = paid(at: Date(), plan: plan)
        #expect(AccessCapability.allCases.allSatisfy(entitlement.grants))
    }

    /// A failed payment keeps the developer working while Stripe retries.
    @Test func graceStillGrants() {
        #expect(paid(at: Date(), status: .grace).isPaid)
    }

    @Test func expiredGrantsNothing() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let issued = Date()
        let controller = AccessController(
            client: FakeLicensing(document: try sign(paid(at: issued, expiresIn: 60), with: key)),
            verifier: verifier(for: key), store: MemoryEntitlementStore(),
            token: { "token" }, now: { issued })
        _ = try await controller.refresh()
        #expect(await controller.can(.storeRelease))

        // The same controller, one hour later, with the same document.
        let later = AccessController(
            client: FakeLicensing(failure: AccessError.serviceUnavailable("offline")),
            verifier: verifier(for: key),
            store: MemoryEntitlementStore(try sign(paid(at: issued, expiresIn: 60), with: key)),
            token: { "token" }, now: { issued.addingTimeInterval(3_600) })
        await later.loadCachedDocument()
        #expect(!(await later.can(.storeRelease)))
    }
}

// MARK: - The controller

@Suite struct AccessControllerTests {

    @Test func anUnexpiredDocumentSurvivesAFailedRefresh() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let issued = Date()
        let client = FakeLicensing(document: try sign(paid(at: issued), with: key))
        let controller = AccessController(
            client: client, verifier: verifier(for: key), store: MemoryEntitlementStore(),
            token: { "token" }, now: { issued })
        _ = try await controller.refresh()

        client.failure = AccessError.serviceUnavailable("offline")
        // Past `refreshAfter`, so `authorize` tries the service and fails.
        let offline = AccessController(
            client: client, verifier: verifier(for: key),
            store: MemoryEntitlementStore(try sign(paid(at: issued), with: key)),
            token: { "token" }, now: { issued.addingTimeInterval(2 * 3_600) })
        await offline.loadCachedDocument()
        await #expect(throws: Never.self) { try await offline.authorize(.storeWrite) }
    }

    /// Fail closed: no cache, no service, no write.
    @Test func noCacheAndNoServiceRefusesTheWrite() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let controller = AccessController(
            client: FakeLicensing(failure: AccessError.serviceUnavailable("offline")),
            verifier: verifier(for: key), store: MemoryEntitlementStore(),
            token: { "token" })
        await #expect(throws: AccessError.refreshRequired) {
            try await controller.authorize(.storeWrite)
        }
    }

    @Test func aSignedOutAccountIsFreeAndSaysSo() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let controller = AccessController(
            client: FakeLicensing(), verifier: verifier(for: key),
            store: MemoryEntitlementStore(), token: { nil })
        await #expect(throws: AccessError.signedOut) {
            try await controller.authorize(.storeRelease)
        }
    }

    /// A tampered blob in the Keychain is deleted, not trusted.
    @Test func anUnverifiableCachedDocumentIsDiscarded() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let now = Date()
        let store = MemoryEntitlementStore(
            try sign(paid(at: now), with: Curve25519.Signing.PrivateKey()))
        let controller = AccessController(
            client: FakeLicensing(), verifier: verifier(for: key), store: store,
            token: { "token" }, now: { now })
        await controller.loadCachedDocument()
        #expect(!(await controller.can(.storeWrite)))
        #expect(try store.load() == nil)
    }

    @Test func aFreshDocumentIsCachedForTheNextLaunch() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let now = Date()
        let store = MemoryEntitlementStore()
        let controller = AccessController(
            client: FakeLicensing(document: try sign(paid(at: now), with: key)),
            verifier: verifier(for: key), store: store, token: { "token" }, now: { now })
        _ = try await controller.refresh()
        #expect(try store.load() != nil)

        await controller.forget()
        #expect(try store.load() == nil)
        #expect(!(await controller.can(.storeWrite)))
    }

    /// A valid document inside its refresh window costs no network call.
    @Test func aRecentDocumentIsNotRefetchedOnEveryWrite() async throws {
        let key = Curve25519.Signing.PrivateKey()
        let now = Date()
        let client = FakeLicensing(document: try sign(paid(at: now), with: key))
        let controller = AccessController(
            client: client, verifier: verifier(for: key), store: MemoryEntitlementStore(),
            token: { "token" }, now: { now })
        _ = try await controller.refresh()
        try await controller.authorize(.storeWrite)
        try await controller.authorize(.storeUpload)
        #expect(client.entitlementCalls == 1)
    }
}

// MARK: - The mutation boundaries

/// The runner emits from its own actor, so a local variable cannot collect it.
private final class EventBox: @unchecked Sendable {
    private let lock = NSLock()
    private var failure: String?
    private var done = false

    func record(_ event: RunEvent) {
        lock.lock(); defer { lock.unlock() }
        if case .failure(let value) = event, failure == nil { failure = value.message }
        if case .finished = event { done = true }
    }

    var failureMessage: String? {
        lock.lock(); defer { lock.unlock() }
        return failure
    }

    var finished: Bool {
        lock.lock(); defer { lock.unlock() }
        return done
    }
}

@Suite struct MutationGateTests {

    private func onePlan() -> PlanResult {
        var plan = PlanResult()
        plan.steps = [PlanStep(id: "apple.version", system: .apple, kind: .add,
                               summary: "Create the version", title: "Version",
                               requests: [RequestSketch("PATCH", "/v1/appStoreVersions/1")],
                               operation: .appleVersionAttributes)]
        return plan
    }

    /// The lowest boundary. A stale screen, a menu command, or a second entry
    /// point added later all still arrive here.
    @Test func aNonDryRunWithoutAccessFailsBeforeAnyRequest() async {
        let events = EventBox()
        let runner = Runner(plan: onePlan(), manifest: Manifest(), actual: ActualState(),
                            root: nil, credentials: StoreCredentials(), dryRun: false,
                            access: GrantNone(), emit: { events.record($0) })
        await runner.run()
        #expect(events.failureMessage?.contains("paid access") == true)
        #expect(!events.finished)
    }

    /// The free half stays free: a dry run never asks the gate anything.
    @Test func aDryRunNeedsNoAccess() async {
        let events = EventBox()
        let runner = Runner(plan: onePlan(), manifest: Manifest(), actual: ActualState(),
                            root: nil, credentials: StoreCredentials(), dryRun: true,
                            access: GrantNone(), emit: { events.record($0) })
        await runner.run()
        #expect(events.finished)
        #expect(events.failureMessage == nil)
    }

    @Test func everyReleaseCallRefusesWithoutAccess() async {
        let client = ReleaseClient(api: StoreAPI(credentials: StoreCredentials(),
                                                 record: { _ in }),
                                   access: GrantNone())
        await #expect(throws: AccessError.notEntitled(.storeRelease)) {
            _ = try await client.releaseApple(appID: "1", platform: "IOS", versionID: "2")
        }
        await #expect(throws: AccessError.notEntitled(.storeRelease)) {
            _ = try await client.releaseApprovedAppleVersion(versionID: "2")
        }
        await #expect(throws: AccessError.notEntitled(.storeRelease)) {
            try await client.cancelAppleSubmission(id: "3")
        }
        await #expect(throws: AccessError.notEntitled(.storeRelease)) {
            _ = try await client.releaseGoogle(packageName: "com.example", track: "production",
                                               status: "completed", userFraction: nil,
                                               versionName: "1.0")
        }
        await #expect(throws: AccessError.notEntitled(.storeRelease)) {
            try await client.haltGoogleRollout(packageName: "com.example", track: "production")
        }
    }

    @Test func theGoogleUploadRefusesWithoutAccess() async {
        let service = UploadService(api: StoreAPI(credentials: StoreCredentials(),
                                                  record: { _ in }))
        await #expect(throws: AccessError.notEntitled(.storeUpload)) {
            _ = try await service.uploadGoogleBundle(
                packageName: "com.example", track: "internal",
                bundle: URL(fileURLWithPath: "/dev/null"), expectedVersionCode: 1,
                versionName: "1.0", access: GrantNone(), onProgress: { _ in })
        }
    }
}

// MARK: - The error surface

@Suite struct AccessErrorTests {

    /// Every message names what still works. A gate that only says "no" reads
    /// as a broken app.
    @Test(arguments: AccessCapability.allCases)
    func everyRefusalNamesWhatStaysFree(capability: AccessCapability) {
        let text = AccessError.notEntitled(capability).errorDescription ?? ""
        #expect(text.contains("paid access"))
        #expect(!text.contains("unlicensed"))
        #expect(!text.contains("—"))
    }

    @Test func codesAreStableAndCarryNoIdentity() {
        #expect(AccessError.signedOut.code == "authentication_required")
        #expect(AccessError.refreshRequired.code == "entitlement_refresh_required")
        #expect(AccessError.server(code: "already_subscribed", message: "x").code
                == "already_subscribed")
    }
}
