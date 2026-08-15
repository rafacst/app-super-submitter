import Foundation

/// What `xcrun` reported about the selected toolchain. upload-spec 8.1.
public struct AppleToolchain: Sendable, Equatable {
    public var developerDirectory: String = ""
    public var xcodeVersion: String = ""
    public var buildVersion: String = ""
    /// Present when the toolchain cannot build. Discovery stops here.
    public var failure: BuildFailure?

    public var label: String {
        xcodeVersion.isEmpty ? developerDirectory : "Xcode \(xcodeVersion) (\(buildVersion))"
    }
}

/// `xcodebuild -list -json`.
public struct XcodeContainerInfo: Sendable, Equatable {
    public var name: String = ""
    public var schemes: [String] = []
    public var configurations: [String] = []
    public var targets: [String] = []
}

/// The build settings that the preflight snapshot reads. upload-spec 8.4.
public struct AppleBuildSettings: Sendable, Equatable {
    public var values: [String: String] = [:]

    public subscript(_ key: String) -> String? {
        let value = values[key]
        return (value?.isEmpty ?? true) ? nil : value
    }

    public var productName: String? { self["PRODUCT_NAME"] }
    public var bundleIdentifier: String? { self["PRODUCT_BUNDLE_IDENTIFIER"] }
    public var marketingVersion: String? { self["MARKETING_VERSION"] }
    public var currentProjectVersion: String? { self["CURRENT_PROJECT_VERSION"] }
    public var team: String? { self["DEVELOPMENT_TEAM"] }
    public var signingStyle: String? { self["CODE_SIGN_STYLE"] }
    public var signingIdentity: String? { self["CODE_SIGN_IDENTITY"] }
    public var provisioningProfile: String? { self["PROVISIONING_PROFILE_SPECIFIER"] }
    public var sdkRoot: String? { self["SDKROOT"] }

    /// The keys that upload-spec 8.4 requires the preflight to read.
    public static let required = [
        "PRODUCT_NAME", "PRODUCT_BUNDLE_IDENTIFIER", "MARKETING_VERSION",
        "CURRENT_PROJECT_VERSION", "DEVELOPMENT_TEAM", "CODE_SIGN_STYLE",
        "CODE_SIGN_IDENTITY", "PROVISIONING_PROFILE_SPECIFIER", "SDKROOT",
        "SUPPORTED_PLATFORMS", "TARGETED_DEVICE_FAMILY", "INFOPLIST_FILE",
        "WRAPPER_EXTENSION", "SKIP_INSTALL", "INSTALL_PATH",
    ]
}

/// What the built `.xcarchive` actually holds. This, not the preflight, is the
/// truth. upload-spec 8.12.
public struct ArchiveInfo: Sendable, Equatable {
    public var applicationName = ""
    public var bundleIdentifier = ""
    public var shortVersion = ""
    public var buildVersion = ""
    public var platform: BuildPlatform = .ios
    public var minimumOS: String?
    public var applicationPath = ""
    public var signingIdentity: String?
    public var team: String?
    public var profileName: String?
    public var size: Int64 = 0
    public var eligibleApplications: [String] = []
    public var signatureVerified: Bool?
    public var signatureDetail: String?
}

/// Runs Xcode. upload-spec section 8.
///
/// Every command is `/usr/bin/xcrun` plus an argument array. Nothing here
/// builds a command string, and nothing here writes inside the developer's
/// repository.
public struct AppleBuildService: Sendable {
    static let xcrun = URL(fileURLWithPath: "/usr/bin/xcrun")
    static let xcodeSelect = URL(fileURLWithPath: "/usr/bin/xcode-select")
    static let codesign = URL(fileURLWithPath: "/usr/bin/codesign")

    private let runner: any ToolRunning
    private let storage: BuildStorage

    public init(runner: any ToolRunning = ToolProcess(), storage: BuildStorage = BuildStorage()) {
        self.runner = runner
        self.storage = storage
    }

    // MARK: - 8.1 Toolchain preflight

