import AppKit
import SwiftUI
import UsageCore

struct DashboardView: View {
    @State private var store = UsageStore()
    @AppStorage("codexExecutablePath") private var customPath = ""
    @AppStorage("autoRefresh") private var autoRefresh = true
    @AppStorage("keepOnTop") private var keepOnTop = false
    @AppStorage("demoMode") private var savedDemoMode = false
    @State private var showingSettings = false
    @State private var demoProvider = DemoUsageProvider()
    @State private var manualTask: Task<Void, Never>?

    private var isDemo: Bool { savedDemoMode || ProcessInfo.processInfo.arguments.contains("--demo") }
    private var connectionID: String { "\(customPath)|\(isDemo)" }

    var body: some View {
        VStack(spacing: 0) {
            header
            ScrollView {
                TimelineView(.periodic(from: .now, by: 1)) { context in
                    dashboard(at: context.date)
                }
                .padding(.horizontal, 28)
                .padding(.top, 26)
                .padding(.bottom, 24)
            }
            footer
        }
        .background(BoardTheme.background)
        .foregroundStyle(.white.opacity(0.94))
        .preferredColorScheme(.dark)
        .frame(minWidth: 520, minHeight: 520)
        .background(WindowConfiguration(keepOnTop: keepOnTop))
        .sheet(isPresented: $showingSettings) {
            ConnectionSettingsView(customPath: $customPath, autoRefresh: $autoRefresh, demoMode: $savedDemoMode)
        }
        .task(id: connectionID) {
            manualTask?.cancel()
            store.reset()
            demoProvider = DemoUsageProvider()
            await refresh()
            while !Task.isCancelled {
                do { try await Task.sleep(for: .seconds(60)) } catch { break }
                if autoRefresh { await refresh() }
            }
        }
        .onReceive(NSWorkspace.shared.notificationCenter.publisher(for: NSWorkspace.didWakeNotification)) { _ in
            if autoRefresh { requestRefresh() }
        }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            if autoRefresh, let updated = store.lastUpdated, Date().timeIntervalSince(updated) > 60 {
                requestRefresh()
            }
        }
        .onDisappear { manualTask?.cancel() }
    }

    private var header: some View {
        HStack(spacing: 13) {
            Image(systemName: "chart.bar.xaxis")
                .font(.system(size: 23, weight: .semibold))
                .foregroundStyle(BoardTheme.green)
                .frame(width: 44, height: 44)
                .background(BoardTheme.green.opacity(0.1), in: RoundedRectangle(cornerRadius: 13))
            VStack(alignment: .leading, spacing: 3) {
                Text("Usage Board").font(.system(size: 21, weight: .semibold, design: .rounded))
                Text("CODEX  /  USAGE MONITOR")
                    .font(.system(size: 9, weight: .medium, design: .monospaced))
                    .tracking(1.5)
                    .foregroundStyle(BoardTheme.muted)
            }
            Spacer()
            BoardIconButton(title: "利用状況を更新（⌘R）", symbol: "arrow.clockwise") { requestRefresh() }
                .disabled(store.isRefreshing)
                .keyboardShortcut("r", modifiers: .command)
            BoardIconButton(title: "接続設定", symbol: "gearshape") { showingSettings = true }
                .keyboardShortcut(",", modifiers: .command)
        }
        .padding(.horizontal, 28)
        .padding(.top, 32)
        .padding(.bottom, 22)
        .overlay(alignment: .bottom) { Rectangle().fill(BoardTheme.border).frame(height: 1) }
    }

    private func dashboard(at now: Date) -> some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack(alignment: .center) {
                VStack(alignment: .leading, spacing: 6) {
                    Text("利用できる残りの枠").font(.system(size: 24, weight: .semibold))
                    Text("アカウント全体の利用状況を、ひと目で。")
                        .font(.system(size: 12)).foregroundStyle(BoardTheme.muted)
                }
                Spacer(minLength: 12)
                statusBadge(at: now)
            }

            if isDemo {
                notice("デモ表示", message: "サンプルデータです。接続設定から実データに切り替えられます。", symbol: "play.rectangle", tint: BoardTheme.blue)
            }
            if let error = store.errorMessage {
                notice("更新できませんでした", message: error, symbol: "exclamationmark.triangle", tint: BoardTheme.amber)
            } else if let updated = store.lastUpdated, now.timeIntervalSince(updated) > 90, !isDemo {
                notice("前回取得した情報を表示中", message: "最新の利用状況は更新ボタンで確認してください。", symbol: "clock", tint: BoardTheme.amber)
            }

            if let snapshot = store.snapshot, !snapshot.buckets.isEmpty {
                ForEach(snapshot.buckets) { bucket in
                    VStack(alignment: .leading, spacing: 13) {
                        HStack(spacing: 8) {
                            Text(bucket.title).font(.system(size: 13, weight: .semibold))
                            if let plan = bucket.planName {
                                Text(plan).font(.system(size: 10, weight: .medium))
                                    .foregroundStyle(BoardTheme.muted)
                                    .padding(.horizontal, 7).padding(.vertical, 3)
                                    .background(.white.opacity(0.05), in: Capsule())
                            }
                            Spacer()
                            Text("残り / 上限 100%")
                                .font(.system(size: 10)).foregroundStyle(BoardTheme.muted)
                        }
                        if bucket.periods.isEmpty {
                            notice("利用枠の詳細がありません", message: "この枠の利用率やリセット時刻は現在提供されていません。", symbol: "info.circle", tint: BoardTheme.muted)
                        } else {
                            ViewThatFits(in: .horizontal) {
                                HStack(alignment: .top, spacing: 16) { cards(for: bucket, at: now) }
                                VStack(spacing: 16) { cards(for: bucket, at: now) }
                            }
                        }
                    }
                }
                HStack(alignment: .top, spacing: 8) {
                    Image(systemName: "info.circle").padding(.top, 1)
                    Text("残り時間は、利用枠がリセットされるまでの時間です。\n作業を続けられる時間の予測ではありません。")
                        .lineSpacing(4)
                }
                .font(.system(size: 11))
                .foregroundStyle(BoardTheme.muted)
            } else if store.snapshot?.rateLimitResetCredits == nil {
                emptyState
            }

            if let resetCredits = store.snapshot?.rateLimitResetCredits {
                resetCreditsSection(resetCredits)
            }
        }
    }

    private func resetCreditsSection(_ summary: RateLimitResetCreditsSummary) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .firstTextBaseline) {
                Text("利用上限のリセット")
                    .font(.system(size: 16, weight: .semibold))
                Spacer()
                Text("利用可能 \(summary.availableCount)")
                    .font(.system(size: 12, weight: .medium))
                    .foregroundStyle(BoardTheme.green)
            }

            if summary.availableCount == 0 {
                Text("利用可能なリセットはありません")
                    .font(.system(size: 12)).foregroundStyle(BoardTheme.muted)
            } else if summary.availableCredits.isEmpty {
                Text("有効期限の詳細は取得できません")
                    .font(.system(size: 12)).foregroundStyle(BoardTheme.muted)
            } else {
                ForEach(summary.availableCredits) { credit in
                    HStack(spacing: 10) {
                        Image(systemName: "arrow.counterclockwise.circle")
                            .foregroundStyle(BoardTheme.green)
                        Text(credit.displayTitle)
                        Spacer()
                        Text(credit.expirationDate.map {
                            "期限 \($0.formatted(.dateTime.year().month().day().locale(Locale(identifier: "ja_JP"))))"
                        } ?? "期限なし")
                            .foregroundStyle(BoardTheme.muted)
                    }
                    .font(.system(size: 12))
                }
                if summary.availableCount > summary.availableCredits.count {
                    Text("ほか \(summary.availableCount - summary.availableCredits.count) 件の期限は取得できません")
                        .font(.system(size: 11)).foregroundStyle(BoardTheme.muted)
                }
            }
        }
        .padding(18)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(BoardTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(BoardTheme.border))
    }

    @ViewBuilder
    private func cards(for bucket: UsageBucket, at now: Date) -> some View {
        ForEach(bucket.periods) { period in
            UsageCard(title: period.title, symbol: period.isLongWindow ? "calendar" : "bolt", window: period.window,
                      tint: period.isLongWindow ? BoardTheme.blue : BoardTheme.green, now: now)
        }
    }

    private func statusBadge(at now: Date) -> some View {
        let stale = store.lastUpdated.map { now.timeIntervalSince($0) > 90 } ?? false
        let label = isDemo ? "デモ" : store.isRefreshing ? "更新中" : store.errorMessage != nil ? "接続エラー" : stale ? "前回の情報" : store.lastUpdated == nil ? "未接続" : "同期済み"
        let tint = isDemo ? BoardTheme.blue : store.errorMessage != nil || stale ? BoardTheme.amber : BoardTheme.green
        return HStack(spacing: 6) {
            Circle().fill(tint).frame(width: 5, height: 5)
            Text(label).font(.system(size: 10, weight: .medium))
        }
        .foregroundStyle(tint)
        .padding(.horizontal, 10).padding(.vertical, 7)
        .background(tint.opacity(0.08), in: Capsule())
    }

    private func notice(_ title: String, message: String, symbol: String, tint: Color) -> some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: symbol).foregroundStyle(tint)
            VStack(alignment: .leading, spacing: 5) {
                Text(title).font(.system(size: 12, weight: .semibold))
                Text(message).font(.system(size: 11)).foregroundStyle(BoardTheme.muted).fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(14)
        .background(tint.opacity(0.06), in: RoundedRectangle(cornerRadius: 12))
        .overlay(RoundedRectangle(cornerRadius: 12).stroke(tint.opacity(0.15)))
    }

    private var emptyState: some View {
        VStack(spacing: 16) {
            if store.isRefreshing {
                ProgressView().controlSize(.small)
                Text("Codex の利用状況を取得しています")
            } else {
                Image(systemName: store.errorMessage == nil ? "chart.bar.doc.horizontal" : "bolt.horizontal.circle")
                    .font(.system(size: 32)).foregroundStyle(BoardTheme.muted)
                Text(store.snapshot == nil ? "Codex と接続しましょう" : "利用枠の情報がありません")
                    .font(.system(size: 16, weight: .semibold))
                Text("Codex の ChatGPT ログインを使って、利用状況を表示します。")
                    .font(.system(size: 12)).foregroundStyle(BoardTheme.muted)
                HStack {
                    Button("接続設定を開く") { showingSettings = true }
                    Button("再試行") { requestRefresh() }
                }
                .buttonStyle(.bordered)
            }
        }
        .frame(maxWidth: .infinity, minHeight: 280)
        .background(BoardTheme.surface, in: RoundedRectangle(cornerRadius: 18))
        .overlay(RoundedRectangle(cornerRadius: 18).stroke(BoardTheme.border))
    }

    private var footer: some View {
        HStack(spacing: 8) {
            Image(systemName: "arrow.triangle.2.circlepath").font(.system(size: 10))
            VStack(alignment: .leading, spacing: 4) {
                Text(autoRefresh ? "60秒ごとに自動更新" : "自動更新は停止中")
                if let date = store.lastUpdated {
                    Text("最終取得 \(date.formatted(.dateTime.hour().minute().second()))")
                        .font(.system(size: 9, design: .monospaced))
                }
            }
            Spacer()
            Toggle(isOn: $keepOnTop) {
                Label("最前面に固定", systemImage: keepOnTop ? "pin.fill" : "pin")
            }
            .toggleStyle(.button)
            .buttonStyle(.plain)
            .foregroundStyle(keepOnTop ? BoardTheme.green : BoardTheme.muted)
            .help("ほかのウインドウより前に表示します")
            .accessibilityIdentifier("keepOnTop")
        }
        .font(.system(size: 10))
        .foregroundStyle(BoardTheme.muted)
        .padding(.horizontal, 28).padding(.vertical, 17)
        .overlay(alignment: .top) { Rectangle().fill(BoardTheme.border).frame(height: 1) }
    }

    private func requestRefresh() {
        guard !store.isRefreshing else { return }
        manualTask = Task { await refresh() }
    }

    private func refresh() async {
        if isDemo {
            await store.refresh(using: demoProvider)
        } else {
            await store.refresh(using: CodexUsageClient(executablePath: CodexLocator.locate(customPath: customPath) ?? ""))
        }
    }
}
