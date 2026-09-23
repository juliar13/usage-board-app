import Foundation
import Observation

@MainActor
@Observable
public final class UsageStore {
    public private(set) var snapshot: UsageLimits?
    public private(set) var lastUpdated: Date?
    public private(set) var errorMessage: String?
    public private(set) var isRefreshing = false
    private var generation = 0

    public init() {}

    public func reset() {
        generation += 1
        snapshot = nil
        lastUpdated = nil
        errorMessage = nil
        isRefreshing = false
    }

    public func refresh(using provider: any UsageProviding, now: Date? = nil) async {
        guard !isRefreshing else { return }
        let requestGeneration = generation
        isRefreshing = true
        defer { if generation == requestGeneration { isRefreshing = false } }
        do {
            let value = try await provider.fetch()
            try Task.checkCancellation()
            guard generation == requestGeneration else { return }
            snapshot = value
            lastUpdated = now ?? Date()
            errorMessage = nil
        } catch is CancellationError {
            // Closing a window or changing a connection is not a connection error.
        } catch {
            guard generation == requestGeneration else { return }
            if let clientError = error as? UsageClientError,
               clientError == .authenticationRequired || clientError == .unsupportedAccount {
                snapshot = nil
                lastUpdated = nil
            }
            errorMessage = (error as? UsageClientError)?.errorDescription ?? UsageClientError.requestFailed.errorDescription
        }
    }
}

public struct DemoUsageProvider: UsageProviding {
    private let limits: UsageLimits
    public init(now: Date = Date()) { limits = .demo(at: now) }
    public func fetch() async throws -> UsageLimits { limits }
}