    /// Read-only. It never runs `sudo`, accepts a licence, installs a
    /// component, or changes the active developer directory.
    public func toolchain() async throws -> AppleToolchain {
        var result = AppleToolchain()

        let selected = try? await run(Self.xcodeSelect, ["-p"], phase: "Resolve Xcode")
        result.developerDirectory = selected?.standardOutput
            .trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        if result.developerDirectory.isEmpty {
            result.failure = BuildFailure(
                category: .toolchainUnavailable, stage: "Resolve the toolchain",
                message: "No Xcode is selected.",
                recovery: "Install Xcode, then run xcode-select --switch on the Xcode you want.")
            return result
        }
        if result.developerDirectory.contains("CommandLineTools") {
            result.failure = BuildFailure(
                category: .toolchainUnavailable, stage: "Resolve the toolchain",
                message: "Only the Command Line Tools are selected. An archive needs full Xcode.",
                recovery: "Run sudo xcode-select --switch /Applications/Xcode.app in Terminal.")
            return result
        }

        let version = try? await run(Self.xcrun, ["xcodebuild", "-version"],
                                     phase: "Read the Xcode version")
        let lines = (version?.standardOutput ?? "").split(separator: "\n").map(String.init)
        result.xcodeVersion = lines.first?.replacingOccurrences(of: "Xcode ", with: "") ?? ""
        result.buildVersion = lines.count > 1
            ? lines[1].replacingOccurrences(of: "Build version ", with: "") : ""

        if version?.succeeded != true {
            let detail = version?.standardError ?? ""
            let unlicensed = detail.lowercased().contains("license")
                || detail.lowercased().contains("agree")
            result.failure = BuildFailure(
                category: .toolchainUnavailable, stage: "Resolve the toolchain",
                message: unlicensed
                    ? "Xcode's first-launch setup is not complete."
                    : "xcodebuild could not run.",
                underlying: detail.isEmpty ? nil : detail,
                recovery: unlicensed
                    ? "Open Xcode once and accept its licence, or run sudo xcodebuild -license accept."
                    : "Open Xcode once to finish its setup, then press Recheck.")
            return result
        }

        return result
    }

    // MARK: - 8.2 and 8.3 Containers and schemes

    public func list(container: URL,
                     kind: LinkedSourceProject.ContainerKind) async throws -> XcodeContainerInfo {
        let flag = kind == .workspace ? "-workspace" : "-project"
        let outcome = try await run(Self.xcrun,
                                    ["xcodebuild", flag, container.path, "-list", "-json"],
                                    workingDirectory: container.deletingLastPathComponent(),
                                    phase: "List the schemes")
        guard outcome.succeeded else {
            throw BuildFailure(
                category: .configuration, stage: "List the schemes",
                message: "Xcode could not read \(container.lastPathComponent).",
                underlying: outcome.standardError,
                recovery: "Open the project in Xcode and check that it loads.")
        }
        // The JSON form is authoritative. The human-readable form is never
        // scraped when JSON succeeds. upload-spec 8.2.
        let json = JSON(data: Data(outcome.standardOutput.utf8))
        let node = json["workspace"].exists ? json["workspace"] : json["project"]
        var info = XcodeContainerInfo()
        info.name = node["name"].string ?? container.deletingPathExtension().lastPathComponent
        info.schemes = node["schemes"].array.compactMap(\.string)
        info.configurations = node["configurations"].array.compactMap(\.string)
        info.targets = node["targets"].array.compactMap(\.string)
        guard !info.schemes.isEmpty else {
            throw BuildFailure(
                category: .configuration, stage: "List the schemes",
                message: "No scheme is visible to the command line.",
                recovery: "In Xcode open Product, then Scheme, then Manage Schemes, and tick Shared for the scheme you distribute.")
        }
        return info
    }

    // MARK: - 8.4 Build settings

