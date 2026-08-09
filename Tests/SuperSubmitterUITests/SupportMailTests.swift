import Foundation
import Testing
@testable import SuperSubmitter

/// The About panel's one button.
///
/// A mailto URL carrying a multi-line body is the part worth pinning: an
/// unescaped newline or `&` makes `URLComponents` hand back a URL that a mail
/// client either refuses or truncates, and the failure is silent. The button
/// only exists for the day something is already broken, so it does not get to
/// be the second thing that is.
@Suite struct SupportMailTests {

    @Test func theURLIsAMailtoToTheSupportAddress() {
        let url = AboutPanel.supportURL
        #expect(url.scheme == "mailto")
        #expect(url.path == AboutPanel.supportEmail)
    }

    @Test func theSubjectNamesTheVersionAndTheBuild() throws {
        let items = try #require(
            URLComponents(url: AboutPanel.supportURL, resolvingAgainstBaseURL: false)?.queryItems)
        let subject = try #require(items.first { $0.name == "subject" }?.value)
        #expect(subject.contains(AboutPanel.version))
        #expect(subject.contains(AboutPanel.build))
    }

    /// Read back through `URLComponents`, so this fails if the newlines or the
    /// separators do not survive the round trip rather than merely looking
    /// right in the source.
    @Test func theBodySurvivesTheRoundTrip() throws {
        let items = try #require(
            URLComponents(url: AboutPanel.supportURL, resolvingAgainstBaseURL: false)?.queryItems)
        let body = try #require(items.first { $0.name == "body" }?.value)

        #expect(body == AboutPanel.supportBody)
        #expect(body.contains("What were you doing?"))
        #expect(body.contains("What happened instead?"))
        #expect(body.contains("\n"))
    }

    /// The three lines that exist so a reply does not have to ask for them.
    @Test func theBodyCarriesTheVersionTheSystemAndTheMachine() {
        let body = AboutPanel.supportBody
        #expect(body.contains(AboutPanel.version))
        #expect(body.contains(AboutPanel.build))
        #expect(body.contains("macOS "))
        #expect(body.contains("Apple silicon") || body.contains("Intel"))
    }

    /// The panel may not call the product "unknown".
    ///
    /// It did, in every build that is not the Xcode app. A SwiftPM executable
    /// carries no Info.plist, so `Bundle.main` answered nothing and the panel
    /// printed the fallback as the name of the app, as its copyright, and in
    /// the support subject. The package build is the one `tools/screenshots.sh`
    /// runs, so that was the About panel on the website.
    ///
    /// The test runs in exactly that bundle, which is what makes it worth
    /// having: it is the case that was broken.
    @Test func theNameAndTheCopyrightAreNeverUnknown() {
        #expect(AboutPanel.appName == "Super Submitter")
        #expect(!AboutPanel.copyright.isEmpty)
        #expect(!AboutPanel.copyright.lowercased().contains("unknown"))
        // The version is a fact of the build, not of the product, so a package
        // build is allowed to have none. It may not guess at one.
        #expect(!AboutPanel.version.lowercased().contains("unknown"))
        #expect(!AboutPanel.build.lowercased().contains("unknown"))
    }

    /// The report is diagnostics and nothing else. A support mail the user has
    /// not read yet must not carry an account, a path, or a key out of the
    /// machine, so the shapes that would carry one are named here.
    @Test func theBodyCarriesNothingIdentifying() {
        let body = AboutPanel.supportBody
        #expect(!body.contains("/Users/"))
        #expect(!body.contains(NSHomeDirectory()))
        #expect(!body.lowercased().contains("token"))
        #expect(!body.lowercased().contains("password"))
        #expect(!body.lowercased().contains("secret"))
        // The one address in there is the one it is being sent to.
        #expect(body.filter { $0 == "@" }.isEmpty)
    }
}
