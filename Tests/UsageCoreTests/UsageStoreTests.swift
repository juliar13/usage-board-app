import Foundation
import Testing
@testable import UsageCore

@MainActor
struct UsageStoreTests {
    @Test func retainsLastSuccessWhenRefreshFails() async throws {
        let store = UsageStore()
        let now = Date(timeIntervalSince1970: 100)
        await store.refresh(using: FixedProvider(result: .success(.demo(at: now))), now: now)
        #expect(store.snapshot != nil)
        #expect(store.lastUpdated == now)
        #expect(store.errorMessage == nil)
        await store.refresh(using: FixedProvider(result: .failure(.timedOut)), now: now.addingTimeInterval(60))
        #expect(store.snapshot != nil)
        #expect(store.lastUpdated == now)
        #expect(store.errorMessage != nil)
        #expect(!store.isRefreshing)
    }

    @Test func clearsOldAccountDataForAuthenticationFailure() async {
        let store = UsageStore()
        await store.refresh(using: FixedProvider(result: .success(.demo(at: Date()))))
        await store.refresh(using: FixedProvider(result: .failure(.authenticationRequired)))
        #expect(store.snapshot == nil)
        #expect(store.lastUpdated == nil)
        #expect(store.errorMessage != nil)
    }

    @Test func doesNotTreatEmptyLimitsAsZero() async throws {
        let store = UsageStore()
        await store.refresh(using: FixedProvider(result: .success(try decodeLimits("{}"))))
        #expect(store.snapshot?.buckets.isEmpty == true)
        #expect(store.errorMessage == nil)
    }

    @Test func coalescesConcurrentRefreshes() async {
        let store = UsageStore()
        let provider = SuspendedProvider()
        let first = Task { await store.refresh(using: provider) }
        while !store.isRefreshing { await Task.yield() }
        await store.refresh(using: provider)
        await first.value
        #expect(await provider.calls == 1)
    }

    @Test func changingConnectionDiscardsInFlightResult() async {
        let store = UsageStore()
        let first = Task { await store.refresh(using: SuspendedProvider()) }
        while !store.isRefreshing { await Task.yield() }
        store.reset()
        await first.value
        #expect(store.snapshot == nil)
        #expect(store.lastUpdated == nil)
    }
}

private struct FixedProvider: UsageProviding {
    let result: Result<UsageLimits, UsageClientError>
    func fetch() async throws -> UsageLimits { try result.get() }
}

private actor SuspendedProvider: UsageProviding {
    var calls = 0
    func fetch() async throws -> UsageLimits {
        calls += 1
        try await Task.sleep(for: .milliseconds(100))
        return .demo(at: Date())
    }
}
