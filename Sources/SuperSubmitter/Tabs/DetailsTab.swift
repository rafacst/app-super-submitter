import SubmitKit
import SwiftUI

/// Tab 3. All controls edit the active locale in `store.yaml` immediately.
///
/// **Why one column per store.** The listing is written for two stores that
/// take different words, and a single column asked the developer to hold both
/// in their head. Every shared field carried the smaller of the two limits with
/// no way to see whose it was, and the Google override arrived as an indented
/// afterthought under the Apple field it replaces. Standing the stores side by
/// side puts each store's own limit over its own box and turns an override into
/// what it is: this store takes different text from that one.
///
/// A shared field is still one value. It is drawn in both columns, because each
/// store's limit and each store's "changed since we read it" mark belong over
/// that store's column, and typing in either box writes the same manifest key.
struct DetailsTab: View {
    @Environment(AppState.self) private var state

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            // Publishing sends this tab through the Summary tab, which
            // plans and then writes. Managing has none, so it writes here.
            if state.mode == .managing { DirectApplyBar(target: .listing) }
            statusBar
            if columns { columnHeaders }
            listingRows
            // The parts of the listing that no API will write, under the
            // fields they belong to rather than at the end of a long column.
            consoleSteps
            // Apple's own keyword resource, beside the Keywords field it
            // is so easily mistaken for.
            if shows(.apple) {
                SearchKeywordsPanel().padding(.top, 6)
                // The other half of how the store classifies the app, and
                // the only part of this tab that Apple writes rather than
                // the developer.
                AppTagsPanel().padding(.top, 6)
            }
        }
        .padding(.horizontal, 4)
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    // MARK: - The rows

    @ViewBuilder
    private var listingRows: some View {
        VStack(alignment: .leading, spacing: 15) {
            pair(apple: { shared(.name, in: .apple, anchor: "details.name") },
                 google: { shared(.name, in: .google) })
            pair(apple: { shared(.subtitle, in: .apple, anchor: "details.subtitle") },
                 google: {
                     override(.googleShortDescription, sharing: .subtitle,
                              limit: 80, of: "the subtitle",
                              anchor: "details.googleShortDescription")
                 })
            pair(apple: { shared(.description, in: .apple, multiline: true,
                                 anchor: "details.description") },
                 google: { shared(.description, in: .google, multiline: true) })
            pair(apple: { shared(.whatsNew, in: .apple, multiline: true,
                                 anchor: "details.whatsNew") },
                 google: {
                     override(.googleWhatsNew, sharing: .whatsNew, limit: 500,
                              of: "what is new", multiline: true)
                 })
            pair(apple: {
                     appleOnly {
                         editor("Keywords", field: .keywords,
                                limit: BindingLimits.limit(for: .keywords, in: .apple),
                                anchor: "details.keywords")
                     }
                 },
                 google: {
                     absent("Google Play has no keywords field. Play reads the description instead.")
                 })
            pair(apple: {
                     appleOnly {
                         editor("Promotional text", field: .promotionalText,
                                limit: BindingLimits.limit(for: .promotionalText, in: .apple),
                                anchor: "details.promotionalText")
                     }
                 },
                 google: { absent("Play has no promotional text.") })
            pair(apple: { shared(.supportURL, in: .apple, anchor: "details.supportURL") },
                 google: { shared(.supportURL, in: .google) })
            pair(apple: {
                     appleOnly {
                         editor("Marketing URL", field: .marketingURL,
                                anchor: "details.marketingURL")
                     }
                 },
                 google: { absent("Play carries no separate marketing URL.") })
            pair(apple: { shared(.privacyPolicyURL, in: .apple,
                                 anchor: "details.privacyPolicyURL") },
                 google: { shared(.privacyPolicyURL, in: .google) })
            pair(apple: {
                     appleOnly {
                         VStack(alignment: .leading, spacing: 15) {
                             editor("Privacy policy text", field: .privacyPolicyText,
                                    multiline: true, anchor: "details.privacyPolicyText")
                             editor("Privacy choices URL", field: .privacyChoicesURL,
                                    anchor: "details.privacyChoicesURL")
                         }
                     }
                 },
                 google: { absent("Play keeps both of these in the console.") })
        }
    }

    /// Two cells on one row, one store each.
    ///
    /// They stack when the developer merges the columns, when only one store is
    /// picked, and before any store is picked at all — the Apple cell carries
    /// the shared value, so a tab with no store yet draws the same fields it
    /// always drew.
    @ViewBuilder
    private func pair<A: View, G: View>(@ViewBuilder apple: () -> A,
                                        @ViewBuilder google: () -> G) -> some View {
        if columns {
            HStack(alignment: .top, spacing: 14) {
                apple().frame(maxWidth: .infinity, alignment: .leading)
                google().frame(maxWidth: .infinity, alignment: .leading)
            }
        } else {
            VStack(alignment: .leading, spacing: 15) {
                if shows(.apple) { apple() }
                if shows(.google) { google() }
            }
        }
    }

    /// One value of the manifest, under one store's limit.
    private func shared(_ field: ListingTextField, in store: Store,
                        multiline: Bool = false, anchor: String? = nil) -> some View {
        editor(field.label, field: field,
               limit: Self.bindingField(field).flatMap {
                   BindingLimits.limit(for: $0, in: store)
               },
               multiline: multiline, anchor: anchor)
    }

    /// The Google column of a field Google may take different text for.
    ///
    /// Off, it mirrors the shared box beside it and offers the switch. On, it
    /// is a box of its own and offers the way back. The toggle used to sit
    /// under the Apple field as an indented child; the column says which store
    /// it belongs to without a word.
    @ViewBuilder
    private func override(_ google: ListingTextField, sharing shared: ListingTextField,
                          limit: Int, of name: String, multiline: Bool = false,
                          anchor: String? = nil) -> some View {
        let binding = state.googleOverrideBinding(google)
        VStack(alignment: .leading, spacing: 5) {
            if binding.wrappedValue {
                editor(google.label, field: google, limit: limit,
                       multiline: multiline, anchor: anchor)
                overrideNote("Play cuts at \(limit)", action: "use the shared text") {
                    binding.wrappedValue = false
                }
            } else {
                editor(shared.label, field: shared,
                       limit: Self.bindingField(shared).flatMap {
                           BindingLimits.limit(for: $0, in: .google)
                       },
                       multiline: multiline, anchor: anchor)
                overrideNote("Play takes \(name) as it stands",
                             action: "use different text") {
                    binding.wrappedValue = true
                }
            }
        }
    }

    private func overrideNote(_ text: String, action: String,
                              press: @escaping () -> Void) -> some View {
        HStack(spacing: 6) {
            Rectangle().fill(Theme.sep2).frame(width: 12, height: Theme.hairline)
            Text("\(text) · ").font(Theme.font(size: 11)).foregroundStyle(Theme.text3)
            Button(action, action: press)
                .buttonStyle(.plain)
                .font(Theme.font(size: 11))
                .foregroundStyle(Theme.accent)
        }
    }

    /// A field only the App Store holds. It stays out of a Google-only app
    /// exactly as it did before the columns, and out of a tab with no store
    /// picked yet, where "only" has nothing to be only against.
    @ViewBuilder
    private func appleOnly<Content: View>(@ViewBuilder content: () -> Content) -> some View {
        if state.stores.contains(.apple) { content() }
    }

    /// A store that holds no equivalent of the field beside it. The row keeps
    /// its shape, and the reason stands where the missing box would be.
    ///
    /// It says nothing without a column beside it to say it about, so a
    /// merged or single-store layout drops it rather than listing what the
    /// other store does not have.
    @ViewBuilder
    private func absent(_ reason: String) -> some View {
        if columns {
            HStack(alignment: .top, spacing: 7) {
                Text(verbatim: "—").font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                Text(reason).font(Theme.font(size: 11.5)).foregroundStyle(Theme.text3)
                    .fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 0)
            }
            .padding(.top, 18)
        }
    }

    // MARK: - The bar over the columns

    /// What the tab is worth reading for before any single field is: what
    /// blocks it, what only a console can answer, and how much of it writes.
    private var statusBar: some View {
        HStack(spacing: 14) {
            if let badge = state.badge(for: .details), badge.errors > 0 {
                Button { state.selectedTab = .plan } label: {
                    HStack(spacing: 6) {
                        Dot(colour: Theme.red)
                        Text(badge.errors == 1 ? "1 blocker" : "\(badge.errors) blockers")
                            .font(Theme.font(size: 12, weight: .semibold))
                            .foregroundStyle(Theme.red)
                        Image(systemName: "chevron.right")
                            .font(Theme.font(size: 9, weight: .semibold))
                            .foregroundStyle(Theme.red.opacity(0.6))
                    }
                    .padding(.horizontal, 9).padding(.vertical, 3)
                    .background(Theme.red.opacity(0.14), in: RoundedRectangle(cornerRadius: 7))
                    .contentShape(.rect)
                }
                .buttonStyle(.plain)
            }
            let consoleHere = state.consoleRows.filter(\.onEditingTab).count
            if consoleHere > 0 {
                count(consoleHere == 1 ? "1 console step here"
                      : "\(consoleHere) console steps here", colour: Theme.yellow)
            }
            if let plan = state.plan, plan.writeCount > 0 {
                count(plan.writeCount == 1 ? "1 change will write"
                      : "\(plan.writeCount) changes will write", colour: Theme.accent)
            }
            Spacer(minLength: 8)
            QuietButton(title: "Read again") { Task { await state.readStores() } }
            if state.stores.count > 1 {
                QuietButton(title: state.detailsMerged ? "Split by store" : "Merge the columns") {
                    state.detailsMerged.toggle()
                }
            }
        }
    }

    private func count(_ text: String, colour: Color) -> some View {
        HStack(spacing: 6) {
            Dot(colour: colour)
            Text(text).font(Theme.font(size: 12)).foregroundStyle(Theme.text2)
        }
    }

    private var columnHeaders: some View {
        HStack(alignment: .bottom, spacing: 14) {
            storeColumnHeader(.apple)
            storeColumnHeader(.google)
        }
    }

    private func storeColumnHeader(_ store: Store) -> some View {
        HStack(spacing: 8) {
            StoreMark(store: store, size: 14)
            Text(store.storeName).font(Theme.font(size: 13, weight: .semibold))
            Spacer(minLength: 8)
            Text(state.locale).font(Theme.mono(11)).foregroundStyle(Theme.text3)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 7)
        .overlay(alignment: .bottom) { Hairline() }
    }

    /// The console rows this tab owns, in the column of the store that asks
    /// for them. Anything neither store owns keeps a row of its own, so a
    /// provider step can never fall off the tab.
    @ViewBuilder
    private var consoleSteps: some View {
        let rows = state.consoleRows.filter(\.onEditingTab)
        let others = rows.filter {
            $0.system != Store.apple.storeName && $0.system != Store.google.storeName
        }
        VStack(alignment: .leading, spacing: 14) {
            // Nothing read yet means no rows at all, and the panel that says
            // so has to survive the split or the tab goes silent about a list
            // it is about to grow.
            if rows.isEmpty {
                ConsoleStepsPanel(system: nil)
            } else {
                pair(apple: { ConsoleStepsPanel(system: Store.apple.storeName) },
                     google: { ConsoleStepsPanel(system: Store.google.storeName) })
                if !others.isEmpty { ConsoleStepsPanel(system: nil) }
            }
        }
        .padding(.top, 6)
        .fieldAnchor("details.console")
    }

    // MARK: - Helpers

    /// Two columns need two stores and the width for them.
    private var columns: Bool { state.stores.count > 1 && !state.detailsMerged }

    /// Before any store is picked the Apple column carries the shared fields,
    /// so the tab draws what it always drew rather than nothing at all.
    private func shows(_ store: Store) -> Bool {
        state.stores.isEmpty ? store == .apple : state.stores.contains(store)
    }

    /// The limit table keys off its own enum, and only the fields that have a
    /// limit appear in it. A URL has none, so it returns nil and the box shows
    /// no counter, exactly as it did before the columns.
    private static func bindingField(_ field: ListingTextField) -> ListingField? {
        switch field {
        case .name: .name
        case .subtitle: .subtitle
        case .description: .description
        case .whatsNew: .whatsNew
        case .keywords: .keywords
        case .promotionalText: .promotionalText
        case .googleShortDescription: .shortDescription
        default: nil
        }
    }

    private func editor(_ title: String, field: ListingTextField, limit: Int? = nil,
                        multiline: Bool = false, tag: String? = nil,
                        anchor: String? = nil) -> some View {
        ListingEditor(title: title, field: field, limit: limit,
                      multiline: multiline, tag: tag, anchor: anchor)
    }
}

