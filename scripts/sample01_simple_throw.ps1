# .envからDSNを読み込み、シンプルなエラーを送信するサンプル
# read .env and send a simple error message to sentry

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-DotEnvValue {
    [CmdletBinding()] param(
        [Parameter(Mandatory)] [string]$Path,
        [Parameter(Mandatory)] [string]$Key
    )
    if (-not (Test-Path -LiteralPath $Path)) { return $null }
    $lines = Get-Content -LiteralPath $Path -Encoding UTF8 -ErrorAction Stop
    foreach ($raw in $lines) {
        $line = $raw.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith('#')) { continue }
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }
        $k = $line.Substring(0, $eq).Trim()
        if ($k -ne $Key) { continue }
        $v = $line.Substring($eq + 1).Trim()
        if (($v.Length -ge 2) -and (
                ($v.StartsWith('"') -and $v.EndsWith('"')) -or
                ($v.StartsWith("'") -and $v.EndsWith("'")))) {
            $v = $v.Substring(1, $v.Length - 2)
        }
        return $v
    }
    return $null
}

# 候補パス: リポジトリルート ..\.env -> 同階層 .\.env -> 実行CWD .\.env
$dotenvCandidates = @(
    (Join-Path $PSScriptRoot '..\\.env'),
    (Join-Path $PSScriptRoot '.env'),
    '.\\.env'
)

$dsn = $null
foreach ($p in $dotenvCandidates) {
    $dsn = Get-DotEnvValue -Path $p -Key 'SENTRY_DSN'
    if ($dsn) { break }
}

if ($dsn) {
    $env:SENTRY_DSN = $dsn
}

if (-not $env:SENTRY_DSN) {
    Write-Error 'SENTRY_DSN が見つかりません。.env で定義するか、環境変数に設定してください。'
    exit 1
}

# Sentry モジュールを読み込み
Import-Module Sentry -ErrorAction Stop

Start-Sentry {
    $_.Dsn = $env:SENTRY_DSN
    $_.SendDefaultPii = $true
}

try {
    throw 'Test error'
}
catch {
    $_ | Out-Sentry
}