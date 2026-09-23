import Foundation

public struct UsageWindow: Codable, Equatable, Sendable {
    public let usedPercent: Double?
    public let windowDurationMins: Int?
    public let resetsAt: Double?

    public init(usedPercent: Double?, windowDurationMins: Int?, resetsAt: Double?) {
        self.usedPercent = usedPercent
        self.windowDurationMins = windowDurationMins
        self.resetsAt = resetsAt
    }

    public var remainingPercent: Double? {
        guard let usedPercent, usedPercent.isFinite else { return nil }
        return min(100, max(0, 100 - usedPercent))
    }

    public var resetDate: Date? {
        guard let resetsAt, resetsAt.isFinite, resetsAt > 0, resetsAt < 253_402_300_800 else { return nil }
        return Date(timeIntervalSince1970: resetsAt)
    }

    public var durationLabel: String {
        guard let minutes = windowDurationMins, minutes > 0 else { return "期間不明" }
        if minutes == 10_080 { return "週間枠" }
        if minutes.isMultiple(of: 1_440) { return "\(minutes / 1_440)日枠" }
        if minutes.isMultiple(of: 60) { return "\(minutes / 60)時間枠" }
        return "\(minutes)分枠"
    }

    public func countdown(at now: Date) -> String {
        guard let resetDate else { return "リセット時刻不明" }
        let interval = resetDate.timeIntervalSince(now)
        guard interval > 0 else { return "リセット待ち" }
        let seconds = Int(ceil(interval))
        let days = seconds / 86_400
        let hours = (seconds % 86_400) / 3_600
        let minutes = (seconds % 3_600) / 60
        if days > 0 { return "\(days)日 \(hours)時間 \(minutes)分" }
        return String(format: "%d時間 %02d分 %02d秒", hours, minutes, seconds % 60)
    }
}

public struct RateLimitBucket: Codable, Equatable, Sendable {
    public var limitId: String?
    public let limitName: String?
    public let primary: UsageWindow?
    public let secondary: UsageWindow?
    public let planType: String?
}

public struct UsageBucket: Identifiable, Equatable, Sendable {
    public let id: String
    public let limits: RateLimitBucket
    public var primary: UsageWindow? { limits.primary }
    public var secondary: UsageWindow? { limits.secondary }
    public var title: String { limits.limitName ?? (id == "codex" ? "Codex" : id) }
    public var planName: String? { limits.planType?.capitalized }

    public var periods: [UsagePeriod] {
        [("primary", primary), ("secondary", secondary)].compactMap { id, window in
            window.map { UsagePeriod(id: id, window: $0) }
        }
    }
}

public struct UsagePeriod: Identifiable, Equatable, Sendable {
    public let id: String
    public let window: UsageWindow
    public var isLongWindow: Bool { (window.windowDurationMins ?? 0) >= 1_440 }
    public var title: String {
        guard let minutes = window.windowDurationMins else { return id == "primary" ? "利用枠" : "追加の利用枠" }
        if minutes == 10_080 { return "週間" }
        return isLongWindow ? "長期の利用枠" : "セッション"
    }
}

public struct RateLimitResetCredit: Decodable, Equatable, Identifiable, Sendable {
    public let id: String
    public let resetType: String
    public let status: String
    public let grantedAt: Int64
    public let expiresAt: Int64?

    public var displayTitle: String { resetType == "codexRateLimits" ? "完全リセット" : "リセット" }

    public var expirationDate: Date? {
        guard let expiresAt, expiresAt > 0, expiresAt < 253_402_300_800 else { return nil }
        return Date(timeIntervalSince1970: TimeInterval(expiresAt))
    }
}

public struct RateLimitResetCreditsSummary: Decodable, Equatable, Sendable {
    public let availableCount: Int
    public let credits: [RateLimitResetCredit]?

    public var availableCredits: [RateLimitResetCredit] {
        (credits ?? []).filter { $0.status == "available" }
            .sorted {
                switch ($0.expirationDate, $1.expirationDate) {
                case let (left?, right?): left < right
                case (_?, nil): true
                case (nil, _?): false
                case (nil, nil): $0.id < $1.id
                }
            }
    }
}

public struct UsageLimits: Decodable, Equatable, Sendable {
    public let rateLimits: RateLimitBucket?
    public let rateLimitsByLimitId: [String: RateLimitBucket]?
    public let rateLimitResetCredits: RateLimitResetCreditsSummary?

    public init(rateLimits: RateLimitBucket?, rateLimitsByLimitId: [String: RateLimitBucket]?, rateLimitResetCredits: RateLimitResetCreditsSummary? = nil) {
        self.rateLimits = rateLimits
        self.rateLimitsByLimitId = rateLimitsByLimitId
        self.rateLimitResetCredits = rateLimitResetCredits
    }

    public var buckets: [UsageBucket] {
        if let rateLimitsByLimitId, !rateLimitsByLimitId.isEmpty {
            return rateLimitsByLimitId.map { UsageBucket(id: $0.key, limits: $0.value) }
                .sorted {
                    if $0.id == "codex" { return $1.id != "codex" }
                    if $1.id == "codex" { return false }
                    return $0.id < $1.id
                }
        }
        guard let rateLimits else { return [] }
        return [UsageBucket(id: rateLimits.limitId ?? "codex", limits: rateLimits)]
    }

    public static func demo(at now: Date) -> UsageLimits {
        UsageLimits(rateLimits: RateLimitBucket(
            limitId: "codex", limitName: nil,
            primary: UsageWindow(usedPercent: 28, windowDurationMins: 300, resetsAt: now.addingTimeInterval(8_640).timeIntervalSince1970),
            secondary: UsageWindow(usedPercent: 46, windowDurationMins: 10_080, resetsAt: now.addingTimeInterval(280_800).timeIntervalSince1970),
            planType: "Demo"
        ), rateLimitsByLimitId: nil)
    }
}
