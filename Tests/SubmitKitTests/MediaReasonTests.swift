import Foundation
import Testing
@testable import SubmitKit

/// Why a set of pictures is being sent again.
///
/// Screenshots are the whole weight of an update, and the row that proposes
/// them gave no reason at all: "replace with 5 screenshots · 12 MB". The
/// commonest question about this app was why it wanted to send pictures the
/// store already had, and the plan knew the answer every time.
@Suite struct MediaReasonTests {
    private let desired = ["a", "b", "c"]

    @Test func aStoreThatWasNeverReadSaysSo() {
        #expect(Planner.mediaReason(read: false, starting: nil, desired: desired)
                == "the store was not read")
    }

    /// The commonest one: the version being written to starts out empty, so
    /// there is nothing on the store to match against.
    @Test func aVersionHoldingNothingSaysSo() {
        #expect(Planner.mediaReason(read: true, starting: nil, desired: desired)
                == "the store holds none")
        #expect(Planner.mediaReason(read: true, starting: [], desired: desired)
                == "the store holds none")
    }

    /// Apple shows screenshots in the order they were uploaded, so the same
    /// pictures in another order is a real change and a cheap one to explain.
    @Test func theSamePicturesInAnotherOrderSayJustThat() {
        #expect(Planner.mediaReason(read: true, starting: ["c", "a", "b"], desired: desired)
                == "the same pictures, in another order")
    }

    @Test func aPartialChangeCountsWhatChanged() {
        #expect(Planner.mediaReason(read: true, starting: ["a", "b", "z"], desired: desired)
                == "1 of 3 differ")
    }

    /// What a re-export looks like: the pictures look identical and every
    /// checksum is new, because the comparison is on the bytes.
    @Test func aFullReplacementSaysAll() {
        #expect(Planner.mediaReason(read: true, starting: ["x", "y", "z"], desired: desired)
                == "all 3 differ")
    }

    @Test func aDifferentCountIsNamedByWhatTheStoreHolds() {
        #expect(Planner.mediaReason(read: true, starting: ["x", "y"], desired: desired)
                == "the store holds 2")
    }
}
