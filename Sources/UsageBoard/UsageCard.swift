import SwiftUI
import UsageCore

struct UsageCard: View {
    let title: String
    let symbol: String
    let window: UsageWindow?
    let tint: Color
    let now: Date

    private var remaining: Double? { window?.remainingPercent }
    private var accent: Color { BoardTheme.tint(remaining: remaining, base: tint) }
    private var expired: Bool { window?.resetDate.map { $0 <= now } ?? false }

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: symbol).foregroundStyle(accent).font(.system(size: 13))
                Text(window?.windowDurationMins == 10_080 ? "週間" : title)
                    .font(.system(size: 13, weight: .medium))
                Spacer()
                Text(window?.durationLabel ?? "情報なし")
                    .font(.system(size: 10)).foregroundStyle(BoardTheme.muted)
            }

            HStack(alignment: .firstTextBaseline, spacing: 3) {
                Text(remaining.map { $0.formatted(.number.precision(.fractionLength(0...1))) } ?? "—")
                    .font(.system(size: 68, weight: .medium, design: .rounded))
                    .tracking(-3)
                Text("%").font(.system(size: 26, weight: .regular, design: .rounded))
                Spacer()
                Text("残り").font(.system(size: 11)).foregroundStyle(BoardTheme.muted)
            }
            .foregroundStyle(accent)
            .monospacedDigit()
            .padding(.top, 19)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(remaining.map { "残り \($0.formatted()) パーセント" } ?? "残り利用率は不明")

            GeometryReader { geometry in
                ZStack(alignment: .leading) {
                    Capsule().fill(.white.opacity(0.07))
                    if let remaining {
                        Capsule().fill(accent).frame(width: geometry.size.width * remaining / 100)
                    }
                }
            }
            .frame(height: 6)
            .padding(.top, 13)
            .accessibilityHidden(true)

            HStack {
                Text(remaining.map { "\((100 - $0).formatted(.number.precision(.fractionLength(0...1))))% 使用済み" } ?? "利用率を取得できていません")
                Spacer()
                if let remaining, remaining <= 10 { Text("残りわずか").foregroundStyle(accent) }
            }
            .font(.system(size: 10)).foregroundStyle(BoardTheme.muted)
            .padding(.top, 9)

            Rectangle().fill(BoardTheme.border).frame(height: 1)
                .padding(.vertical, 22)

            HStack(spacing: 6) {
                Image(systemName: "clock").font(.system(size: 10))
                Text("リセットまで").font(.system(size: 10))
            }
            .foregroundStyle(BoardTheme.muted)

            Text(window?.countdown(at: now) ?? "リセット時刻不明")
                .font(.system(size: 22, weight: .medium, design: .rounded))
                .monospacedDigit()
                .foregroundStyle(expired ? BoardTheme.amber : .white.opacity(0.9))
                .padding(.top, 9)

            Text(resetCaption)
                .font(.system(size: 10)).foregroundStyle(BoardTheme.muted)
                .padding(.top, 8)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(22)
        .frame(minWidth: 275, maxWidth: .infinity, alignment: .leading)
        .background(BoardTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(BoardTheme.border))
    }

    private var resetCaption: String {
        if expired { return "リセット後の取得待ち・利用率は前回の値" }
        guard let date = window?.resetDate else { return "次回の取得時に確認します" }
        return date.formatted(.dateTime.month().day().weekday(.abbreviated).hour().minute().locale(Locale(identifier: "ja_JP"))) + " にリセット"
    }
}
