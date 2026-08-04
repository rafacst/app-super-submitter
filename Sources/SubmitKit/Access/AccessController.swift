import Foundation

/// The one question every mutation boundary asks before it writes.
///
/// It is a protocol so the boundary cannot be built without an answer to it.
/// A boolean parameter with a default would be forgotten on the next write
/// somebody adds, and a forgotten gate is an open gate.
public protocol AccessGate: Sendable {
    /// Confirms the capability, refreshing first when the cached document is
    /// stale. It throws rather than returning false, so a caller cannot pass
    /// the gate by ignoring the result.
    func authorize(_ capability: AccessCapability) async throws
}

/// Where the signed document rests between launches.
public protocol EntitlementStoring: Sendable {
    func load() throws -> SignedEntitlement?
    func save(_ document: SignedEntitlement) throws
    func clear() throws
}

/// The bearer token of the signed-in account.
///
/// Returning nil means nobody is signed in, which is free access. Supabase
/// Auth fills this in; nothing else in the app knows where the token is from.
public typealias AccountTokenProvider = @Sendable () async throws -> String?

/// Holds the current entitlement, refreshes it, and answers every gate.
///
/// `// ponytail: one controller, one cached document. Per-capability caching
/// // would add three expiry clocks to keep in step, and all paid plans grant
/// // the same three capabilities.`
public actor AccessController: AccessGate {
    private let client: any LicensingClient
    private let verifier: EntitlementVerifier
    private let store: any EntitlementStoring
    private let token: AccountTokenProvider
    private let now: @Sendable () -> Date

    private var document: SignedEntitlement?
    private var entitlement: Entitlement?

    public init(client: any LicensingClient, verifier: EntitlementVerifier,
                store: any EntitlementStoring, token: @escaping AccountTokenProvider,
                now: @escaping @Sendable () -> Date = { Date() }) {
        self.client = client
        self.verifier = verifier
        self.store = store
        self.token = token
        self.now = now
    }

    /// Reads the document the last session left in the Keychain.
    ///
    /// A document that fails verification is deleted rather than kept. Keeping
    /// an unverifiable blob only makes the next failure harder to explain.
    public func loadCachedDocument() {
        guard let stored = try? store.load() else { return }
        guard let verified = try? verifier.verify(stored, at: now()) else {
            try? store.clear()
            return
        }
        document = stored
        entitlement = verified
    }

    /// What the app shows. It never authorizes anything on its own.
    public var current: Entitlement {
        guard let entitlement, entitlement.expiresAt > now() else {
            return .free(at: now())
        }
        return entitlement
    }

    /// The read the UI uses to draw a lock. `authorize` is what a write uses.
    public func can(_ capability: AccessCapability) -> Bool {
        current.grants(capability)
    }

    public var needsRefresh: Bool {
        guard let entitlement else { return true }
        return now() >= entitlement.refreshAfter
    }

    /// The bearer token of the signed-in account, for the billing routes that
    /// are not entitlement reads: checkout, restore, and the portal.
    public func currentToken() async throws -> String? {
        try await token()
    }

    /// Asks the service for the current document and stores it.
    @discardableResult
    public func refresh() async throws -> Entitlement {
        guard verifier.isConfigured else { throw AccessError.licensingNotConfigured }
        guard let bearer = try await token(), !bearer.isEmpty else {
            // Signing out is not a failure. It is free access, and the cached
            // document of the previous account must not survive it.
            forget()
            throw AccessError.signedOut
        }
        let fresh = try await client.entitlement(idToken: bearer)
        let verified = try verifier.verify(fresh, at: now(), subject: entitlement?.subject)
        document = fresh
        entitlement = verified
        try? store.save(fresh)
        return verified
    }

    public func authorize(_ capability: AccessCapability) async throws {
        if needsRefresh {
            do {
                _ = try await refresh()
            } catch let error as AccessError where error == .signedOut {
                throw error
            } catch {
                // An unexpired document survives a failed refresh. That is the
                // whole point of signing it: the service being down for an
                // hour must not stop a paying developer mid-release.
                guard let entitlement, entitlement.expiresAt > now() else {
                    throw AccessError.refreshRequired
                }
                _ = entitlement
            }
        }
        guard current.grants(capability) else {
            throw AccessError.notEntitled(capability)
        }
    }

    /// Signing out, and the reaction to a revoked grant. It removes the
    /// document and nothing else. Projects, manifests, builds, and store
    /// credentials are the developer's and stay where they are.
    public func forget() {
        document = nil
        entitlement = nil
        try? store.clear()
    }
}

/// The Keychain, through the store the credentials already use.
public struct KeychainEntitlementStore: EntitlementStoring {
    private let account: String

    public init(account: String = "entitlement") { self.account = account }

    public func load() throws -> SignedEntitlement? {
        try KeychainCredentials.load(SignedEntitlement.self, kind: .license, account: account)
    }

    public func save(_ document: SignedEntitlement) throws {
        try KeychainCredentials.save(document, kind: .license, account: account)
    }

    public func clear() throws {
        try KeychainCredentials.delete(kind: .license, account: account)
    }
}

/// For a test and for a build with no Keychain access.
public final class MemoryEntitlementStore: EntitlementStoring, @unchecked Sendable {
    private let lock = NSLock()
    private var stored: SignedEntitlement?

    public init(_ stored: SignedEntitlement? = nil) { self.stored = stored }

    public func load() throws -> SignedEntitlement? {
        lock.lock(); defer { lock.unlock() }
        return stored
    }

    public func save(_ document: SignedEntitlement) throws {
        lock.lock(); defer { lock.unlock() }
        stored = document
    }

    public func clear() throws {
        lock.lock(); defer { lock.unlock() }
        stored = nil
    }
}
