import AppKit
import SwiftUI
import UsageCore

struct ConnectionSettingsView: View {
    @Environment(\.dismiss) private var dismiss
    @Binding var customPath: String
    @Binding var autoRefresh: Bool
    @Binding var demoMode: Bool
    @State private var draftPath = ""
    @State private var draftAutoRefresh = true
    @State private var draftDemoMode = false

    var body: some View {
        VStack(alignment: .leading, spacing: 22) {
            HStack {
                Text("接続設定").font(.system(size: 21, weight: .semibold))
                Spacer()
                BoardIconButton(title: "閉じる", symbol: "xmark") { dismiss() }
            }
            VStack(alignment: .leading, spacing: 9) {
                Text("Codex の実行ファイル").font(.system(size: 12, weight: .semibold))
                HStack {
                    TextField("空欄で自動検出", text: $draftPath)
                        .textFieldStyle(.roundedBorder)
                        .accessibilityIdentifier("codexPath")
                    Button("選択…") { chooseExecutable() }
                }
                Text("検出先: \(CodexLocator.locate(customPath: draftPath) ?? "見つかりません")")
                    .font(.system(size: 10, design: .monospaced))
                    .foregroundStyle(BoardTheme.muted)
                    .textSelection(.enabled)
                    .lineLimit(3)
                Text("既存の Codex の ChatGPT ログインを利用します。未ログインの場合は、ターミナルで codex login を実行してください。")
                    .font(.system(size: 11)).foregroundStyle(BoardTheme.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Divider()
            Toggle("60秒ごとに利用状況を更新する", isOn: $draftAutoRefresh)
            Toggle("デモデータで表示する", isOn: $draftDemoMode)
            Text("利用状況の取得だけを行います。API キーや認証トークンの入力は不要です。")
                .font(.system(size: 11)).foregroundStyle(BoardTheme.muted)
                .fixedSize(horizontal: false, vertical: true)
            HStack {
                Button("自動検出に戻す") { draftPath = "" }
                Spacer()
                Button("キャンセル") { dismiss() }.keyboardShortcut(.cancelAction)
                Button("保存して接続") {
                    customPath = draftPath.trimmingCharacters(in: .whitespacesAndNewlines)
                    autoRefresh = draftAutoRefresh
                    demoMode = draftDemoMode
                    dismiss()
                }
                .buttonStyle(.borderedProminent)
                .tint(BoardTheme.green)
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(28)
        .frame(width: 490)
        .background(BoardTheme.background)
        .preferredColorScheme(.dark)
        .onAppear {
            draftPath = customPath
            draftAutoRefresh = autoRefresh
            draftDemoMode = demoMode
        }
    }

    private func chooseExecutable() {
        let panel = NSOpenPanel()
        panel.title = "Codex の実行ファイルを選択"
        panel.canChooseDirectories = false
        panel.canChooseFiles = true
        panel.allowsMultipleSelection = false
        panel.showsHiddenFiles = true
        if panel.runModal() == .OK, let url = panel.url { draftPath = url.path }
    }
}
