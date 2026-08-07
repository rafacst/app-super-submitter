import CryptoKit
import Foundation
import SubmitKit
import Testing
@testable import SuperSubmitter

/// A document this Mac cannot verify is not the same as an account that has not
/// paid, and the app must never draw them the same way.
///
/// The bug this guards cost a real payment its access in silence.
/// `refreshEntitlement` was `try? await controller.refresh()`, so a wrong
/// signing key, a replayed subject, or a skewed clock all fell into the same
/// `else` branch as "free account", and the tab said Free with no reason on a
/// Mac whose card had already been charged.
@MainActor
struct EntitlementProblemTests {

    /// Which failures are loud and which are ordinary.
    ///
    /// Being offline, being signed out, and not having paid are normal states,
    /// and an alarm on every launch for any of them teaches the developer to
    /// ignore the one that matters.
    @Test func theLoudFailuresAreToldApartFromTheOrdinaryOnes() {
        let loud: [AccessError] = [
            .invalidSignature, .malformedEntitlement, .unknownSigningKey,
            .unsupportedVersion, .subjectMismatch, .clockMismatch,
            .configurationInvalid, .licensingNotConfigured,
        ]
        let quiet: [AccessError] = [
            .signedOut, .entitlementExpired, .refreshRequired,
            .serviceUnavailable("offline"), .notEntitled(.storeWrite),
            .server(code: "promotion_code_invalid", message: "no"),
        ]
        for error in loud {
            #expect(error.isVerificationFailure, "\(error.code) must be reported")
        }
        for error in quiet {
            #expect(!error.isVerificationFailure, "\(error.code) must not raise the alarm")
        }
    }

    /// The capability strings the service must send.
    ///
    /// The wire form is snake_case and the Swift case names are not. A brief
    /// written from the case names sent a Worker agent to change a correct
    /// service, so the contract is asserted here rather than remembered.
    @Test func theCapabilityWireNamesAreSnakeCase() {
        #expect(AccessCapability.storeWrite.rawValue == "store_write")
        #expect(AccessCapability.storeUpload.rawValue == "store_upload")
        #expect(AccessCapability.storeRelease.rawValue == "store_release")
        #expect(AccessPlan.lifetime.rawValue == "lifetime")
        #expect(EntitlementStatus.active.rawValue == "active")
    }

    /// A payload this build cannot parse must arrive as an `AccessError`.
    ///
    /// `status`, `plan`, and every capability decode into string enums, so one
    /// unknown value throws a `DecodingError`, which is not an `AccessError`,
    /// which every handler in the app switches on. Before it was wrapped, a
    /// capability spelled the other way took a paying account's access away
    /// with nothing on screen and no code to report.
    ///
    /// A real key and a real signature, so the failure under test is the
    /// payload and provably not the envelope.
    @Test func anUnreadablePayloadIsAMalformedEntitlementAndNotARawDecodingError() throws {
        let key = Curve25519.Signing.PrivateKey()
        let verifier = try EntitlementVerifier(
            base64Keys: ["k": key.publicKey.rawRepresentation.base64EncodedString()])
        let now = Date(timeIntervalSince1970: 1_800_000_000)

        func document(capability: String) throws -> SignedEntitlement {
            let json = """
            {"version":1,"subject":"u","status":"active","plan":"annual",\
            "capabilities":["\(capability)"],"issuedAt":"2027-01-15T00:00:00Z",\
            "refreshAfter":"2027-01-16T00:00:00Z","expiresAt":"2027-02-15T00:00:00Z"}
            """
            let payload = Self.base64URL(Data(json.utf8))
            return SignedEntitlement(
                payload: payload,
                signature: Self.base64URL(try key.signature(for: Data(payload.utf8))),
                keyId: "k")
        }

        // The near miss: the Swift case name instead of the wire name.
        #expect(throws: AccessError.malformedEntitlement) {
            _ = try verifier.verify(try document(capability: "storeWrite"), at: now)
        }
        // The same document with the wire spelling verifies, which proves the
        // case above failed on the spelling and not on the rest of it.
        let good = try verifier.verify(try document(capability: "store_write"), at: now)
        #expect(good.capabilities == [AccessCapability.storeWrite])
        #expect(good.plan == .annual)
        #expect(good.status == .active)
    }

    /// base64url without padding, the encoding both document fields use.
    private static func base64URL(_ data: Data) -> String {
        data.base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}
