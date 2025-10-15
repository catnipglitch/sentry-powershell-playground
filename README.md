# sentry-powershell-playground

PowerShellで`.env`を読み込んでSentryなどのクレデンシャルをセッションに設定するための最小セットです。

## サンプル一覧（ファイル名と概要）

| ファイル名                                                      | 概要                                                                                                     |
| --------------------------------------------------------------- | -------------------------------------------------------------------------------------------------------- |
| `scripts/sample01_simple_throw.ps1`                             | 1ファイル完結。`.env`から`SENTRY_DSN`を取得し、Sentry初期化→テスト例外を送信。                           |
| `scripts/sample02_init_from_dotenv_and_throw.ps1`               | 外部init（`init_sentry_and_load_env.ps1`）で`.env`読み込みとSentry初期化し、本体は最小コードで例外送信。 |
| `scripts/sample03_collect_machine_info_and_capture_message.ps1` | マシン情報を収集してメッセージとして送信する（`CaptureMessage`）。                                       |
| `scripts/sample04_stats_errors_week.ps1`                        | 今週（過去7日間）のエラー件数をSentry APIで取得し、日別集計と合計を表示。                                |

---
## 使い方

### 前提（インストール/セットアップ）

Sentry PowerShell SDKの公式ドキュメントを参照し、インストールと初期設定を済ませてください。

- 公式ドキュメント: https://docs.sentry.io/platforms/powershell/
- リポジトリ: https://github.com/getsentry/sentry-powershell

### .envの準備

```
SENTRY_DSN=your_dsn_here
ANOTHER_KEY="quoted value"
# コメント行
```

### 読み込み（PowerShellセッション）

```powershell
. scripts/init_sentry_and_load_env.ps1
Import-DotEnv                   # カレントの .env を読む
# Import-DotEnv -Path .\\.env   # 明示パスを指定する場合
# Import-DotEnv -Override       # 既存の環境変数も上書きする場合
```

### 反映確認

```powershell
$env:SENTRY_DSN
```

### 直接設定（ワンライナー）

`.env`を使わずにその場で設定したい場合:

```powershell
$env:SENTRY_DSN = 'p'
```

### 永続化（ユーザー環境変数）

```powershell
[Environment]::SetEnvironmentVariable('SENTRY_DSN','p','User')
```

## 注意

- スコープは現在のPowerShellプロセスのみです。永続化が必要なら`$PROFILE`に以下の2行を追記してください。

```powershell
. $PSScriptRoot/scripts/init_sentry_and_load_env.ps1
Import-DotEnv
```

- `.env`の空行・`#`から始まる行は無視されます。
- 値が`"..."`または`'...'`で囲まれている場合は外側の1組だけを剥がします。

## サンプル解説


### `scripts/sample01_simple_throw.ps1` — スクリプトの解説

1ファイルで`.env`から`SENTRY_DSN`を読み込み（親/同階層/CWDの順で探索）、Sentryを初期化したのちテスト用の例外を送信します。外部の初期化スクリプトに依存しない最小構成です。

実行:

```powershell
pwsh -File .\scripts\sample01_simple_throw.ps1
```

補足:
- `.env`未検出または`SENTRY_DSN`未設定時はエラー終了します。
- デフォルトで`SendDefaultPii`を有効化しています。

---

### `scripts/sample02_init_from_dotenv_and_throw.ps1` — スクリプトの解説

外部の初期化スクリプト（`scripts/init_sentry_and_load_env.ps1`）をドットソースし、`.env`から読み込んだ`SENTRY_DSN`でSentryを初期化してから、テスト用の例外を送信します。量産時の雛形向けに、本体は最小コードです。

実行:

```powershell
pwsh -File .\scripts\sample02_init_from_dotenv_and_throw.ps1
```

---

### `scripts/sample03_collect_machine_info_and_capture_message.ps1` — スクリプトの解説

CPU/GPU/OS/ストレージ/BIOS/メモリ/ランタイム/コンピューター名などを収集し、まずJSONでプレビュー表示します。確認プロンプトで`y/yes`と答えた場合のみ、例外ではなくメッセージとしてSentryに送信します（`SentrySdk.CaptureMessage`）。

実行:

```powershell
pwsh -File .\scripts\sample03_collect_machine_info_and_capture_message.ps1
```

補足:
- 送信内容はExtras(`diagnostics_json`,`computer_name`)とTags(`sample=sample03`,`kind=diagnostics`)として付与されます。
- 送信完了後はイベントIDが表示されます。SentryのUIでイベントID検索すると確認しやすいです。

---

### `scripts/sample04_stats_errors_week.ps1` — スクリプトの解説

SentryのREST APIを使って「過去7日間のエラー数」を取得し、日別内訳と合計を表示します。`SENTRY_AUTH_TOKEN` と `SENTRY_ORG` が必要で、`SENTRY_PROJECT` を設定すると特定プロジェクトに絞り込めます。

実行:

```powershell
pwsh -File .\scripts\sample04_stats_errors_week.ps1
```

必要な環境変数（参照系のみ必要）:

```powershell
$env:SENTRY_AUTH_TOKEN = '<Your API Token>'
$env:SENTRY_ORG        = '<org-slug>'
$env:SENTRY_PROJECT    = '<project-slug>'  # 任意
```

## 初期化スクリプト（関数）

`scripts/init_sentry_and_load_env.ps1` は以下の関数を提供します。

- `Import-DotEnv`：`.env`を現在セッションの環境変数へ取り込み（`-Override`対応）
- `Get-DotEnvPath`：指定パス起点で`.env`を探索
- `Initialize-SentryFromDotEnv`：`.env`読み込み→`SENTRY_DSN`検証→Sentry初期化（`-SendDefaultPii`対応）

## ライセンス

MIT