/// The dot that colours a count on the bar over the columns.
private struct Dot: View {
    let colour: Color
    var body: some View { Circle().fill(colour).frame(width: 7, height: 7) }
}

/// One field of the listing, and the characters it holds while you type.
///
/// **Why it holds them.** `AppState` is `@Observable` and `manifest` is one
/// stored property, so a write to any field of the listing invalidates every
/// view that has read any part of the manifest: the twelve editors on this tab,
/// the inspector preview, the header, and the sidebar, whose badges count the
/// listing's overflowing fields. Measured on the live window, one character
/// typed into Description cost 25 ms of the main thread and one typed into Name
/// cost 50, against 0.05 ms for a redraw with nothing to do. The model work in
/// that is 0.17 ms. All the rest is the window drawing itself again, per key.
///
/// So the manifest stops hearing about every key. The field keeps a draft, the
/// draft is what the box shows and what the counter counts, and the manifest
/// takes it when the typing stops. A key now redraws one field.
///
/// **The three ways this could lose or misplace an edit, and what stops each.**
///
/// - The value changes from somewhere else: an undo, an import, a language
///   switch, the "Use this" button. `settled` is the last text this field
///   handed over or took, so a stored value that differs from it is somebody
///   else's write, and the draft adopts it.
/// - The window closes the tab with characters still waiting. `onDisappear`
///   hands them over.
/// - The developer switches app between the last key and the commit.
///   `AppState.flushSave` drains this first, because `load(from:)` flushes
///   before it swaps the document. The owner check is the second line: a draft
///   belongs to the manifest it was typed into and lands in no other.
private struct ListingEditor: View {
    @Environment(AppState.self) private var state
    let title: String
    let field: ListingTextField
    var limit: Int?
    var multiline = false
    var tag: String?
    var anchor: String?

