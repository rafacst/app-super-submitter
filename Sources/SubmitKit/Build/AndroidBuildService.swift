import Foundation

/// The Android toolchain that this run will use. upload-spec 9.3.
public struct AndroidToolchain: Sendable, Equatable {
    public var gradleVersion = ""
    public var javaHome = ""
    public var javaVersion = ""
    public var androidSDKPath: String?
    /// Every JDK that discovery found, so the developer can choose one.
    public var availableJDKs: [JDK] = []
    public var failure: BuildFailure?

    public struct JDK: Sendable, Equatable, Identifiable {
        public var home: String
        public var version: String
        public var source: String
        public var id: String { home }
    }

    public var label: String {
        gradleVersion.isEmpty ? "Gradle wrapper" : "Gradle \(gradleVersion)"
    }
}

/// One buildable module and its App Bundle task. upload-spec 9.5.
public struct GradleVariant: Sendable, Equatable, Identifiable {
    public var module: String
    public var task: String
    /// `release`, `productionRelease`, and so on, taken from the task name.
    public var variant: String
    public var id: String { "\(module):\(task)" }

    public var qualifiedTask: String { "\(module):\(task)" }

    public var label: String { "\(module.hasPrefix(":") ? String(module.dropFirst()) : module) · \(variant)" }
}

/// What the module's own files say the build will produce.
///
/// A hint and never the answer. Gradle is a program: a build script can read
/// the version out of a properties file, a git tag, or a version catalog, and
/// only the built `.aab` settles it. See `BundleInfo`, which is the answer.
///
/// It exists because the preflight had nothing at all to show. Four rows read
/// "Not read" on every Android project, over values that sit as literals in
/// `build.gradle` in almost every one of them, and the developer learnt the
/// version the build would carry after the build.
public struct AndroidProjectIdentity: Sendable, Equatable {
    public var applicationID: String?
    public var versionName: String?
    public var versionCode: String?
    /// The label the launcher shows, from `strings.xml`.
    public var appName: String?

    public init(applicationID: String? = nil, versionName: String? = nil,
                versionCode: String? = nil, appName: String? = nil) {
        self.applicationID = applicationID
        self.versionName = versionName
        self.versionCode = versionCode
        self.appName = appName
    }
}

/// What a built `.aab` actually holds. upload-spec 9.12.
public struct BundleInfo: Sendable, Equatable {
    public var applicationID = ""
    public var versionName = ""
    public var versionCode = 0
    public var size: Int64 = 0
    public var sha256 = ""
    public var certificateSubject: String?
    public var certificateFingerprint: String?
    public var signatureVerified = false
    public var signatureDetail: String?
}

/// Runs the project's own Gradle wrapper. upload-spec section 9.
///
/// Super Submitter never runs a system Gradle, never edits a Gradle file,
/// never asks for a keystore password, and never answers a prompt.
public struct AndroidBuildService: Sendable {
    static let javaHomeTool = URL(fileURLWithPath: "/usr/libexec/java_home")

    private let runner: any ToolRunning
    private let storage: BuildStorage

    public init(runner: any ToolRunning = ToolProcess(),
                storage: BuildStorage = BuildStorage()) {
        self.runner = runner
        self.storage = storage
    }

    // MARK: - 9.3 Toolchain preflight

    public func toolchain(root: URL, preferredJavaHome: String?) async throws
        -> AndroidToolchain {
        var result = AndroidToolchain()
        let wrapper = root.appendingPathComponent("gradlew")

        guard FileManager.default.fileExists(atPath: wrapper.path) else {
            result.failure = BuildFailure(
                category: .projectDiscovery, stage: "Resolve the toolchain",
                message: "This folder holds no gradlew.",
                recovery: "Choose the folder that holds gradlew and settings.gradle.")
            return result
        }
        guard FileManager.default.isExecutableFile(atPath: wrapper.path) else {
            result.failure = BuildFailure(
                category: .configuration, stage: "Resolve the toolchain",
                message: "gradlew is not executable.",
                recovery: "Run chmod +x gradlew in the project. Super Submitter never changes a file in your repository.")
            return result
        }

        // The wrapper pins the version. Read it from the properties file
        // instead of a Gradle run, because that costs seconds.
        let properties = root.appendingPathComponent("gradle/wrapper/gradle-wrapper.properties")
        if let text = try? String(contentsOf: properties, encoding: .utf8) {
            result.gradleVersion = Self.gradleVersion(fromDistributionURL: text) ?? ""
        }

        result.availableJDKs = await discoverJDKs()
        if let preferredJavaHome, result.availableJDKs.contains(where: { $0.home == preferredJavaHome }) {
            result.javaHome = preferredJavaHome
        } else {
            result.javaHome = result.availableJDKs.first?.home ?? ""
        }
        result.javaVersion = result.availableJDKs
            .first { $0.home == result.javaHome }?.version ?? ""

        if result.javaHome.isEmpty {
            result.failure = BuildFailure(
                category: .toolchainUnavailable, stage: "Resolve the toolchain",
                message: "No JDK was found.",
                recovery: "Install a JDK, or select Android Studio's bundled JBR. Super Submitter never installs one.")
            return result
        }

        result.androidSDKPath = Self.androidSDKPath(root: root)
        if result.androidSDKPath == nil {
            result.failure = BuildFailure(
                category: .toolchainUnavailable, stage: "Resolve the toolchain",
                message: "No Android SDK was found.",
                recovery: "Set sdk.dir in local.properties, or set ANDROID_HOME. Super Submitter never installs an SDK.")
        }
        return result
    }

