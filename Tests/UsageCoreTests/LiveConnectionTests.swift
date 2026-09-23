import Foundation
import Testing
@testable import UsageCore

struct LiveConnectionTests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["USAGE_BOARD_LIVE_TEST"] == "1"))
    func readsExistingCodexAccount() async throws {
        let path = try #require(CodexLocator.locate())
        let limits = try await CodexUsageClient(executablePath: path).fetch()
        #expect(!limits.buckets.isEmpty)
        #expect(limits.buckets.contains { $0.primary?.remainingPercent != nil || $0.secondary?.remainingPercent != nil })
    }
}