    public func settings(container: URL, kind: LinkedSourceProject.ContainerKind,
                         scheme: String, configuration: String?,
                         platform: BuildPlatform,
                         buildNumber: String? = nil,
                         marketingVersion: String? = nil) async throws -> AppleBuildSettings {
        var arguments = ["xcodebuild", kind == .workspace ? "-workspace" : "-project",
                         container.path, "-scheme", scheme]
        if let configuration, !configuration.isEmpty {
            arguments += ["-configuration", configuration]
        }
        if let destination = platform.appleDestination {
            arguments += ["-destination", destination]
        }
        arguments += ["-showBuildSettings", "-json"]
        // The same overrides the archive will carry, so the preflight reports
        // the number and the version the build will actually use and the
        // conflict check runs against those.
        arguments += Self.buildNumberArguments(buildNumber)
        arguments += Self.marketingVersionArguments(marketingVersion)

        let outcome = try await run(Self.xcrun, arguments,
                                    workingDirectory: container.deletingLastPathComponent(),
                                    phase: "Read the build settings")
        guard outcome.succeeded else {
            throw BuildFailure(
                category: .configuration, stage: "Read the build settings",
                message: "Xcode could not evaluate \(scheme) for \(platform.label).",
                underlying: outcome.standardError,
                recovery: "Check that the scheme supports this platform, then choose another scheme or destination.")
        }
        var result = AppleBuildSettings()
        // The array holds one entry per target. The first entry that carries a
        // bundle identifier is the application; the rest are its extensions.
        let entries = JSON(data: Data(outcome.standardOutput.utf8)).array
        let application = entries.first {
            $0["buildSettings"]["PRODUCT_BUNDLE_IDENTIFIER"].string?.isEmpty == false
                && ($0["buildSettings"]["WRAPPER_EXTENSION"].string ?? "app") == "app"
        } ?? entries.first
        for key in AppleBuildSettings.required {
            result.values[key] = application?["buildSettings"][key].string ?? ""
        }
        return result
    }

    /// A build number chosen in Super Submitter, as Xcode takes it.
    ///
    /// `xcodebuild CURRENT_PROJECT_VERSION=42` overrides the setting for that
    /// one invocation. The project file is not opened and not written, which is
    /// the whole reason the number travels this way: the store refuses a build
    /// number it already holds, and the answer used to be a trip to Xcode.
    ///
    /// Digits only. The value reaches an argument array rather than a shell, so
    /// nothing here can be injected, and a number is the only thing the store
    /// counts with. Anything else, including an empty string, means "the
    /// project decides" and adds no argument at all.
    ///
    /// A project whose `Info.plist` hardcodes `CFBundleVersion` ignores the
    /// setting. That is not silent: the archive inspection reads the built
    /// package and reports the difference before anything is uploaded.
    static func buildNumberArguments(_ buildNumber: String?) -> [String] {
        guard let buildNumber, !buildNumber.isEmpty,
              buildNumber.allSatisfy({ $0.isASCII && $0.isNumber }) else { return [] }
        return ["CURRENT_PROJECT_VERSION=\(buildNumber)"]
    }

    /// The release version from `store.yaml`, as Xcode takes it.
    ///
    /// The same mechanism as the build number above, for the same reason.
    /// `store.yaml` names the version the store will hold and the project
    /// names the one the archive carries. When they disagree the upload is
    /// refused, and it is refused after a whole archive has been built.
    /// `MARKETING_VERSION=1.6` settles it for one invocation, and the project
    /// file is neither opened nor written.
    ///
    /// Digits and dots, nothing else. `CFBundleShortVersionString` is a dotted
    /// number, the value reaches an argument array unquoted, and anything else
    /// means "the project decides" and adds no argument at all.
    ///
    /// A project whose `Info.plist` hardcodes `CFBundleShortVersionString`
    /// ignores the setting. That is not silent: the archive inspection reads
    /// the built package, and `store.yaml version` is a blocking mismatch.
    static func marketingVersionArguments(_ version: String?) -> [String] {
        guard let version, !version.isEmpty,
              version.allSatisfy({ $0.isASCII && ($0.isNumber || $0 == ".") })
        else { return [] }
        return ["MARKETING_VERSION=\(version)"]
    }

