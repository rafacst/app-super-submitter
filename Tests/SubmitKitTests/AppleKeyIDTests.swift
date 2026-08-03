import Foundation
import Testing
@testable import SubmitKit

/// A wrong key id fails the connection with an error that names nothing
/// useful, so the parser answers nil for anything that is not Apple's shape.
@Test func theKeyIDComesOutOfApplesOwnFileName() {
    #expect(AppleCredential.keyID(fromFileName: "AuthKey_Z2YFP2FP9D.p8") == "Z2YFP2FP9D")
    #expect(AppleCredential.keyID(fromFileName: "AuthKey_ABC123DEFG.p8") == "ABC123DEFG")
    // A renamed file that is still only the id.
    #expect(AppleCredential.keyID(fromFileName: "Z2YFP2FP9D.p8") == "Z2YFP2FP9D")
    #expect(AppleCredential.keyID(fromFileName: "authkey_Z2YFP2FP9D.p8") == "Z2YFP2FP9D")
}

@Test func aFileNameWithoutAKeyIDAnswersNothing() {
    #expect(AppleCredential.keyID(fromFileName: "AuthKey_backup.p8") == nil)
    #expect(AppleCredential.keyID(fromFileName: "my key.p8") == nil)
    #expect(AppleCredential.keyID(fromFileName: "AuthKey_z2yfp2fp9d.p8") == nil)
    // Apple issues ten characters, never nine and never eleven.
    #expect(AppleCredential.keyID(fromFileName: "AuthKey_Z2YFP2FP9.p8") == nil)
    #expect(AppleCredential.keyID(fromFileName: "AuthKey_Z2YFP2FP9DX.p8") == nil)
    #expect(AppleCredential.keyID(fromFileName: "AuthKey_Z2YFP2FP9D copy.p8") == nil)
    #expect(AppleCredential.keyID(fromFileName: "") == nil)
}
