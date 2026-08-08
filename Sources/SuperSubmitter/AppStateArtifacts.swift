import SubmitKit
import SwiftUI

/// The Android artifacts and the track settings of tab 2.
///
/// Every binding here writes one manifest key and saves. No binding parses a
/// build, because the artifact paths name files that something else produced.
extension AppState {

    enum ArtifactField: CaseIterable {
        case apk, mappingFile, nativeSymbols, expansionMain, expansionPatch, deviceTierConfig

        var label: String {
            switch self {
            case .apk: "APK"
            case .mappingFile: "Mapping file"
            case .nativeSymbols: "Native symbols"
            case .expansionMain: "Main expansion file"
            case .expansionPatch: "Patch expansion file"
            case .deviceTierConfig: "Device tier config"
            }
        }

        var hint: String {
            switch self {
            case .apk: "Optional. A bundle and an APK may go into one edit."
            case .mappingFile: "ProGuard or R8. Google needs it to read a stack trace."
            case .nativeSymbols: "The NDK debug symbols archive."
            case .expansionMain: "APK only. A bundle carries its assets inside. An apply re-uploads it only when it differs from the one Google holds."
            case .expansionPatch: "APK only. Re-uploaded only when it differs."
            case .deviceTierConfig: "JSON. An apply reuses the newest matching configuration and creates one only when yours differs."
            }
        }
    }

    func artifactBinding(_ field: ArtifactField) -> Binding<String> {
        Binding(get: {
            let google = self.manifest.release?.google
            return switch field {
            case .apk: self.manifest.release?.build?.androidApk ?? ""
            case .mappingFile: google?.mappingFile ?? ""
            case .nativeSymbols: google?.nativeDebugSymbols ?? ""
            case .expansionMain: google?.expansionFileMain ?? ""
            case .expansionPatch: google?.expansionFilePatch ?? ""
            case .deviceTierConfig: google?.deviceTierConfig ?? ""
            }
        }, set: { value in
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            let stored: String? = trimmed.isEmpty ? nil : trimmed
            self.ensureGoogleRelease()
            switch field {
            case .apk:
                if self.manifest.release?.build == nil {
                    self.manifest.release?.build = Manifest.Release.Build()
                }
                self.manifest.release?.build?.androidApk = stored
            case .mappingFile: self.manifest.release?.google?.mappingFile = stored
            case .nativeSymbols: self.manifest.release?.google?.nativeDebugSymbols = stored
            case .expansionMain: self.manifest.release?.google?.expansionFileMain = stored
            case .expansionPatch: self.manifest.release?.google?.expansionFilePatch = stored
            case .deviceTierConfig: self.manifest.release?.google?.deviceTierConfig = stored
            }
            self.saveManifestReportingErrors()
        })
    }

    /// The track list, as one comma-separated field. A track name holds no
    /// comma, so the round trip is exact.
    var googleTracksBinding: Binding<String> {
        Binding(get: { (self.manifest.release?.google?.tracks ?? []).joined(separator: ", ") },
                set: { value in
                    self.ensureGoogleRelease()
                    let list = Self.splitList(value)
                    self.manifest.release?.google?.tracks = list.isEmpty ? nil : list
                    self.saveManifestReportingErrors()
                })
    }

    var googleCountriesBinding: Binding<String> {
        Binding(get: { (self.manifest.release?.google?.countries ?? []).joined(separator: ", ") },
                set: { value in
                    self.ensureGoogleRelease()
                    let list = Self.splitList(value).map { $0.uppercased() }
                    self.manifest.release?.google?.countries = list.isEmpty ? nil : list
                    self.saveManifestReportingErrors()
                })
    }

    var googleRestOfWorldBinding: Binding<Bool> {
        Binding(get: { self.manifest.release?.google?.includeRestOfWorld ?? false },
                set: { value in
                    self.ensureGoogleRelease()
                    self.manifest.release?.google?.includeRestOfWorld = value
                    self.saveManifestReportingErrors()
                })
    }