    // MARK: - 8.11 Archive

    /// The archive command. It appends no free-form user text, and an exit
    /// status of zero is not enough: the archive must exist at the exact
    /// requested path.
    public func archive(container: URL, kind: LinkedSourceProject.ContainerKind,
                        scheme: String, configuration: String?, platform: BuildPlatform,
                        archivePath: URL, authentication: AppleAuthenticationFiles?,
                        allowProvisioningUpdates: Bool, buildNumber: String? = nil,
                        marketingVersion: String? = nil,
                        onLine: @escaping @Sendable (ToolStream, String) -> Void) async throws
        -> URL {
        var arguments = ["xcodebuild",
                         kind == .workspace ? "-workspace" : "-project", container.path,
                         "-scheme", scheme]
        if let configuration, !configuration.isEmpty {
            arguments += ["-configuration", configuration]
        }
        if let destination = platform.appleDestination {
            arguments += ["-destination", destination]
        }
        arguments += ["-archivePath", archivePath.deletingPathExtension().path, "archive"]
        arguments += authentication?.arguments ?? []
        if allowProvisioningUpdates { arguments.append("-allowProvisioningUpdates") }
        arguments += Self.buildNumberArguments(buildNumber)
        arguments += Self.marketingVersionArguments(marketingVersion)

        let outcome = try await runner.run(
            ToolInvocation(executable: Self.xcrun, arguments: arguments,
                           workingDirectory: container.deletingLastPathComponent(),
                           environment: [:], phase: "Build the archive"),
            onLine: onLine)

        guard outcome.succeeded else {
            throw Self.archiveFailure(outcome)
        }
        guard FileManager.default.fileExists(atPath: archivePath.path) else {
            throw BuildFailure(
                category: .artifactDiscovery, stage: "Build the archive",
                message: "xcodebuild reported success and no archive exists at the requested path.",
                diagnostics: outcome.failureDetail,
                recovery: "Check the build log for a script that moved or removed the archive.")
        }
        return archivePath
    }

    static func archiveFailure(_ outcome: ToolOutcome) -> BuildFailure {
        let text = (outcome.standardError + outcome.standardOutput).lowercased()
        let category: BuildErrorCategory
        let recovery: String
        if text.contains("no profiles for") || text.contains("code signing")
            || text.contains("no signing certificate") {
            category = .signing
            recovery = "Open the project in Xcode and fix the signing for this target. Super Submitter never creates a certificate or a profile."
        } else if text.contains("package resolution") || text.contains("could not resolve")
            || text.contains("pod install") {
            category = .dependencyResolution
            recovery = "Resolve the dependencies in the project once, then build again. Super Submitter never edits a dependency file."
        } else {
            category = .build
            recovery = "Read the diagnostics and the build log, fix the build in the project, then run it again."
        }
        return BuildFailure(
            category: category, stage: "Build the archive",
            message: "The archive failed with exit status \(outcome.status).",
            diagnostics: outcome.failureDetail,
            recovery: recovery)
    }

    // MARK: - 8.12 Authoritative archive inspection

