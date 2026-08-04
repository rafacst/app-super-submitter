import SwiftUI

/// The ten tabs, in the order of the work. Spec section 16.3.
enum Tab: Int, CaseIterable, Identifiable, Hashable {
    case stores = 1
    case build
    case details
    case media
    case money
    case marketing
    case reviewInfo
    case plan
    case submit
    case release

    var id: Int { rawValue }

    var title: String {
        switch self {
        case .stores: "Stores"
        case .build: "Build"
        case .details: "Details"
        case .media: "Media"
        case .money: "Monetization"
        case .marketing: "Marketing"
        case .reviewInfo: "Review info"
        case .plan: "Summary"
        case .submit: "Submit"
        case .release: "Release"
        }
    }

    /// The outline reads as "not here", the filled one as "here". Release is
    /// the exception: the dotted path says the flight already left.
    func symbol(selected: Bool) -> String {
        switch self {
        case .stores: selected ? "storefront.fill" : "storefront"
        case .build: selected ? "shippingbox.fill" : "shippingbox"
        case .details: selected ? "list.bullet.rectangle.fill" : "list.bullet.rectangle"
        case .media: selected ? "photo.stack.fill" : "photo.stack"
        case .money: selected ? "dollarsign.square.fill" : "dollarsign.square"
        case .marketing: selected ? "megaphone.fill" : "megaphone"
        case .reviewInfo: selected ? "checkmark.square.fill" : "checkmark.square"
        case .plan: selected ? "text.bubble.fill" : "text.bubble"
        case .submit: selected ? "square.and.arrow.up.fill" : "square.and.arrow.up"
        case .release: selected ? "airplane.path.dotted" : "airplane"
        }
    }

    /// The question the tab answers. Spec section 16.3.
    var question: String {
        switch self {
        case .stores: "Where does this app go, and who am I?"
        case .build: "What do I submit?"
        case .details: "What does the listing say?"
        case .media: "What does the listing show?"
        case .money: "What does it cost, and what can I buy?"
        case .marketing: "How does the App Store sell it?"
        case .reviewInfo: "What does the reviewer need?"
        case .plan: "What changes, exactly?"
        case .submit: "Do it."
        case .release: "Is it ready, and shall I send it?"
        }
    }

    /// The four zones of the app. The sidebar draws a divider between them,
    /// because the zone tells the user what a tab can do to a live store.
    enum Zone: Int, CaseIterable {
        case edits, reads, writes, releases

        var label: String {
            switch self {
            case .edits: "Edit the manifest"
            case .reads: "Check"
            case .writes: "Write the drafts"
            case .releases: "Release"
            }
        }
    }

    var zone: Zone {
        switch self {
        case .stores, .build, .details, .media, .money, .marketing, .reviewInfo: .edits
        case .plan: .reads
        case .submit: .writes
        case .release: .releases
        }
    }

    static func tabs(in zone: Zone) -> [Tab] {
        allCases.filter { $0.zone == zone }
    }

    /// A rule sits before tab 7 and before tab 9.
    ///
    /// The first marks where the app stops editing a file and starts reading
    /// the stores. The second marks the only tab that can send a version to
    /// review. Two hairlines carry the whole mental model.
    var startsZone: Bool { self == .plan || self == .release }
}