    /// The primary track, the one that the release button sends.
    var googlePrimaryTrackBinding: Binding<String> {
        Binding(get: { self.manifest.googlePrimaryTrack },
                set: { value in
                    self.ensureGoogleRelease()
                    let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
                    self.manifest.release?.google?.track = trimmed.isEmpty ? nil : trimmed
                    self.saveManifestReportingErrors()
                })
    }

    /// The Google Groups that may install one closed track.
    ///
    /// Google replaces the whole list on every write and takes group email
    /// addresses only: the single-tester list stays in the Play Console. A
    /// closed track with no group here reaches nobody, and until this field
    /// existed the raw YAML editor was the only way to fill it.
    func googleTestersBinding(track: String) -> Binding<String> {
        Binding(get: {
            (self.manifest.release?.google?.testers?[track] ?? []).joined(separator: ", ")
        }, set: { value in
            self.ensureGoogleRelease()
            var all = self.manifest.release?.google?.testers ?? [:]
            let list = Self.splitList(value)
            // An empty list is not the same as no key. Google clears a track
            // that names an empty list, and leaves one it never hears about.
            if list.isEmpty, value.trimmingCharacters(in: .whitespaces).isEmpty {
                all.removeValue(forKey: track)
            } else {
                all[track] = list
            }
            self.manifest.release?.google?.testers = all.isEmpty ? nil : all
            self.saveManifestReportingErrors()
        })
    }

    // MARK: - The externally hosted APK

    var hasExternalApk: Bool { manifest.release?.google?.externalApk != nil }

    func addExternalApk() {
        ensureGoogleRelease()
        guard manifest.release?.google?.externalApk == nil else { return }
        manifest.release?.google?.externalApk = Manifest.Release.ExternalApk(
            url: "", applicationLabel: "", versionCode: 1, versionName: "",
            minimumSdk: 24, certificateBase64s: [])
        saveManifestReportingErrors()
    }

    func removeExternalApk() {
        manifest.release?.google?.externalApk = nil
        saveManifestReportingErrors()
    }

    enum ExternalApkField: CaseIterable {
        case url, label, versionCode, versionName, minimumSdk, certificates

        var title: String {
            switch self {
            case .url: "HTTPS URL"
            case .label: "Application label"
            case .versionCode: "Version code"
            case .versionName: "Version name"
            case .minimumSdk: "Minimum SDK"
            case .certificates: "Certificates, base64, comma-separated"
            }
        }
    }

    func externalApkBinding(_ field: ExternalApkField) -> Binding<String> {
        Binding(get: {
            guard let apk = self.manifest.release?.google?.externalApk else { return "" }
            return switch field {
            case .url: apk.url
            case .label: apk.applicationLabel
            case .versionCode: String(apk.versionCode)
            case .versionName: apk.versionName
            case .minimumSdk: String(apk.minimumSdk)
            case .certificates: apk.certificateBase64s.joined(separator: ", ")
            }
        }, set: { value in
            guard self.manifest.release?.google?.externalApk != nil else { return }
            switch field {
            case .url: self.manifest.release?.google?.externalApk?.url = value
            case .label: self.manifest.release?.google?.externalApk?.applicationLabel = value
            case .versionCode:
                self.manifest.release?.google?.externalApk?.versionCode = Int(value) ?? 0
            case .versionName: self.manifest.release?.google?.externalApk?.versionName = value
            case .minimumSdk:
                self.manifest.release?.google?.externalApk?.minimumSdk = Int(value) ?? 0
            case .certificates:
                self.manifest.release?.google?.externalApk?.certificateBase64s =
                    Self.splitList(value)
            }
            self.saveManifestReportingErrors()
        })
    }

    // MARK: - Shared

    func ensureGoogleRelease() {
        if manifest.release == nil { manifest.release = Manifest.Release() }
        if manifest.release?.google == nil {
            manifest.release?.google = Manifest.Release.GoogleRelease()
        }
    }

    static func splitList(_ value: String) -> [String] {
        value.split(separator: ",")
            .map { $0.trimmingCharacters(in: .whitespaces) }
            .filter { !$0.isEmpty }
    }
}