    /// A reference and not a `@State String`, so the closures that commit it
    /// read the characters as they are now and not as they were when the body
    /// that made the closure ran.
    @State private var draft = ListingDraft()

    var body: some View {
        @Bindable var draft = draft
        let stored = state.manifest.listingText(locale: state.locale, field: field)
        let value = draft.text
        let overLimit = limit.map { value.count > $0 } ?? false
        // Grey means "this is what the store already says". The developer
        // types over it and it goes black, because the text no longer matches
        // what the store holds and the run will write it.
        let live = state.storeSnapshot.text(field, locale: state.locale)
        let unchanged = !live.isEmpty && live.allSatisfy { $0.value == value }
        return VStack(alignment: .leading, spacing: 5) {
            HStack {
                Text(title).font(Theme.font(size: 11.5, weight: .medium))
                if let tag { Tag(tag) }
                if unchanged { KeptTag() } else if !live.isEmpty { ChangedTag() }
                Spacer()
                // Quiet until the budget is worth watching.
                //
                // "191 / 4000" is not information — it is a number that will
                // never matter, printed over every field on the tab, in the
                // same size and colour as the label it sits beside. The
                // counter now appears at half the budget, warns at four
                // fifths, and turns red over it, so a counter on screen means
                // the limit is in play.
                if let limit, Double(value.count) / Double(limit) > 0.5 {
                    let nearLimit = Double(value.count) / Double(limit) > 0.8
                    // A character budget is a count of characters, not a
                    // quantity, so it takes no thousands separator: the 4000
                    // character description limit read as "4.000".
                    Text(verbatim: "\(value.count) / \(limit)")
                        .font(Theme.font(size: 11, weight: overLimit ? .semibold : .regular))
                        .foregroundStyle(overLimit ? Theme.red
                                         : nearLimit ? Theme.yellow : Theme.text2)
                        // The count changes on every key, so the digits have
                        // to hold their column or the label jitters as you type.
                        .monospacedDigit()
                        .contentTransition(.numericText())
                        .accessibilityLabel("\(value.count) of \(limit) characters")
                }
            }
            if multiline {
                // A vertically growing TextField remeasures this entire
                // scroll view after every character. TextEditor keeps one
                // stable viewport and scrolls long release notes internally.
                TextEditor(text: $draft.text.limited(to: limit))
                    .scrollContentBackground(.hidden)
                    .font(Theme.font(size: 13))
                    .foregroundStyle(unchanged ? Theme.text2 : Theme.text)
                    .padding(3)
                    .frame(height: Theme.scaled(90))
                    .background(Theme.field, in: RoundedRectangle(cornerRadius: 6))
                    .overlay(RoundedRectangle(cornerRadius: 6)
                        .strokeBorder(overLimit ? Theme.red : Theme.sep,
                                      lineWidth: overLimit ? 1 : Theme.hairline))
            } else {
                TextField(title, text: $draft.text.limited(to: limit))
                    .textFieldStyle(.roundedBorder)
                    .foregroundStyle(unchanged ? Theme.text2 : Theme.text)
            }
            if overLimit {
                Text("\(value.count - (limit ?? 0)) characters over the store limit. The value is not shortened automatically.")
                    .font(Theme.font(size: 11)).foregroundStyle(Theme.red)
            }
            liveValues(field, live: live, current: value)
        }
        .fieldAnchor(anchor)
        .onAppear { adopt(stored) }
        // Somebody else wrote this field: an undo, an import, a language
        // switch, the "Use this" button. `settled` tells that apart from the
        // echo of this field's own commit.
        .onChange(of: stored) { _, new in if new != draft.settled { adopt(new) } }
        .onChange(of: draft.text) { scheduleCommit() }
        .onDisappear { commit() }
    }