    public func inspect(archive: URL, platform: BuildPlatform) async throws -> ArchiveInfo {
        let plistURL = archive.appendingPathComponent("Info.plist")
        guard let data = try? Data(contentsOf: plistURL),
              let plist = try? PropertyListSerialization.propertyList(
                from: data, format: nil) as? [String: Any] else {
            throw BuildFailure(
                category: .artifactValidation, stage: "Inspect the archive",
                message: "The archive holds no readable Info.plist.",
                recovery: "Build again, then inspect the archive in Finder.")
        }

        var info = ArchiveInfo()
        info.platform = platform
        let properties = plist["ApplicationProperties"] as? [String: Any] ?? [:]
        info.applicationPath = properties["ApplicationPath"] as? String ?? ""
        info.bundleIdentifier = properties["CFBundleIdentifier"] as? String ?? ""
        info.shortVersion = properties["CFBundleShortVersionString"] as? String ?? ""
        info.buildVersion = properties["CFBundleVersion"] as? String ?? ""
        info.signingIdentity = properties["SigningIdentity"] as? String
        info.team = properties["Team"] as? String
        info.profileName = properties["ProfileName"] as? String
        info.applicationName = plist["Name"] as? String
            ?? URL(fileURLWithPath: info.applicationPath).deletingPathExtension()
                .lastPathComponent

        // Read the archived application's own Info.plist. Use the archive's
        // declared product path, never a filesystem-wide search.
        let productsURL = archive.appendingPathComponent("Products")
        let appURL = productsURL.appendingPathComponent(info.applicationPath)
        if let appData = try? Data(contentsOf: appURL.appendingPathComponent("Info.plist")),
           let appPlist = try? PropertyListSerialization.propertyList(
            from: appData, format: nil) as? [String: Any] {
            info.applicationName = appPlist["CFBundleDisplayName"] as? String
                ?? appPlist["CFBundleName"] as? String ?? info.applicationName
            if info.bundleIdentifier.isEmpty {
                info.bundleIdentifier = appPlist["CFBundleIdentifier"] as? String ?? ""
            }
            if info.shortVersion.isEmpty {
                info.shortVersion = appPlist["CFBundleShortVersionString"] as? String ?? ""
            }
            if info.buildVersion.isEmpty {
                info.buildVersion = appPlist["CFBundleVersion"] as? String ?? ""
            }
            info.minimumOS = appPlist["MinimumOSVersion"] as? String
                ?? appPlist["LSMinimumSystemVersion"] as? String
        }

        // An archive can hold more than one eligible app. The export then
        // needs distributionBundleIdentifier. upload-spec 8.13.
        info.eligibleApplications = ((try? FileManager.default.contentsOfDirectory(
            atPath: productsURL.appendingPathComponent("Applications").path)) ?? [])
            .filter { $0.hasSuffix(".app") }
        if info.eligibleApplications.isEmpty, !info.applicationPath.isEmpty {
            info.eligibleApplications = [URL(fileURLWithPath: info.applicationPath)
                .lastPathComponent]
        }

        info.size = Self.size(of: archive)

        // A non-mutating signature diagnostic. The Xcode export step is the
        // final authority for distribution signing.
        var arguments = ["--verify", "--strict", "--verbose=2"]
        if platform == .macos { arguments.append("--deep") }
        arguments.append(appURL.path)
        if let outcome = try? await run(Self.codesign, arguments,
                                        phase: "Verify the signature") {
            info.signatureVerified = outcome.succeeded
            info.signatureDetail = (outcome.standardError + outcome.standardOutput)
                .trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return info
    }

    // MARK: - 8.13 and 8.15 Export and upload

    /// `manageAppVersionAndBuildNumber` is explicitly false. Otherwise Xcode
    /// may change a value that the developer just confirmed.
    public func writeExportOptions(runID: UUID, platform: BuildPlatform, team: String?,
                                   signingStyle: String?,
                                   distributionBundleIdentifier: String?) throws -> URL {
        var options: [String: Any] = [
            "method": "app-store-connect",
            "destination": "upload",
            "manageAppVersionAndBuildNumber": false,
            "uploadSymbols": true,
        ]
        options["signingStyle"] = (signingStyle?.lowercased() == "manual")
            ? "manual" : "automatic"
        if let team, !team.isEmpty { options["teamID"] = team }
        if let distributionBundleIdentifier, !distributionBundleIdentifier.isEmpty {
            options["distributionBundleIdentifier"] = distributionBundleIdentifier
        }
        let data = try PropertyListSerialization.data(fromPropertyList: options,
                                                      format: .xml, options: 0)
        let folder = try storage.makeScratch(runID: runID)
        let file = folder.appendingPathComponent("ExportOptions.plist")
        try data.write(to: file, options: .atomic)
        try FileManager.default.setAttributes([.posixPermissions: 0o600],
                                              ofItemAtPath: file.path)
        return file
    }

    /// `destination = upload` makes this second `xcodebuild` process perform
    /// the App Store Connect upload.
    ///
    /// - Parameter access: the paywall boundary. It is asked immediately
    ///   before the process starts, because a build and its confirmation can
    ///   take long enough for a grant to end in between.
    public func exportAndUpload(archive: URL, exportPath: URL, optionsPlist: URL,
                                authentication: AppleAuthenticationFiles?,
                                allowProvisioningUpdates: Bool,
                                access: any AccessGate,
                                onLine: @escaping @Sendable (ToolStream, String) -> Void)
        async throws {
        try await access.authorize(.storeUpload)
        var arguments = ["xcodebuild", "-exportArchive",
                         "-archivePath", archive.path,
                         "-exportPath", exportPath.path,
                         "-exportOptionsPlist", optionsPlist.path]
        arguments += authentication?.arguments ?? []
        if allowProvisioningUpdates { arguments.append("-allowProvisioningUpdates") }

        let outcome = try await runner.run(
            ToolInvocation(executable: Self.xcrun, arguments: arguments,
                           phase: "Export and upload"),
            onLine: onLine)
        guard outcome.succeeded else {
            let text = (outcome.standardError + outcome.standardOutput).lowercased()
            throw BuildFailure(
                category: text.contains("validation") ? .remoteValidation : .upload,
                stage: "Export and upload",
                message: "The export failed with exit status \(outcome.status).",
                diagnostics: outcome.failureDetail,
                recovery: "The archive is kept. Read the validation issue in the diagnostics, fix it, then export again.",
                retainedArtifact: archive.path)
        }
    }

    // MARK: - Small helpers

    private func run(_ executable: URL, _ arguments: [String],
                     workingDirectory: URL? = nil, phase: String) async throws -> ToolOutcome {
        try await runner.run(
            ToolInvocation(executable: executable, arguments: arguments,
                           workingDirectory: workingDirectory, timeout: 180,
                           phase: phase),
            onLine: { _, _ in })
    }

    static func size(of url: URL) -> Int64 {
        let keys: [URLResourceKey] = [.totalFileAllocatedSizeKey, .fileAllocatedSizeKey]
        guard let walker = FileManager.default.enumerator(at: url,
                                                          includingPropertiesForKeys: keys)
        else { return 0 }
        var total: Int64 = 0
        for case let file as URL in walker {
            let values = try? file.resourceValues(forKeys: Set(keys))
            total += Int64(values?.totalFileAllocatedSize ?? values?.fileAllocatedSize ?? 0)
        }
        return total
    }
}

/// The short-lived files that `xcodebuild` needs for App Store Connect
/// authentication. upload-spec 8.7.
///
/// The key lives in the Keychain. It reaches the disk for the length of one
/// command, in a `0700` directory, as a `0600` file, and the cleanup runs on
/// success, on error, and on a cancel.
public struct AppleAuthenticationFiles: Sendable {
    public let keyPath: URL
    public let keyID: String
    public let issuerID: String

    public var arguments: [String] {
        ["-authenticationKeyPath", keyPath.path,
         "-authenticationKeyID", keyID,
         "-authenticationKeyIssuerID", issuerID]
    }

    /// The mode shown on the confirmation screen.
    public var label: String { "App Store Connect API key \(keyID)" }

    public init(keyPath: URL, keyID: String, issuerID: String) {
        self.keyPath = keyPath
        self.keyID = keyID
        self.issuerID = issuerID
    }

    public static func materialize(credential: AppleCredential, runID: UUID,
                                   storage: BuildStorage) throws -> AppleAuthenticationFiles {
        let file = try storage.writeSecret(credential.privateKeyPEM,
                                           named: "AuthKey_\(credential.keyID).p8",
                                           runID: runID)
        return AppleAuthenticationFiles(keyPath: file, keyID: credential.keyID,
                                        issuerID: credential.issuerID)
    }
}