    /// Every JDK the machine offers, including Android Studio's bundled JBR.
    func discoverJDKs() async -> [AndroidToolchain.JDK] {
        var result: [AndroidToolchain.JDK] = []
        if let outcome = try? await run(Self.javaHomeTool, ["-V"], phase: "Find the JDKs") {
            // `java_home -V` writes its list to standard error, one per line.
            for line in (outcome.standardError + outcome.standardOutput)
                .split(separator: "\n") {
                let parts = line.components(separatedBy: "/")
                guard parts.count > 1, let range = line.range(of: "/") else { continue }
                let home = String(line[range.lowerBound...]).trimmingCharacters(in: .whitespaces)
                guard FileManager.default.fileExists(atPath: home) else { continue }
                let version = line.split(separator: " ").first.map(String.init) ?? ""
                result.append(.init(home: home, version: version, source: "java_home"))
            }
        }
        // Android Studio ships its own runtime, and many projects need it.
        let bundled = "/Applications/Android Studio.app/Contents/jbr/Contents/Home"
        if FileManager.default.fileExists(atPath: bundled) {
            result.append(.init(home: bundled, version: "JetBrains Runtime",
                                source: "Android Studio"))
        }
        if let environment = ProcessInfo.processInfo.environment["JAVA_HOME"],
           FileManager.default.fileExists(atPath: environment),
           !result.contains(where: { $0.home == environment }) {
            result.insert(.init(home: environment, version: "", source: "JAVA_HOME"), at: 0)
        }
        return result
    }

    static func androidSDKPath(root: URL) -> String? {
        let local = root.appendingPathComponent("local.properties")
        if let text = try? String(contentsOf: local, encoding: .utf8) {
            for line in text.split(separator: "\n") where line.hasPrefix("sdk.dir=") {
                let path = String(line.dropFirst("sdk.dir=".count))
                    .replacingOccurrences(of: "\\:", with: ":")
                    .trimmingCharacters(in: .whitespaces)
                if FileManager.default.fileExists(atPath: path) { return path }
            }
        }
        let environment = ProcessInfo.processInfo.environment
        for name in ["ANDROID_HOME", "ANDROID_SDK_ROOT"] {
            if let path = environment[name], FileManager.default.fileExists(atPath: path) {
                return path
            }
        }
        let standard = NSHomeDirectory() + "/Library/Android/sdk"
        return FileManager.default.fileExists(atPath: standard) ? standard : nil
    }

    static func gradleVersion(fromDistributionURL text: String) -> String? {
        guard let range = text.range(of: "gradle-", options: .backwards),
              let end = text.range(of: "-", range: range.upperBound..<text.endIndex)
                ?? text.range(of: ".zip", range: range.upperBound..<text.endIndex) else {
            return nil
        }
        let version = String(text[range.upperBound..<end.lowerBound])
        return version.first?.isNumber == true ? version : nil
    }

    // MARK: - 9.5 Module and variant discovery