    private func adopt(_ text: String) {
        draft.pending?.cancel()
        draft.pending = nil
        draft.text = text
        draft.settled = text
        draft.owner = state.manifestURL
        state.pendingListingEdit = nil
    }

    /// The pause that ends a burst of typing. Trailing, so a developer who
    /// types a paragraph without stopping writes once at the end of it and not
    /// four times a second.
    private func scheduleCommit() {
        guard draft.text != draft.settled else { return }
        draft.pending?.cancel()
        // The shell drains this before any write and before it swaps the
        // document, so the characters below cannot be lost to a Command-S or
        // to a click on another app in the sidebar.
        state.pendingListingEdit = { commit() }
        draft.pending = Task { @MainActor in
            try? await Task.sleep(for: .milliseconds(220))
            guard !Task.isCancelled else { return }
            commit()
        }
    }

    private func commit() {
        draft.pending?.cancel()
        draft.pending = nil
        state.pendingListingEdit = nil
        guard draft.text != draft.settled else { return }
        // A draft belongs to the manifest it was typed into. Without this an
        // app switched inside the pause would take the previous app's words.
        guard draft.owner == state.manifestURL else { return }
        draft.settled = draft.text
        state.listingBinding(field, locale: state.locale).wrappedValue = draft.text
    }
}

