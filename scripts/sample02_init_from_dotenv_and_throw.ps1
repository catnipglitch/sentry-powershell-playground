# sample02: 初期化と .env 読み込みを外部 ps1 に委譲し、本体は最小コードでエラー送信
# Initialize Sentry from .env via external initializer, then send a simple error

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# ドットソースで初期化ヘルパーを読み込む（呼び出し元セッションに反映）
. "$PSScriptRoot\init_sentry_and_load_env.ps1"

# .env 探索は $PSScriptRoot を基点に（リポジトリ直下の .env も拾えるように）
Initialize-SentryFromDotEnv -SearchFrom $PSScriptRoot -SendDefaultPii -Verbose:$false

try {
    throw 'Sample02: Test error'
}
catch {
    $_ | Out-Sentry
}
