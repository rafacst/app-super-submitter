import Foundation
import SubmitKit
import SwiftUI

/// One step back, for every edit that reaches `store.yaml`.
///
/// The app writes the file as the developer types, so there is no Save button
/// to cancel and no dirty state to discard. Undo is the only way back, and the
/// app performs irreversible work, so it has to have one.
///
/// Every mutation in the app ends at `saveManifestReportingErrors`, so the
/// registration sits there and nowhere else. A tab that edits a field does not
/// know undo exists, and a tab written later inherits it.
///
/// A step holds the whole manifest rather than one field. The file is a few
/// kilobytes, the edits are struct writes across a dozen shapes, and a
/// per-field stack would need one case per field for no gain the developer
/// can see.
extension AppState {

    /// How long a run of edits stays one step.
    ///
    /// Without it, Command-Z walks back through a description one letter at a
    /// time. A pause longer than this starts the next step.
    private static let undoCoalesceWindow: TimeInterval = 0.7

    /// Files the state that came before the edit now being saved.
    ///
    /// `undoBaseline` always holds the manifest as it stood before the current
    /// edit, because every call advances it afterwards. A keystroke inside the
    /// window advances the baseline without registering, so a burst keeps the
    /// one entry that restores the text as it stood before the burst.
    func registerManifestUndo() {
        guard undoBaseline != manifest else { return }
        let now = Date()
        let coalescing = lastUndoRegistration
            .map { now.timeIntervalSince($0) < Self.undoCoalesceWindow } ?? false
        if !coalescing { fileStep(back: undoBaseline) }
        undoBaseline = manifest
        lastUndoRegistration = now
        refreshUndoState()
    }

    /// Puts a manifest back, and files the way forward.
    ///
    /// Registering while an undo runs is what gives Redo: `UndoManager` files
    /// the new entry on the redo stack for as long as it is undoing.
    func restoreManifest(_ restored: Manifest) {
        fileStep(back: manifest)
        manifest = restored
        undoBaseline = restored
        // The next keystroke starts its own step. Without this a key pressed
        // inside the window would coalesce into the undo itself and register
        // nothing, so the edit after an undo could not be undone.
        lastUndoRegistration = nil

        // The tabs read these, not the manifest, so a restore that skipped
        // them would put the file back and leave the fields showing the value
        // that was just undone.
        syncStoreFieldsFromManifest()
        syncEditingStateFromManifest()
        if manifest.listing?.locales[locale] == nil {
            locale = manifest.listing?.defaultLocale ?? locale
        }
        do { try save() }
        catch {
            errorMessage = "The manifest could not be saved. \(error.localizedDescription)"
        }
        invalidatePlan()
        // The raw side shows text it encoded itself, so it re-encodes.
        if showYAML, let block = yamlBlock { loadYAML(block) }
        refreshUndoState()
    }

    /// Forgets the stack, and starts a new baseline.
    ///
    /// A step holds a whole manifest, so carrying the stack across a switch of
    /// app would let one Command-Z write the previous app's listing into this
    /// app's file.
    func resetUndo() {
        undoBaseline = manifest
        lastUndoRegistration = nil
        // Every action on this stack, not only the ones filed against this
        // target: the app owns the manager outright, so there is nothing else
        // on it, and the by-target call leaves an open group behind.
        undoManager.removeAllActions()
        refreshUndoState()
    }

    /// Files one step, as its own group.
    ///
    /// `groupsByEvent` is off, so a registration outside a group would never
    /// close and Command-Z would revert the whole session at once. Undo and
    /// redo open their own group for the way back, so those two do not nest a
    /// second one inside it.
    private func fileStep(back previous: Manifest) {
        let owned = !undoManager.isUndoing && !undoManager.isRedoing
        if owned { undoManager.beginUndoGrouping() }
        undoManager.registerUndo(withTarget: self) { target in
            MainActor.assumeIsolated { target.restoreManifest(previous) }
        }
        undoManager.setActionName("Change")
        if owned { undoManager.endUndoGrouping() }
    }

    func undoEdit() {
        guard undoManager.canUndo else { return }
        undoManager.undo()
        refreshUndoState()
    }

    func redoEdit() {
        guard undoManager.canRedo else { return }
        undoManager.redo()
        refreshUndoState()
    }

    /// Copies the two flags out of `UndoManager`, which predates Observation
    /// and publishes nothing SwiftUI reads.
    ///
    /// ponytail: pulled at every entry point instead of observed. This
    /// extension is the only thing that registers against the target, so there
    /// is no third party that can change the stack behind it. Observe
    /// `NSUndoManagerDidUndoChange` if something outside ever registers.
    private func refreshUndoState() {
        canUndoEdit = undoManager.canUndo
        canRedoEdit = undoManager.canRedo
    }
}
