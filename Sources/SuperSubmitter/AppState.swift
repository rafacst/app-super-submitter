import Foundation
import Observation
import SubmitKit
import SwiftUI

/// Where the tabs live. Spec section 16.1.
enum NavigationPosition: String, CaseIterable, Identifiable {
    case sidebar, topBar

    var id: String { rawValue }

    var label: String {
        switch self {
        case .sidebar: "Sidebar"
        case .topBar: "Top bar"
        }
    }
}

enum Severity {
    case error, warning

    var color: Color { self == .error ? Theme.red : Theme.yellow }
    var background: Color { self == .error ? Theme.redBg : Theme.yellowBg }
}

@Observable
@MainActor
final class AppState {
    @ObservationIgnored private var runTask: Task<Void, Never>?

    // The manifest and the file behind it.
    var manifest = Manifest()
    var manifestURL: URL?

    // Navigation.
    var selectedTab: Tab = .stores
    var selectedAppIndex = 0
    var switcherOpen = false

    /// Settings opens as a panel over the window, not as a second window.
    var showSettings = false
    var showOnboarding = false
    var onboardingStep = 0
    var menuBarOpen = false
    var releaseSheet: Store?

    // Tab 1.
    var appleGuideOpen = false
    var googleGuideOpen = false

    // Tab 2.
    var buildRead = false

    // Tab 3.
    var locale = "en-US"
    var keywordsFixed = false

    // Tab 5.
    var provider: Manifest.Provider = .revenuecat

    // Tab 7.
    var dryRun = false
    var acknowledged: Set<String> = []

    // Tab 8.
    var runIndex = -1
    var runDone = false
    var runProgress = 0.0
    var logOpen = false
    var applied = false

    // Tab 9.
    var checked: Set<String> = []
    var rechecked = false
    var appleReleased = false
    var googleReleased = false

    var currentApp: DemoApp { DemoData.apps[min(selectedAppIndex, DemoData.apps.count - 1)] }

    var stores: Set<Store> { [.apple, .google] }

    // MARK: - The badges

    /// The count of open items per tab, and how loud each one is.
    ///
    /// A badge is red when the tab holds an error and yellow when it holds
    /// only warnings. Red means "this blocks the apply", so it must never
    /// appear on a tab that holds no error.
    func badge(for tab: Tab) -> (count: Int, severity: Severity)? {
        if applied { return nil }
        switch tab {
        case .details:
            return keywordsFixed ? nil : (1, .error)
        case .reviewInfo:
            return (2, .warning)
        case .plan:
            return keywordsFixed ? (2, .warning) : (3, .error)
        default:
            return nil
        }
    }

    var planIsBlocked: Bool { !keywordsFixed }
    var hasProvider: Bool { provider != .none }

    // MARK: - The run

    func startRun() {
        guard !planIsBlocked, !applied else { return }
        runTask?.cancel()
        runIndex = 0
        runDone = false
        runProgress = 0

        runTask = Task { [weak self] in
            guard let self else { return }

            for (index, item) in DemoData.runItems.enumerated() {
                guard !Task.isCancelled else { return }
                runIndex = index
                runProgress = 0

                let tickCount = item.isGroup ? 1 : (item.long ? 22 : 3)
                for tick in 1...tickCount {
                    do {
                        try await Task.sleep(for: .milliseconds(110))
                    } catch {
                        return
                    }
                    guard !Task.isCancelled else { return }
                    runProgress = Double(tick) / Double(tickCount)
                }
            }

            finishRun()

            do {
                try await Task.sleep(for: .milliseconds(1_600))
            } catch {
                return
            }
            guard runDone else { return }
            selectedTab = .release
        }
    }

    func finishRun() {
        runIndex = DemoData.runItems.count
        runDone = true
        runProgress = 1
        applied = true
    }

    func resetDemo() {
        runTask?.cancel()
        runTask = nil
        selectedTab = .stores
        buildRead = false
        keywordsFixed = false
        applied = false
        runIndex = -1
        runDone = false
        runProgress = 0
        checked = []
        rechecked = false
        appleReleased = false
        googleReleased = false
        acknowledged = []
    }

    // MARK: - The manifest file

    func load(from url: URL) throws {
        manifest = try ManifestFile.load(from: url)
        manifestURL = url
    }

    func save() throws {
        guard let manifestURL else { return }
        try ManifestFile.save(manifest, to: manifestURL)
    }
}
