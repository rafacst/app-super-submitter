import SubmitKit
import SwiftUI

/// The store credential card, and every part it is built from.
///
/// The Stores tab and the update sheet both ask for one App Store Connect key
/// and one Play service account, so they ask for them the same way: one card
/// per store, folded away once the key is in, a file well that takes a drop,
/// and the same guide behind the same link. It used to be two designs, and the
/// sheet had the poorer one: a bare button where the tab had a drop target, and
/// four controls with no fold, on a step whose own heading promises the keys are
/// entered once.
///
/// The card holds no state. The fold, the guide and the connection come from
/// the caller, because the two callers answer them differently: the tab folds on
/// the connection it can test, and the sheet folds on the key it already holds.
struct CredentialCard<Content: View>: View {
    let store: Store
    /// The word on the right of the header. Nil where nothing has tried the key
    /// yet. The sheet connects from its own footer, and a card that reported
    /// "Not connected" there would name a step the sheet does not have.
    var status: ConnectionStatus?
    /// What the card says about itself while it is folded away: the key id, or
    /// the service account address. It is the answer to "connected as what",
    /// which is the only question a folded card still has to answer.
    let summary: String
    /// The whole card below the header. What decides it is the caller's, and
    /// both callers hide the same thing: a key that is in and covers every app
    /// on the account is four controls nobody touches again, sitting above the
    /// store picker they push down.
    let open: Bool
    let toggle: () -> Void
    let guide: GuideContent
    let guideOpen: Bool
    let toggleGuide: () -> Void
    /// The button that saves the key and calls the store, with the note that
    /// says where the key is kept. Nil leaves both out, for a card whose caller
    /// connects from somewhere else.
    var connect: (() -> Void)?
    var keychainNote: String = ""
    @ViewBuilder let content: Content

    /// True for the third of a second the fields spend shaking. See `body`.
    @State private var shaking = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            header

            if open {
                VStack(alignment: .leading, spacing: 12) {
                    // The fields, and only the fields, take the shake. The
                    // header above and the message below have to hold still:
                    // the whole card moving would say "this card" where the
                    // point is to say "these values".
                    content
                        .offset(x: shaking ? -7 : 0)

                    Button(action: toggleGuide) {
                        HStack(spacing: 6) {
                            Text(guideOpen ? "▼" : "▶").font(Theme.font(size: 8))
                            Text("Where do I get this?").font(Theme.font(size: 12))
                        }
                        .foregroundStyle(Theme.accent)
                        .contentShape(.rect)
                    }
                    .buttonStyle(.plain)
                    .accessibilityValue(guideOpen ? "Expanded" : "Collapsed")

                    if guideOpen { GuideBox(guide: guide) }

                    if let connect { connectFooter(connect) }
                }
                .padding(.horizontal, 16)
                .padding(.bottom, 14)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        .motion(.snappy(duration: 0.18), value: open)
        // The shake itself. Reduce Motion is honoured by hand here rather than
        // through `.motion`, because the answer is not a shorter animation but
        // no movement at all: `shaking` is never set, so the offset never
        // leaves zero and the field stays where it is. The colour, the words
        // and the focus below do the whole job on their own.
        .animation(reduceMotion ? nil
                   : .linear(duration: 0.06).repeatCount(5, autoreverses: true),
                   value: shaking)
        // A refused key is the most common failure in the product, and it
        // reported itself by dropping a line of text under a button, below the
        // fold, while the two fields that caused it sat above unchanged.
        //
        // Motion alone is never the message. The report is explicit: pair it
        // with specific text and a path to recovery. The text is the store's
        // own refusal in `connectFooter`, and the card is already open because
        // a connection can only be attempted from inside it.
        .onChange(of: status) { _, new in
            guard new?.isFailed == true, !reduceMotion else { return }
            shaking = true
            Task { @MainActor in
                // 5 repeats at 0.06 seconds, and then back to rest. Without
                // this the offset stays at -7 and the fields sit seven points
                // to the left for as long as the card is open.
                try? await Task.sleep(for: .milliseconds(320))
                shaking = false
            }
        }
    }

