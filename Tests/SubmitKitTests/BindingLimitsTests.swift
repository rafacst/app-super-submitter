import Testing
@testable import SubmitKit

// Spec section 6.1. The binding limit is the smallest limit among the stores
// that receive the shared value.

@Test func bothStoresBindToTheSmallerLimit() {
    #expect(BindingLimits.binding(for: .subtitle, stores: [.apple, .google]) == 30)
    #expect(BindingLimits.binding(for: .whatsNew, stores: [.apple, .google]) == 500)
    #expect(BindingLimits.binding(for: .description, stores: [.apple, .google]) == 4000)
}

@Test func oneStoreBindsToItsOwnLimit() {
    #expect(BindingLimits.binding(for: .subtitle, stores: [.google]) == 80)
    #expect(BindingLimits.binding(for: .whatsNew, stores: [.apple]) == 4000)
}

@Test func anOverrideRemovesThatStoreFromTheCalculation() {
    // The developer wrote google.whatsNew, so the shared value is Apple only.
    #expect(BindingLimits.binding(for: .whatsNew,
                                  stores: [.apple, .google],
                                  overriddenIn: [.google]) == 4000)
    #expect(BindingLimits.binding(for: .subtitle,
                                  stores: [.apple, .google],
                                  overriddenIn: [.google]) == 30)
}

@Test func aFieldThatNoSelectedStoreReadsHasNoLimit() {
    #expect(BindingLimits.binding(for: .keywords, stores: [.google]) == nil)
    #expect(BindingLimits.binding(for: .shortDescription, stores: [.apple]) == nil)
    #expect(BindingLimits.binding(for: .subtitle, stores: []) == nil)
}

@Test func theOverflowCountsTheCharactersOverTheLimit() {
    let thirtyOne = String(repeating: "a", count: 31)
    #expect(BindingLimits.overflow(thirtyOne, for: .name, stores: [.apple, .google]) == 1)
    #expect(BindingLimits.overflow("Fast Bill Split", for: .name, stores: [.apple]) == 0)

    // No limit means no overflow. It never blocks a field that nobody reads.
    #expect(BindingLimits.overflow(thirtyOne, for: .keywords, stores: [.google]) == 0)
}