/// The characters of one field between two keystrokes. See `ListingEditor`.
///
/// A class, so the commit closures hold the field itself and not a copy of the
/// view that made them. `@ObservationIgnored` on all but the text: the body
/// reads the text and nothing else, and an observed `Task` would redraw the
/// field twice per key for no picture.
@MainActor @Observable private final class ListingDraft {
    var text = ""
    @ObservationIgnored var settled = ""
    @ObservationIgnored var owner: URL?
    @ObservationIgnored var pending: Task<Void, Never>?
}

private extension ListingEditor {

    /// What the stores hold for this field today, when it is not what the
    /// developer is about to send. A matching value says nothing, so it stays
    /// out of the way.
    ///
    /// The App Store answers twice, and both answers matter. The draft is what
    /// a run patches, and an App Store Connect draft is usually empty. The
    /// live version is what a customer reads. Showing only the draft reported
    /// an app with no description while its page was full, so the live text is
    /// listed too, with the one button that takes it.
    @ViewBuilder
    private func liveValues(_ field: ListingTextField,
                            live: [(store: Store, value: String)],
                            current: String) -> some View {
        let differing = live.filter { $0.value != current }
        let onAppStore = state.storeSnapshot.liveOnAppStore(field, locale: state.locale)
            .flatMap { $0 == current ? nil : $0 }
        if !differing.isEmpty || onAppStore != nil {
            VStack(alignment: .leading, spacing: 8) {
                ForEach(differing, id: \.store) { entry in
                    entryRow(label: "In the \(entry.store.storeName) draft",
                             store: entry.store, value: entry.value, field: field)
                }
                if let onAppStore {
                    entryRow(label: "On the App Store now", store: .apple,
                             value: onAppStore, field: field)
                }
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Theme.sunken, in: RoundedRectangle(cornerRadius: 7))
            .overlay(RoundedRectangle(cornerRadius: 7)
                .strokeBorder(Theme.sep2, lineWidth: Theme.hairline))
        }
    }

