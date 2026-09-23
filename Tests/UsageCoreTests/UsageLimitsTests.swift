import Foundation
import Testing
@testable import UsageCore

struct UsageLimitsTests {
    @Test func convertsUsedToRemainingAndClamps() throws {
        for (used, remaining) in [(25.0, 75.0), (0, 100), (100, 0), (130, 0), (-10, 100)] {
            let window = try JSONDecoder().decode(UsageWindow.self, from: Data("{\"usedPercent\":\(used)}".utf8))
            #expect(window.remainingPercent == remaining)
        }
    }

    @Test func missingValuesAreUnknown() throws {
        let window = try JSONDecoder().decode(UsageWindow.self, from: Data("{}".utf8))
        #expect(window.remainingPercent == nil)
        #expect(window.resetDate == nil)
        #expect(window.durationLabel == "期間不明")
        #expect(window.countdown(at: Date()) == "リセット時刻不明")
    }

    @Test func prefersMultipleBucketsAndKeepsTheirKeys() throws {
        let limits = try decodeLimits("""
        {"rateLimits":{"primary":{"usedPercent":99}},
         "rateLimitsByLimitId":{
           "other":{"primary":{"usedPercent":40}},
           "codex":{"primary":{"usedPercent":25},"secondary":{"usedPercent":5}}
         }}
        """)
        #expect(limits.buckets.map(\.id) == ["codex", "other"])
        #expect(limits.buckets.first?.primary?.remainingPercent == 75)
        #expect(limits.buckets.first?.secondary?.remainingPercent == 95)
    }

    @Test func legacyFallbackAndEmptyPayload() throws {
        let legacy = try decodeLimits("{\"rateLimits\":{\"primary\":{\"usedPercent\":17}},\"rateLimitsByLimitId\":{}}")
        #expect(legacy.buckets.count == 1)
        #expect(legacy.buckets.first?.id == "codex")
        #expect(try decodeLimits("{}").buckets.isEmpty)
        #expect(try decodeLimits("{\"rateLimits\":null}").buckets.isEmpty)
    }

    @Test func countdownUsesUnixSecondsAndNeverGoesNegative() {
        let window = UsageWindow(usedPercent: 25, windowDurationMins: 300, resetsAt: 10_000)
        #expect(window.durationLabel == "5時間枠")
        #expect(window.resetDate == Date(timeIntervalSince1970: 10_000))
        #expect(window.countdown(at: Date(timeIntervalSince1970: 6_339)) == "1時間 01分 01秒")
        #expect(window.countdown(at: Date(timeIntervalSince1970: 10_001)) == "リセット待ち")
        #expect(window.remainingPercent == 75) // Clock expiry must not invent a refreshed quota.
    }

    @Test func supportsWeeklyAndNonstandardWindows() {
        #expect(UsageWindow(usedPercent: 0, windowDurationMins: 10_080, resetsAt: nil).durationLabel == "週間枠")
        #expect(UsageWindow(usedPercent: 0, windowDurationMins: 15, resetsAt: nil).durationLabel == "15分枠")
        let window = UsageWindow(usedPercent: 0, windowDurationMins: nil, resetsAt: 100_000)
        #expect(window.countdown(at: Date(timeIntervalSince1970: 0)) == "1日 3時間 46分")
    }

    @Test func displaysOnlyReturnedPeriodsAndRecognizesWeeklyPrimary() throws {
        let limits = try decodeLimits("""
        {"rateLimits":{"primary":{"usedPercent":46,"windowDurationMins":10080},"secondary":null}}
        """)
        let periods = try #require(limits.buckets.first).periods
        #expect(periods.count == 1)
        #expect(periods.first?.title == "週間")
        #expect(periods.first?.isLongWindow == true)
        #expect(try decodeLimits("{\"rateLimits\":{}}").buckets.first?.periods.isEmpty == true)
    }

    @Test func decodesAvailableResetCountAndExpiries() throws {
        let limits = try decodeLimits("""
        {"rateLimitResetCredits":{"availableCount":3,"credits":[
          {"id":"first","resetType":"codexRateLimits","status":"available","grantedAt":100,"expiresAt":200,"title":"Full reset"},
          {"id":"second","resetType":"codexRateLimits","status":"available","grantedAt":101,"expiresAt":null},
          {"id":"old","resetType":"codexRateLimits","status":"redeemed","grantedAt":90,"expiresAt":150}
        ]}}
        """)
        let summary = try #require(limits.rateLimitResetCredits)
        #expect(summary.availableCount == 3)
        #expect(summary.availableCredits.map(\.id) == ["first", "second"])
        #expect(summary.availableCredits.first?.expirationDate == Date(timeIntervalSince1970: 200))
        #expect(summary.availableCredits.last?.expirationDate == nil)
        #expect(summary.availableCredits.first?.displayTitle == "完全リセット")
    }

    @Test func distinguishesUnavailableResetDetailsFromEmptyDetails() throws {
        #expect(try decodeLimits("{}").rateLimitResetCredits == nil)
        let countOnly = try decodeLimits("{\"rateLimitResetCredits\":{\"availableCount\":2,\"credits\":null}}")
        #expect(countOnly.rateLimitResetCredits?.availableCount == 2)
        #expect(countOnly.rateLimitResetCredits?.credits == nil)
        let empty = try decodeLimits("{\"rateLimitResetCredits\":{\"availableCount\":0,\"credits\":[]}}")
        #expect(empty.rateLimitResetCredits?.credits?.isEmpty == true)
    }
}

func decodeLimits(_ json: String) throws -> UsageLimits {
    try JSONDecoder().decode(UsageLimits.self, from: Data(json.utf8))
}