    /// The row that stays whatever the card is doing, and the control that
    /// folds it.
    ///
    /// The whole row is the hit target rather than a lone chevron: this is a
    /// disclosure, and macOS gives a disclosure its title bar. The status keeps
    /// its four words, because they are the reason to open the card at all.
    private var header: some View {
        Button(action: toggle) {
            HStack(spacing: 8) {
                Image(systemName: "chevron.right")
                    .font(Theme.font(size: 9, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .rotationEffect(.degrees(open ? 90 : 0))
                StoreMark(store: store, size: 18)
                Text("\(store.storeName) credential")
                    .font(Theme.font(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.text)
                // What the fold hides. A folded card that says only
                // "Connected" cannot answer "as which account", which is the
                // one thing a second developer on the machine has to check.
                if !open, !summary.isEmpty {
                    Text(summary)
                        .font(Theme.mono(11))
                        .foregroundStyle(Theme.text2)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 6)
                // Four states, four words, four glyphs. A refused key used to
                // draw the same grey "Not connected" as a key nobody has tried
                // yet, so the one state that needs the developer to act looked
                // like the state they had not reached.
                if let status {
                    HStack(spacing: 5) {
                        Image(systemName: Self.symbol(status))
                            .font(Theme.font(size: 11))
                            // The dashed circle becomes a clock becomes a tick,
                            // in place. This is the result of a call the
                            // developer just made and waited seconds for, and
                            // the answer used to arrive as a swapped glyph.
                            .contentTransition(.symbolEffect(.replace))
                            // Only on the good end. A refusal is marked by the
                            // fields shaking below, and two motions for one
                            // event is two events.
                            .symbolEffect(.bounce, value: status.isConnected)
                        Text(Self.word(status)).font(Theme.font(size: 11.5)).fixedSize()
                    }
                    .foregroundStyle(Self.colour(status))
                    .motion(.smooth(duration: 0.2), value: status)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 13)
            .contentShape(.rect)
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(store.storeName) credential")
        .accessibilityValue(accessibilityState)
        .accessibilityHint(open ? "Hide the credential" : "Show the credential")
    }

    private var accessibilityState: String {
        let fold = open ? "expanded" : "collapsed"
        guard let status else { return fold }
        return "\(Self.word(status)), \(fold)"
    }

    private func connectFooter(_ connect: @escaping () -> Void) -> some View {
        VStack(alignment: .leading, spacing: 7) {
            // Prominent, and below the fields rather than after the paragraph.
            // Connecting is the reason this card exists, until it succeeds
            // nothing else in the app can reach a store, and it was a quiet
            // button sitting under forty words of Keychain policy, which made
            // the policy look like the point and the action like a footnote.
            // Prominent until it passes. A connected store has nothing left to
            // ask for, so the button steps down.
            //
            // "Test connection" named the smaller half of what it did. The
            // button saves the key to the Keychain and then calls the store
            // with it, so a pass is a connection and not a rehearsal of one. A
            // developer reading "test" reasonably waits for a Connect button
            // that never was.
            let title = switch status {
            case .connecting: "Connecting…"
            case .connected: "Reconnect"
            default: "Connect to the store"
            }
            QuietButton(title: title,
                        prominent: !(status?.isConnected ?? false), action: connect)
                .disabled(status == .connecting)
            Text(keychainNote).font(Theme.font(size: 11.5))
                .foregroundStyle(Theme.text2)
                .fixedSize(horizontal: false, vertical: true)
            if case .failed(let message) = status {
                WarningNote(message)
            } else if case .connected(let message) = status {
                Text(message).font(Theme.font(size: 11.5))
                    .foregroundStyle(Theme.green)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private static func symbol(_ status: ConnectionStatus) -> String {
        if status.isConnected { return "checkmark.circle.fill" }
        if status.isFailed { return "exclamationmark.triangle.fill" }
        return status == .connecting ? "clock.fill" : "circle.dashed"
    }

    private static func word(_ status: ConnectionStatus) -> String {
        if status.isConnected { return "Connected" }
        if status.isFailed { return "The store refused it" }
        return status == .connecting ? "Connecting" : "Not connected"
    }

    /// Yellow and not red for a refusal. Nothing was written, so nothing has to
    /// be taken back, and red says irreversible everywhere in this app.
    private static func colour(_ status: ConnectionStatus) -> Color {
        if status.isConnected { return Theme.green }
        if status.isFailed || status == .connecting { return Theme.yellow }
        return Theme.text2
    }
}

extension AnyTransition {
    /// Grows out of the store card above it, rather than fading in place.
    static var credentialPanel: AnyTransition {
        .scale(scale: 0.96, anchor: .top).combined(with: .opacity)
    }
}

struct GuideLink: Identifiable {
    let title: String
    let url: URL
    var id: String { title }

    init(_ title: String, _ url: String) {
        self.title = title
        self.url = URL(string: url)!
    }
}

/// How a developer gets the key, said once for every place that asks for it.
struct GuideContent {
    let steps: [String]
    let warning: String
    let buttons: [GuideLink]

    static let apple = GuideContent(
        steps: [
            "Open App Store Connect, then Users and Access, then Integrations, then App Store Connect API.",
            "Create a key with the App Manager role. Copy the key id and the issuer id.",
            "Download the .p8 file.",
        ],
        warning: "Apple shows the .p8 file once. Save it now. A lost key cannot be downloaded again. You create a new one.",
        buttons: [GuideLink("Open Users and Access ↗",
                            "https://appstoreconnect.apple.com/access/integrations/api")])

    static let google = GuideContent(
        steps: [
            "In the Google Cloud console, create a service account and download its JSON key.",
            "Grant it the Android Publisher role.",
            "In the Play Console, open Users and permissions and invite the service account email.",
        ],
        warning: "Step 3 is mandatory and no API performs it. A skipped invitation returns a permission error during the connection test.",
        buttons: [
            GuideLink("Open Cloud console ↗", "https://console.cloud.google.com/iam-admin/serviceaccounts"),
            GuideLink("Open Play Console ↗", "https://play.google.com/console"),
        ])
}

struct GuideBox: View {
    let guide: GuideContent

    var body: some View {
        VStack(alignment: .leading, spacing: 9) {
            ForEach(Array(guide.steps.enumerated()), id: \.offset) { index, step in
                HStack(alignment: .top, spacing: 9) {
                    Text("\(index + 1)").foregroundStyle(Theme.text2)
                    Text(step).fixedSize(horizontal: false, vertical: true)
                }
                .font(Theme.font(size: 12))
                .lineSpacing(3)
            }

            HStack(alignment: .top, spacing: 9) {
                Text("!").font(Theme.font(size: 12, weight: .bold)).foregroundStyle(Theme.yellow)
                Text(guide.warning)
                    .font(Theme.font(size: 12))
                    .lineSpacing(3)
                    .fixedSize(horizontal: false, vertical: true)
            }
            .padding(.horizontal, 11)
            .padding(.vertical, 9)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.yellowBg, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7).strokeBorder(Theme.yellow, lineWidth: 1))

            VStack(alignment: .leading, spacing: 6) {
                ForEach(guide.buttons) { item in
                    Link(destination: item.url) { QuietButtonLabel(title: item.title) }
                }
            }
        }
        .padding(.horizontal, 15)
        .padding(.vertical, 13)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

struct QuietButtonLabel: View {
    let title: String
    var body: some View {
        Text(title)
            .font(Theme.font(size: 12))
            .foregroundStyle(Theme.text)
            .padding(.horizontal, 11)
            .padding(.vertical, 4)
            .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
            .overlay(RoundedRectangle(cornerRadius: 6)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

/// The key file, as a target you can drop on. A button alone made the drop
/// look impossible, and dragging the file out of Downloads is what a developer
/// does with it.
struct FileWell: View {
    let name: String
    let emptyName: String
    let prompt: String
    let choose: () -> Void
    let accept: ([URL]) -> Bool
    @State private var targeted = false

    var body: some View {
        HStack(spacing: 10) {
            RoundedRectangle(cornerRadius: 4)
                .fill(Theme.field)
                .overlay(RoundedRectangle(cornerRadius: 4)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
                .frame(width: 30, height: 36)
            VStack(alignment: .leading, spacing: 2) {
                Text(name.isEmpty ? emptyName : name).font(Theme.font(size: 12)).lineLimit(1)
                HStack(spacing: 3) {
                    Text(prompt).foregroundStyle(Theme.text2)
                    Button("choose a file…", action: choose)
                        .buttonStyle(.plain)
                        .foregroundStyle(Theme.accent)
                }
                .font(Theme.font(size: 11))
            }
            Spacer(minLength: 0)
        }
        .padding(12)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(targeted ? Theme.field : Theme.sunken, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(targeted ? Theme.accent : Theme.sep,
                          style: StrokeStyle(lineWidth: targeted ? 1.5 : 1, dash: [3, 3])))
        // The well brightened on entry in one frame. This is the target a
        // developer aims a dragged .p8 at, and the border going from hairline
        // to 1.5 points instantly reads as a redraw rather than a response.
        .motion(.easeOut(duration: 0.12), value: targeted)
        .dropDestination(for: URL.self) { urls, _ in
            let accepted = accept(urls)
            // Only on the accepted drop. A .json dropped on the Apple well is
            // refused, and a tick there would say it landed.
            if accepted { Haptic.drop() }
            return accepted
        } isTargeted: { targeted = $0 }
    }
}

struct EditableField: View {
    let label: String
    @Binding var value: String
    let prompt: String
    /// The length the store issues, where it issues a fixed one. Nil means the
    /// field takes whatever the developer has.
    var limit: Int?

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(label).font(Theme.font(size: 11)).foregroundStyle(Theme.text2)
            // `oneLine` outside `limited`, and the order is the whole point: the
            // break is taken out first, then the length is counted. A key id
            // copied out of App Store Connect arrives with a newline on the end,
            // which is 37 characters against a limit of 36, and the limit alone
            // refused the whole paste. A Return typed into the field did the
            // same damage from the other side: the value grew a line, the field
            // editor scrolled to the empty second one, and the id a developer
            // had just entered was cut in half on the screen.
            //
            // Every field this draws holds a store id. None of them has a
            // second line, so this belongs here and not at the four call sites.
            //
            // `capped` and not `limited`. Refusing growth leaves a value that
            // arrived from the Keychain or from an import over length exactly
            // as long as it was, and an issuer id is 36 characters or it is
            // not an issuer id. The store refuses the 37th, so the field does.
            TextField(prompt, text: $value.capped(to: limit).oneLine)
                .textFieldStyle(.plain)
                .font(Theme.mono(12))
                .padding(.horizontal, 8)
                .padding(.vertical, 6)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                .overlay(RoundedRectangle(cornerRadius: 6)
                    .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
        }
    }
}
