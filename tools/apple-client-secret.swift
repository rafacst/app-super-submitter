#!/usr/bin/swift
// Makes the Sign in with Apple client secret that Supabase asks for.
//
//   swift tools/apple-client-secret.swift \
//     --key ~/Downloads/AuthKey_XXXXXXXXXX.p8 \
//     --key-id XXXXXXXXXX \
//     --team-id 88BXH8KNVZ \
//     --services-id com.rafacst.supersubmitter.signin
//
// Apple's client secret is a JWT, not the key itself, and it expires. Six
// months is the ceiling Apple allows, so that is what this uses. Put the
// expiry date in a calendar: when it passes, every Apple sign-in fails until
// a new secret reaches Supabase.
//
// Supabase publishes a browser tool for this. This exists so the .p8 never
// leaves the machine and never goes into a web form.
//
// ponytail: no argument parser and no key storage. It reads a file, prints
// one line, and forgets. The .p8 belongs in your password manager.

import CryptoKit
import Foundation

func argument(_ name: String) -> String? {
    guard let index = CommandLine.arguments.firstIndex(of: "--\(name)"),
          index + 1 < CommandLine.arguments.count else { return nil }
    return CommandLine.arguments[index + 1]
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data("error: \(message)\n".utf8))
    exit(1)
}

guard let keyPath = argument("key"), let keyID = argument("key-id"),
      let teamID = argument("team-id"), let servicesID = argument("services-id") else {
    fail("""
    usage: swift tools/apple-client-secret.swift \\
             --key <AuthKey_XXXX.p8> --key-id <KEY_ID> \\
             --team-id <TEAM_ID> --services-id <SERVICES_ID>
    """)
}

let expanded = (keyPath as NSString).expandingTildeInPath
guard let pem = try? String(contentsOfFile: expanded, encoding: .utf8) else {
    fail("cannot read \(expanded)")
}
guard let key = try? P256.Signing.PrivateKey(pemRepresentation: pem) else {
    fail("\(expanded) is not a PEM encoded P-256 private key. Apple's .p8 is one.")
}

extension Data {
    var base64URL: String {
        base64EncodedString()
            .replacingOccurrences(of: "+", with: "-")
            .replacingOccurrences(of: "/", with: "_")
            .replacingOccurrences(of: "=", with: "")
    }
}

let issued = Int(Date().timeIntervalSince1970)
// 15777000 seconds is Apple's documented ceiling. A longer exp is refused.
let expires = issued + 15_777_000
let header: [String: Any] = ["alg": "ES256", "kid": keyID, "typ": "JWT"]
let payload: [String: Any] = [
    "iss": teamID,
    "iat": issued,
    "exp": expires,
    "aud": "https://appleid.apple.com",
    // The Services ID, not the bundle ID. Apple checks this against the
    // client_id Supabase sends, and a bundle ID here fails at sign-in only.
    "sub": servicesID,
]

let options: JSONSerialization.WritingOptions = [.sortedKeys, .withoutEscapingSlashes]
guard let headerData = try? JSONSerialization.data(withJSONObject: header, options: options),
      let payloadData = try? JSONSerialization.data(withJSONObject: payload, options: options) else {
    fail("could not encode the token")
}
let signingInput = "\(headerData.base64URL).\(payloadData.base64URL)"
guard let signature = try? key.signature(for: Data(signingInput.utf8)) else {
    fail("could not sign the token")
}

let formatter = DateFormatter()
formatter.dateFormat = "yyyy-MM-dd"
FileHandle.standardError.write(Data(
    "This secret expires on \(formatter.string(from: Date(timeIntervalSince1970: TimeInterval(expires)))). Put that date in a calendar.\n".utf8))

print("\(signingInput).\(signature.rawRepresentation.base64URL)")
