import Foundation
import Testing
@testable import SubmitKit

// The three states of a managed field. A plain Optional loses the middle one,
// and the middle one decides whether an apply clears a live store field.

@Test func absentKeyIsUnmanaged() throws {
    let yaml = """
        version: 1
        apps: {}
        listing:
          defaultLocale: en-US
          locales:
            en-US:
              name: Fast Bill Split
        """
    let manifest = try ManifestFile.decode(yaml)
    let locale = try #require(manifest.listing?.locales["en-US"])
    #expect(locale.subtitle == .unmanaged)
    #expect(locale.subtitle.isManaged == false)
}

@Test func nullKeyClearsTheField() throws {
    let yaml = """
        version: 1
        apps: {}
        listing:
          defaultLocale: en-US
          locales:
            en-US:
              name: Fast Bill Split
              subtitle: null
        """
    let locale = try #require(try ManifestFile.decode(yaml).listing?.locales["en-US"])
    #expect(locale.subtitle == .clear)
    #expect(locale.subtitle.isManaged)
}

@Test func theThreeStatesSurviveARoundTrip() throws {
    let yaml = """
        version: 1
        apps: {}
        listing:
          defaultLocale: en-US
          locales:
            en-US:
              name: Fast Bill Split
              subtitle: null
              description: Split a restaurant bill with your friends.
        """
    let first = try ManifestFile.decode(yaml)
    let second = try ManifestFile.decode(ManifestFile.encode(first))
    let locale = try #require(second.listing?.locales["en-US"])

    #expect(locale.subtitle == .clear)                 // null stayed null
    #expect(locale.keywords == .unmanaged)             // absent stayed absent
    #expect(locale.description == .value("Split a restaurant bill with your friends."))
    #expect(first == second)
}

// Money. `Decimal(4.99)` is not 4.99, and this app writes prices to a store.

@Test func aPriceKeepsItsExactAmount() throws {
    let yaml = """
        version: 1
        apps: {}
        pricing:
          base:
            amount: 4.99
            currency: USD
            territory: USA
        """
    let price = try #require(try ManifestFile.decode(yaml).pricing?.base)
    #expect(price.amount == Decimal(string: "4.99"))
    #expect("\(price.amount)" == "4.99")
    #expect(price.territory == "USA")
}

// The full example from spec section 5.2 must load.

@Test func theSpecExampleLoads() throws {
    let manifest = try ManifestFile.decode(specExample)

    #expect(manifest.version == 1)
    #expect(manifest.apps.apple?.bundleId == "com.example.app")
    #expect(manifest.apps.apple?.platforms == [.ios, .macOS])
    #expect(manifest.apps.google?.packageName == "com.example.app")
    #expect(manifest.monetization?.provider == .revenuecat)
    #expect(manifest.monetization?.revenuecat?.appIds.playStore == "app9g0h1i2")
    #expect(manifest.release?.apple?.releaseType == .afterApproval)
    #expect(manifest.listing?.locales.count == 2)
    #expect(manifest.listing?.locales["pt-BR"]?.name == "Divide a Conta")
    #expect(manifest.media?.screenshots?["en-US"]?["phone"]?.count == 1)
    #expect(manifest.purchases?.first?.kind == .nonConsumable)
    #expect(manifest.subscriptions?.first?.plans.count == 2)
    #expect(manifest.subscriptions?.first?.plans.last?.duration == "P1Y")
    #expect(manifest.offerings?.first?.isCurrent == true)
    #expect(manifest.review?.demoAccountRequired == false)
}

private let specExample = """
    version: 1

    apps:
      apple:
        appId: "1234567890"
        platforms: [IOS, MAC_OS]
        bundleId: com.example.app
      google:
        packageName: com.example.app

    monetization:
      provider: revenuecat
      revenuecat:
        projectId: proj1ab2c3d4
        appIds:
          app_store: app1a2b3c4
          mac_app_store: app5d6e7f8
          play_store: app9g0h1i2

    release:
      versionName: "3.2.0"
      build:
        ios: build/App.ipa
        macos: build/App.pkg
        android: build/app.aab
      apple:
        releaseType: AFTER_APPROVAL
        phasedRelease: true
      google:
        track: production
        status: completed
        userFraction: null
        inAppUpdatePriority: 0

    listing:
      defaultLocale: en-US
      locales:
        en-US:
          name: "Fast Bill Split"
          subtitle: "Split any bill in seconds"
          description: |
            Split a restaurant bill with your friends. No account. No ads.
          whatsNew: "Faster scanning and a new dark theme."
          keywords: "bill,split,tip,receipt,restaurant"
          promotionalText: "Now with receipt scanning."
          supportUrl: https://example.com/support
          marketingUrl: https://example.com
          google:
            shortDescription: "Split any bill in seconds with your friends"
            video: https://youtube.com/watch?v=xxxx
            whatsNew: "Faster scanning and a new dark theme."
        pt-BR:
          name: "Divide a Conta"
          subtitle: "Divida a conta em segundos"
          description: |
            Divida a conta do restaurante com os seus amigos.
          whatsNew: "Leitura mais rapida e um tema escuro novo."
          keywords: "conta,dividir,gorjeta,recibo,restaurante"

    media:
      screenshots:
        en-US:
          phone:   [assets/en/phone/*.png]
          tablet10: [assets/en/tablet/*.png]
          desktop: [assets/en/mac/*.png]
        pt-BR:
          phone:   [assets/pt/phone/*.png]
      previews:
        en-US:
          phone:   [assets/en/preview/*.mov]
      icon: assets/icon-512.png
      featureGraphic: assets/feature.png

    pricing:
      base:
        amount: 4.99
        currency: USD
        territory: USA
      autoConvertOtherTerritories: true

    purchases:
      - id: com.example.app.pro
        kind: non_consumable
        name: "Pro Unlock"
        price: { amount: 9.99, currency: USD }
        reviewNote: "Tap Settings, then Upgrade."
        entitlements: [pro]
        locales:
          en-US: { name: "Pro Unlock", description: "Unlock every feature forever." }
          pt-BR: { name: "Versao Pro", description: "Desbloqueie todos os recursos." }

    subscriptions:
      - groupId: main
        groupName: "Fast Bill Split Premium"
        plans:
          - id: com.example.app.premium.monthly
            duration: P1M
            basePlanId: monthly
            price: { amount: 2.99, currency: USD }
            entitlements: [premium]
            packageKey: monthly
            locales:
              en-US: { name: "Premium Monthly", description: "Unlimited splits." }
          - id: com.example.app.premium.yearly
            duration: P1Y
            basePlanId: annual
            price: { amount: 24.99, currency: USD }
            entitlements: [premium]
            packageKey: annual
            locales:
              en-US: { name: "Premium Yearly", description: "Unlimited splits. Two months free." }

    entitlements:
      - key: pro
        name: "Pro"
      - key: premium
        name: "Premium"

    offerings:
      - key: default
        name: "Standard offering"
        isCurrent: true
        products: [com.example.app.premium.monthly, com.example.app.premium.yearly]

    review:
      contactFirstName: Rafa
      contactLastName: C
      contactEmail: dev@example.com
      contactPhone: "+351000000000"
      demoAccountRequired: false
      notes: "No login is necessary."
    """