    /// Gradle build scripts are programs, so static parsing is only a hint.
    /// This asks Gradle's own evaluated task model instead.
    public func variants(root: URL, toolchain: AndroidToolchain,
                         onLine: @escaping @Sendable (ToolStream, String) -> Void = { _, _ in })
        async throws -> [GradleVariant] {
        let outcome = try await gradle(root: root, toolchain: toolchain,
                                       arguments: ["tasks", "--all"],
                                       phase: "List the Gradle tasks",
                                       timeout: 600, onLine: onLine)
        guard outcome.succeeded else {
            throw BuildFailure(
                category: .configuration, stage: "List the Gradle tasks",
                message: "Gradle could not evaluate this project.",
                diagnostics: outcome.failureDetail,
                recovery: "Open the project once in Android Studio, or fix the Gradle configuration, then press Recheck.")
        }
        let variants = Self.parseBundleTasks(outcome.standardOutput)
        guard !variants.isEmpty else {
            throw BuildFailure(
                category: .configuration, stage: "List the Gradle tasks",
                message: "This project declares no App Bundle task.",
                recovery: "Add the Android application plugin to the module you distribute, then press Recheck.")
        }
        return variants
    }

    /// `:app:bundleRelease - Assembles bundle 'release'…` and the flavored
    /// forms. Debug variants never distribute, so they are dropped.
    static func parseBundleTasks(_ output: String) -> [GradleVariant] {
        var result: [GradleVariant] = []
        for rawLine in output.split(separator: "\n") {
            let line = rawLine.trimmingCharacters(in: .whitespaces)
            let fields = line.components(separatedBy: " - ")
            guard fields.count >= 2 else { continue }
            let name = fields[0].trimmingCharacters(in: .whitespaces)
            let description = fields.dropFirst().joined(separator: " - ")
                .trimmingCharacters(in: .whitespaces)
            guard description.lowercased().hasPrefix("assembles bundle") else { continue }
            guard name.contains("bundle") else { continue }
            let pieces = name.split(separator: ":").map(String.init)
            let task = pieces.last ?? ""
            guard task.hasPrefix("bundle"), task != "bundle" else { continue }
            let variant = String(task.dropFirst("bundle".count))
            guard !variant.isEmpty, variant.first?.isUppercase == true else { continue }
            // A debug or a test variant never reaches a store.
            let lowered = variant.lowercased()
            guard !lowered.hasSuffix("debug"), !lowered.hasSuffix("androidtest"),
                  !lowered.hasSuffix("unittest") else { continue }
            let module = pieces.count > 1
                ? ":" + pieces.dropLast().joined(separator: ":").trimmingCharacters(
                    in: CharacterSet(charactersIn: ":"))
                : ""
            result.append(GradleVariant(module: module, task: task,
                                        variant: variant.prefix(1).lowercased()
                                            + variant.dropFirst()))
        }
        // A project can list the same task twice across two Gradle sections.
        var seen: Set<String> = []
        return result.filter { seen.insert($0.id).inserted }
    }

    // MARK: - 9.6 What the module says it builds

    /// Reads the module's build script and its strings, without running
    /// anything.
    ///
    /// The alternative is a second Gradle invocation to print the evaluated
    /// `android` extension, and that costs the developer a minute of daemon
    /// time to fill four rows on a card. This reads two files.
    ///
    /// A value the script computes is simply absent. The row then says "Not
    /// read", which is what every row said before this existed.
    public static func identity(root: URL, module: String?) -> AndroidProjectIdentity {
        let folder = moduleFolder(root: root, module: module)
        var result = AndroidProjectIdentity()
        for name in ["build.gradle.kts", "build.gradle"] {
            guard let text = try? String(contentsOf: folder.appendingPathComponent(name),
                                         encoding: .utf8) else { continue }
            // `namespace` is the fallback and not the answer. Under AGP 8 a
            // module that names no `applicationId` ships under its namespace,
            // and a module that names one ships under that.
            result.applicationID = value(of: "applicationId", in: text)
                ?? value(of: "namespace", in: text)
            result.versionName = value(of: "versionName", in: text)
            result.versionCode = value(of: "versionCode", in: text)
            break
        }
        let strings = folder.appendingPathComponent("src/main/res/values/strings.xml")
        if let text = try? String(contentsOf: strings, encoding: .utf8) {
            result.appName = appName(in: text)
        }
        return result
    }

    /// `:app` is the folder `app`, and `:feature:login` is `feature/login`.
    /// No module named is the root itself, which is what a single-module build
    /// with no `settings.gradle` include looks like.
    static func moduleFolder(root: URL, module: String?) -> URL {
        let parts = (module ?? "").split(separator: ":").map(String.init)
        return parts.reduce(root) { $0.appendingPathComponent($1) }
    }