    private func entryRow(label: String, store: Store, value: String,
                          field: ListingTextField) -> some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 5) {
                StoreMark(store: store, size: 11)
                Text(label)
                    .font(Theme.font(size: 10.5, weight: .medium))
                    .foregroundStyle(Theme.text3)
                    .textCase(.uppercase)
                    .kerning(0.3)
                Spacer(minLength: 8)
                QuietButton(title: "Use this") {
                    state.listingBinding(field).wrappedValue = value
                }
                .accessibilityLabel("Use the text \(label.lowercased())")
            }
            Text(value)
                .font(Theme.font(size: 11.5))
                .foregroundStyle(Theme.text2)
                .lineSpacing(2)
                .lineLimit(6)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

}

/// The listing as each store will show it.
///
/// A view of its own, and not a property on `DetailsTab`. A property has to be
/// reached through an instance, and an instance built by hand outside the view
/// tree carries no environment, so reading `state` from it traps at the first
/// draw. The inspector needs this beside the editor, so it has to be a node
/// the tree can install.
private struct StoreReceivesPreview: View {
    @Environment(AppState.self) private var state

    var body: some View {
        let name = state.manifest.listingText(locale: state.locale, field: .name)
        let subtitle = state.manifest.listingText(locale: state.locale, field: .subtitle)
        let description = state.manifest.listingText(locale: state.locale, field: .description)
        let googleSubtitle = state.manifest.hasGoogleOverride(locale: state.locale,
                                                             field: .googleShortDescription)
            ? state.manifest.listingText(locale: state.locale, field: .googleShortDescription)
            : subtitle
        return VStack(alignment: .leading, spacing: 14) {
            Text("What each store receives")
                .font(Theme.sectionHeader)
                .foregroundStyle(Theme.text3)
            if state.stores.contains(.apple) {
                StoreTextPreview(store: .apple, locale: state.locale, name: name,
                                 subtitle: subtitle, description: description)
            }
            if state.stores.contains(.google) {
                StoreTextPreview(store: .google, locale: state.locale, name: name,
                                 subtitle: googleSubtitle, description: description)
            }
        }
    }
}

