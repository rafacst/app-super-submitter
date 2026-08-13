import Foundation
import Testing
@testable import SubmitKit

/// Which subscription group holds which plan.
///
/// The import used to read this off each included subscription, from a
/// `relationships.group` that a real payload does not carry:
/// `subscriptionGroups?include=subscriptions` returns the subscriptions flat.
/// Every plan therefore landed under the empty-string key and every group came
/// back empty, which is an app whose subscriptions have been on sale for years
/// showing a group with no plans in it.
@Suite struct SubscriptionGroupMembershipTests {

    /// The production shape: membership lives on the group alone.
    @Test func membershipIsReadFromTheGroupsOwnRelationshipList() {
        let payload = JSON(data: Data(#"""
        {"data":[
          {"type":"subscriptionGroups","id":"g1",
           "attributes":{"referenceName":"Premium"},
           "relationships":{"subscriptions":{"data":[
             {"type":"subscriptions","id":"s1"},
             {"type":"subscriptions","id":"s2"}]}}},
          {"type":"subscriptionGroups","id":"g2",
           "attributes":{"referenceName":"Pro Tools"},
           "relationships":{"subscriptions":{"data":[
             {"type":"subscriptions","id":"s3"}]}}}],
         "included":[
          {"type":"subscriptions","id":"s1",
           "attributes":{"productId":"com.example.monthly",
                         "subscriptionPeriod":"ONE_MONTH","state":"APPROVED"}},
          {"type":"subscriptions","id":"s2",
           "attributes":{"productId":"com.example.yearly",
                         "subscriptionPeriod":"ONE_YEAR","state":"APPROVED"}},
          {"type":"subscriptions","id":"s3",
           "attributes":{"productId":"com.example.tools",
                         "subscriptionPeriod":"ONE_MONTH","state":"APPROVED"}}]}
        """#.utf8))

        let groups = StoreImportReader.appleSubscriptionGroups(payload)

        #expect(groups.count == 2)
        let premium = groups.first { $0.groupName == "Premium" }
        #expect(premium?.plans.map(\.id) == ["com.example.monthly", "com.example.yearly"])
        // In the order the group lists them, not the order Apple happened to
        // include them in.
        #expect(premium?.plans.map(\.duration) == ["P1M", "P1Y"])
        #expect(groups.first { $0.groupName == "Pro Tools" }?.plans.map(\.id)
                == ["com.example.tools"])
    }

    /// A payload that does carry the reverse link still works, so nothing that
    /// worked before this stops working.
    @Test func theReverseLinkIsStillHonouredWhereItExists() {
        let payload = JSON(data: Data(#"""
        {"data":[{"type":"subscriptionGroups","id":"g1",
                  "attributes":{"referenceName":"Premium"}}],
         "included":[{"type":"subscriptions","id":"s1",
                      "attributes":{"productId":"com.example.monthly",
                                    "subscriptionPeriod":"ONE_MONTH"},
                      "relationships":{"group":{"data":{"id":"g1"}}}}]}
        """#.utf8))

        let groups = StoreImportReader.appleSubscriptionGroups(payload)

        #expect(groups.first?.plans.map(\.id) == ["com.example.monthly"])
    }

    /// A group Apple holds with nothing in it is a group with no plans, and
    /// not a reason to drop the group.
    @Test func anEmptyGroupSurvivesWithNoPlans() {
        let payload = JSON(data: Data(#"""
        {"data":[{"type":"subscriptionGroups","id":"g1",
                  "attributes":{"referenceName":"Empty"},
                  "relationships":{"subscriptions":{"data":[]}}}],
         "included":[]}
        """#.utf8))

        let groups = StoreImportReader.appleSubscriptionGroups(payload)

        #expect(groups.count == 1)
        #expect(groups.first?.groupName == "Empty")
        #expect(groups.first?.plans.isEmpty == true)
    }

    /// A subscription listed by a group but missing from `included` costs that
    /// one plan. The rest of the group still arrives.
    @Test func aMissingIncludedSubscriptionCostsOnlyItself() {
        let payload = JSON(data: Data(#"""
        {"data":[{"type":"subscriptionGroups","id":"g1",
                  "attributes":{"referenceName":"Premium"},
                  "relationships":{"subscriptions":{"data":[
                    {"type":"subscriptions","id":"s1"},
                    {"type":"subscriptions","id":"missing"}]}}}],
         "included":[{"type":"subscriptions","id":"s1",
                      "attributes":{"productId":"com.example.monthly",
                                    "subscriptionPeriod":"ONE_MONTH"}}]}
        """#.utf8))

        let groups = StoreImportReader.appleSubscriptionGroups(payload)

        #expect(groups.first?.plans.map(\.id) == ["com.example.monthly"])
    }
}