    /// One assignment, in either Gradle language.
    ///
    /// Kotlin writes `versionName = "1.0"` and Groovy writes `versionName
    /// "1.0"`, so the `=` is optional. The key is anchored at both ends:
    /// `versionNameSuffix = "-beta"` starts with `versionName` and is a
    /// different setting.
    ///
    /// A commented line is not an assignment. A version left behind under `//`
    /// is the one most likely to be read here, because that is where the last
    /// one goes when a developer changes it.
    static func value(of key: String, in text: String) -> String? {
        for rawLine in text.split(separator: "\n") {
            var line = rawLine.trimmingCharacters(in: .whitespaces)
            guard !line.hasPrefix("//"), !line.hasPrefix("*"), !line.hasPrefix("/*") else {
                continue
            }
            guard line.hasPrefix(key) else { continue }
            line = String(line.dropFirst(key.count))
            // What follows the key decides whether it was the key. Anything
            // that is a letter, a digit, or a dot belongs to a longer name.
            guard let next = line.first, !next.isLetter, !next.isNumber, next != "." else {
                continue
            }
            line = line.drop(while: { $0 == " " || $0 == "=" || $0 == "\t" })
                .trimmingCharacters(in: .whitespaces)
            if let quote = line.first, quote == "\"" || quote == "'" {
                let rest = line.dropFirst()
                guard let end = rest.firstIndex(of: quote) else { continue }
                let value = String(rest[rest.startIndex..<end])
                if !value.isEmpty { return value }
                continue
            }
            // `versionCode 7`, which carries no quotes.
            let digits = String(line.prefix(while: \.isNumber))
            if !digits.isEmpty { return digits }
        }
        return nil
    }

    /// `<string name="app_name">Receitório</string>`, and nothing cleverer. A
    /// label that points at another resource is not a name to show.
    static func appName(in xml: String) -> String? {
        guard let start = xml.range(of: "name=\"app_name\"") else { return nil }
        guard let open = xml[start.upperBound...].firstIndex(of: ">") else { return nil }
        let rest = xml[xml.index(after: open)...]
        guard let close = rest.firstIndex(of: "<") else { return nil }
        let name = rest[rest.startIndex..<close].trimmingCharacters(in: .whitespacesAndNewlines)
        return name.isEmpty || name.hasPrefix("@") ? nil : name
    }

    // MARK: - 9.10 The bundle build

    /// Runs one bundle task. It records what `.aab` files already existed, so
    /// artifact discovery can name the file **this run** produced.
    public func buildBundle(root: URL, toolchain: AndroidToolchain, variant: GradleVariant,
                            onLine: @escaping @Sendable (ToolStream, String) -> Void)
        async throws -> [URL] {
        let before = Self.bundleSnapshot(root: root)
        let outcome = try await gradle(
            root: root, toolchain: toolchain,
            arguments: [variant.qualifiedTask, "--console=plain"],
            phase: "Build the App Bundle", timeout: nil, onLine: onLine)

        guard outcome.succeeded else {
            let text = (outcome.standardError + outcome.standardOutput).lowercased()
            let category: BuildErrorCategory
            let recovery: String
            if text.contains("keystore") || text.contains("signing")
                || text.contains("password") {
                category = .signing
                recovery = "Configure noninteractive release signing in the project. Super Submitter never asks for or stores a keystore password."
            } else if text.contains("could not resolve") || text.contains("could not find") {
                category = .dependencyResolution
                recovery = "Resolve the dependencies once in the project, then build again."
            } else {
                category = .build
                recovery = "Read the diagnostics and the Gradle log, fix the build, then run it again."
            }
            throw BuildFailure(
                category: category, stage: "Build the App Bundle",
                message: "Gradle failed with exit status \(outcome.status).",
                diagnostics: outcome.failureDetail, recovery: recovery)
        }

        let after = Self.bundleSnapshot(root: root)
        // Only a file that this run created or changed. Never the newest
        // `.aab` on the machine. upload-spec 9.11.
        let produced = after.filter { path, stamp in before[path] != stamp }
        guard !produced.isEmpty else {
            throw BuildFailure(
                category: .artifactDiscovery, stage: "Find the App Bundle",
                message: "Gradle succeeded and no new .aab appeared under the expected outputs.",
                recovery: "This project writes its bundle somewhere else. Use Choose Built AAB to pick the file.")
        }
        return produced.keys.sorted().map { URL(fileURLWithPath: $0) }
    }

