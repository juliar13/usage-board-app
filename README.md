# Codex Usage Board

Codex の残り利用率とリセットまでの時間を表示する、通常のウインドウ型 macOS アプリの MVP です。SwiftUI / AppKit で実装し、外部ライブラリは使っていません。

## 起動

生成済みの `dist/Codex Usage Board.app` を Finder から開けます。必要ならこの `.app` をアプリケーションフォルダへコピーしてください。

```sh
./scripts/build-app.sh
open "dist/Codex Usage Board.app"
```

- 実行: macOS 14 以降、`app-server` に対応する Codex とその ChatGPT ログイン。
- ビルド: Xcode / Swift 6.0 以降。スクリプトは実行した Mac のアーキテクチャ用にビルドします。
- このビルドはローカル動作用の ad-hoc 署名です。Developer ID 署名・公証・App Store 配布は対象外です。
- Xcode では `Package.swift` を開き、`UsageBoard` スキームを実行できます。

## できること

- セッション枠・週間枠などの残りパーセント、使用率、進捗バー。
- リセットまでのカウントダウンと、Mac のタイムゾーンでのリセット日時。
- 複数の利用枠がある場合、それぞれを表示。
- アカウントから週間枠だけ返る場合は、週間枠のみを表示（存在しない短期枠は補完しません）。
- 利用可能なリセットの件数と、提供される各リセットの有効期限を表示。詳細が省略された場合は期限不明と表示します。
- 60 秒ごとの自動更新、手動更新（⌘R）、スリープ復帰後の再取得。
- 最前面への固定。ウインドウ幅を縮めるとカードを縦に表示。
- 接続設定（⌘,）で Codex のパス指定・自動更新・デモ表示を変更。
- 取得失敗時のエラー表示と前回値の保持。認証エラー時は前回値を消去。

「残り時間」は利用枠のリセットまでの時間です。作業可能な残り時間や、個々のタスクの制限時間を予測するものではありません。利用率はアカウント共通です。表示は最大約 60 秒遅れます。リセット時刻を過ぎても、サーバーから再取得するまでは残量を 100% に戻しません。

## 接続

`~/.local/bin/codex`、Homebrew のパス、Codex の標準インストール先、`PATH` を順に確認します。見つからなければ接続設定で実行ファイルを選んでください。空欄にすると自動検出に戻ります。

未ログインの場合はターミナルで次を実行し、ChatGPT アカウントでログインします。

```sh
codex login
```

独自のパスを指定した場合は、その実行ファイルで `login` を実行してください。API キーによるログインでは ChatGPT の利用枠は取得できません。GUI 起動ではシェル設定を読み込まないため、シェルだけに独自の `CODEX_HOME` を設定している環境は MVP の自動検出対象外です。

## データの取り扱い

取得のたびに `codex app-server --listen stdio://` を起動し、`initialize` → `initialized` → `account/rateLimits/read` の順に通信して終了します。応答待ちは最大 20 秒です。モデルの実行やタスクの作成、リセットの使用は行いません。

認証処理は Codex に任せ、アプリは認証トークンを直接読み取り・保存しません。実行ファイルのパスと表示設定のみを UserDefaults に保存し、利用状況はメモリ上だけで保持します。通信エラーの生データは表示・保存しません。Codex 自身は通常どおり `~/.codex` の状態を使用するため、アプリは App Sandbox を有効にしていません。

取得方法と各フィールドの意味は [公式 App Server ドキュメント](https://developers.openai.com/ja-JP/docs/app-server) と Codex の App Server スキーマに基づきます。`rateLimitsByLimitId` があれば優先し、旧形式 `rateLimits` にも対応しています。リセット情報は Codex が `rateLimitResetCredits` を返す場合に表示します。

## 開発・検証

```sh
swift test
swift run UsageBoard --demo

# 既存ログインで読み取り専用の実接続テストを明示的に実行
USAGE_BOARD_LIVE_TEST=1 swift test --filter LiveConnectionTests
```

通常のテストでは疑似 App Server を使用し、実アカウントに接続しません。使用率・日時計算、欠損データ、JSONL の分割受信、通知、接続失敗、タイムアウト、キャンセル、重複更新、古い応答の破棄を検証します。UI の確認では設定画面のデモスイッチを使用できます。`--demo` 起動は、その起動中だけデモを強制します。

## 構成

- `Sources/UsageCore`: 利用枠モデル、Codex 接続、更新状態。
- `Sources/UsageBoard`: SwiftUI 画面とウインドウ設定。
- `Tests/UsageCoreTests`: Swift Testing によるテスト。
- `scripts/build-app.sh`: `.app` の生成。
- `PLAN.md`: 実装計画。
- `MEMORY.md`: 作業記録。

履歴、通知、ログイン時起動、使用ペース予測は MVP の範囲外です。