/// What the listing looks like, and the values the store decides.
///
/// It was a fixed 340 point column welded to the right of the tab. Nothing in
/// it is prose the developer writes, so it was reference material taking a
/// third of the width away from the writing, and there was no way to put it
/// away. The shell now shows it as an inspector, which is the container macOS
/// has for exactly this: reference beside a document, hidden on a toggle.
struct DetailsInspector: View {
    @Environment(AppState.self) private var state

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                StoreReceivesPreview()
                // The ids and the declarations are fields, not reference, but
                // they answer "which app is this" and not "what does the
                // listing say". A box for `GAMES` has no business being 900
                // points wide between two paragraphs of listing text.
                if !state.stores.isEmpty { AppIdentifiers() }
                ListingDeclarations()
                Spacer(minLength: 0)
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .background(Theme.sunken)
    }
}

struct Tag: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text).font(Theme.font(size: 10.5)).foregroundStyle(Theme.text3)
            .padding(.horizontal, 4)
            .overlay(RoundedRectangle(cornerRadius: 4)
                .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}

/// The mark on a field that still says what the store says.
///
/// The grey text carries the message and this names it, because grey alone is
/// a colour and a colour alone is not a label. Both stores hold this text, so
/// the update sends nothing for this field.
struct KeptTag: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "checkmark").font(Theme.font(size: 8, weight: .bold))
            Text("Kept").font(Theme.font(size: 10, weight: .medium))
        }
        .foregroundStyle(Theme.text3)
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(Theme.sunken, in: Capsule())
        .accessibilityLabel("Unchanged. The store already holds this text.")
    }
}

/// The mark on a field that no longer says what the store says.
///
/// It appears only once a store has answered for this field. A field nobody
/// has read carries neither chip, because "changed from what" has no answer
/// yet. Orange and not red: red says irreversible, and an edit is not.
struct ChangedTag: View {
    var body: some View {
        HStack(spacing: 3) {
            Image(systemName: "pencil").font(Theme.font(size: 8, weight: .bold))
            Text("Changed").font(Theme.font(size: 10, weight: .medium))
        }
        .foregroundStyle(Theme.orange)
        .padding(.horizontal, 5).padding(.vertical, 1)
        .background(Theme.orange.opacity(0.13), in: Capsule())
        .accessibilityLabel("Changed. The run will write this text to the store.")
    }
}

private struct StoreTextPreview: View {
    let store: Store
    let locale: String
    let name: String
    let subtitle: String
    let description: String

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 6) {
                StoreMark(store: store, size: 13)
                Text("\(store.storeName) · \(locale)")
                    .font(Theme.font(size: 11, weight: .semibold)).foregroundStyle(Theme.text2)
            }
            Text(name.isEmpty ? "Untitled app" : name).font(Theme.font(size: 15, weight: .semibold))
            Text(subtitle).font(Theme.font(size: 12)).foregroundStyle(Theme.text2)
            Text(description).font(Theme.font(size: 11.5)).lineLimit(5)
        }
        .padding(12).frame(maxWidth: .infinity, alignment: .leading)
        .background(Theme.raised, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8)
            .strokeBorder(Theme.sep, lineWidth: Theme.hairline))
    }
}