    /// Every `.aab` under a `build/outputs/bundle` folder, with its identity.
    static func bundleSnapshot(root: URL) -> [String: String] {
        var result: [String: String] = [:]
        guard let walker = FileManager.default.enumerator(
            at: root, includingPropertiesForKeys: [.contentModificationDateKey, .fileSizeKey],
            options: [.skipsHiddenFiles]) else { return result }
        for case let url as URL in walker {
            if ProjectDiscovery.skipped.contains(url.lastPathComponent),
               url.lastPathComponent != "build" {
                walker.skipDescendants()
                continue
            }
            guard url.pathExtension == "aab",
                  url.path.contains("/build/outputs/bundle/") else { continue }
            let values = try? url.resourceValues(
                forKeys: [.contentModificationDateKey, .fileSizeKey])
            let date = values?.contentModificationDate?.timeIntervalSince1970 ?? 0
            result[url.path] = "\(date)-\(values?.fileSize ?? 0)"
        }
        return result
    }

    // MARK: - 9.12 Authoritative bundle inspection

    public func inspect(bundle: URL, toolchain: AndroidToolchain) async throws -> BundleInfo {
        var info = BundleInfo()
        let package = try PackageReader().read(bundle)
        info.applicationID = package.identifier ?? ""
        info.versionName = package.versionName ?? ""
        info.versionCode = package.buildNumber.flatMap(Int.init) ?? 0
        let data = try Data(contentsOf: bundle, options: .mappedIfSafe)
        info.size = Int64(data.count)
        info.sha256 = Checksums.sha256(data)

        // An App Bundle uses JAR signing. `apksigner` verifies an APK and is
        // not the verifier for this artifact. upload-spec 9.12.
        let jarsigner = URL(fileURLWithPath: toolchain.javaHome + "/bin/jarsigner")
        guard FileManager.default.isExecutableFile(atPath: jarsigner.path) else {
            throw BuildFailure(
                category: .artifactValidation, stage: "Verify the bundle signature",
                message: "The selected JDK holds no jarsigner, so the signature cannot be verified.",
                recovery: "Choose a full JDK in the preflight, not a runtime-only installation.")
        }
        let outcome = try await run(jarsigner, ["-verify", "-verbose:summary", "-certs",
                                                bundle.path],
                                    phase: "Verify the bundle signature")
        let text = outcome.standardOutput + outcome.standardError
        info.signatureVerified = outcome.succeeded && text.contains("jar verified")
        info.signatureDetail = text.split(separator: "\n").prefix(8)
            .joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        (info.certificateSubject, info.certificateFingerprint) = Self.certificate(from: text)

        guard info.signatureVerified else {
            throw BuildFailure(
                category: .artifactValidation, stage: "Verify the bundle signature",
                message: "This App Bundle is not signed, or its signature does not verify.",
                diagnostics: info.signatureDetail,
                recovery: "Configure the release variant to sign with the app's registered upload key. Google Play App Signing does not remove that requirement.",
                retainedArtifact: bundle.path)
        }
        return info
    }

    /// The public certificate summary only. No private-key material ever.
    static func certificate(from text: String) -> (String?, String?) {
        var subject: String?
        var fingerprint: String?
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if subject == nil, trimmed.hasPrefix("X.509,") {
                subject = String(trimmed.dropFirst("X.509,".count))
                    .trimmingCharacters(in: .whitespaces)
            }
            let normalized = trimmed.lowercased().replacingOccurrences(of: "-", with: "")
            if fingerprint == nil, normalized.hasPrefix("sha256"),
               let range = trimmed.range(of: ":") {
                fingerprint = String(trimmed[range.upperBound...])
                    .trimmingCharacters(in: .whitespaces)
            }
        }
        return (subject, fingerprint)
    }

    // MARK: - The one Gradle entry point

    /// Launches the absolute `gradlew` with an argument array and the Gradle
    /// root as the working directory. It never builds a shell command.
    private func gradle(root: URL, toolchain: AndroidToolchain, arguments: [String],
                        phase: String, timeout: TimeInterval?,
                        onLine: @escaping @Sendable (ToolStream, String) -> Void) async throws
        -> ToolOutcome {
        var environment: [String: String] = [:]
        if !toolchain.javaHome.isEmpty { environment["JAVA_HOME"] = toolchain.javaHome }
        if let sdk = toolchain.androidSDKPath { environment["ANDROID_HOME"] = sdk }
        var full = arguments
        if !full.contains("--console=plain") { full.append("--console=plain") }
        return try await runner.run(
            ToolInvocation(executable: root.appendingPathComponent("gradlew"),
                           arguments: full, workingDirectory: root,
                           environment: environment, timeout: timeout, phase: phase),
            onLine: onLine)
    }

    private func run(_ executable: URL, _ arguments: [String],
                     phase: String) async throws -> ToolOutcome {
        try await runner.run(
            ToolInvocation(executable: executable, arguments: arguments, timeout: 120,
                           phase: phase),
            onLine: { _, _ in })
    }
}
