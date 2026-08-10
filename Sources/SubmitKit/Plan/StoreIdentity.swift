import Foundation

/// The one rule for "does the store already hold this?".
///
/// The manifest names a marketing resource twice. `key` is the handle the
/// developer never changes, and `name` is the words a person reads. Apple
/// stores one string, so the two have to be reconciled somewhere, and three
/// places reconciled it differently:
///
/// - The apply created a custom product page under the **key** and then renamed
///   it to the **name**, while every lookup asked for the key again. The third
///   apply of an unchanged manifest found nothing, created a second page, and
///   every apply after it leaked another one. The experiments carried the same
///   pattern.
/// - The planner asked by **name**, so the plan and the apply could disagree
///   about whether a resource existed.
/// - The Marketing tab asked by either, which is the only one of the three that
///   was right, and it could not stop the apply duplicating behind it.
///
/// So the rule lives here and the three of them call it. A store is asked under
/// both spellings, because a store that has been through the older build can be
/// holding either one, and a resource is created under the name it will keep,
/// so nothing has to be renamed later.
public enum StoreIdentity {

    /// What the store holds for this resource, under either spelling.
    ///
    /// The key first. It is the handle the manifest owns, so when a store
    /// somehow holds both, the key is the one the developer meant.
    public static func value<Held>(key: String, name: String,
                                   in held: [String: Held]) -> Held? {
        if !key.isEmpty, let found = held[key] { return found }
        if !name.isEmpty, let found = held[name] { return found }
        return nil
    }

    /// Whether the store holds it at all.
    public static func holds<Held>(key: String, name: String,
                                   in held: [String: Held]) -> Bool {
        value(key: key, name: name, in: held) != nil
    }

    /// The name to create a resource under.
    ///
    /// The words a person reads, so no later apply has to rename it, and the
    /// rename is the whole of what made the older build duplicate. An entry
    /// with no name keeps its key, because a resource has to be called
    /// something and the key is the only other thing there is.
    public static func displayName(key: String, name: String) -> String {
        name.isEmpty ? key : name
    }
}
