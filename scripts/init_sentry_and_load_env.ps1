<#!
.SYNOPSIS
  .env ファイルの内容を現在の PowerShell セッションの環境変数に読み込みます。

.DESCRIPTION
  典型的な KEY=VALUE 形式の .env を読み込み、空行や # で始まるコメント行を無視します。
  既存の環境変数はデフォルトでは上書きしません（-Override 指定時のみ上書き）。

.PARAMETER Path
  読み込む .env のパス。デフォルトは .\.env

.PARAMETER Override
  既存の環境変数を上書きします。

.EXAMPLE
  # カレントディレクトリの .env を読み込む
  . scripts/init_sentry_and_load_env.ps1; Import-DotEnv

.EXAMPLE
  # 明示パス + 既存値を上書き
  . scripts/init_sentry_and_load_env.ps1; Import-DotEnv -Path "./.env" -Override

.NOTES
  スクリプトはプロセス環境 ($env:) にのみ反映します。永続化はされません。
#>

Set-StrictMode -Version Latest

function Import-DotEnv {
    [CmdletBinding()]
    param(
        [Parameter(Position = 0)]
        [string]$Path = ".\\.env",

        [switch]$Override
    )

    if (-not (Test-Path -LiteralPath $Path)) {
        throw "DotEnv file not found: $Path"
    }

    $content = Get-Content -LiteralPath $Path -ErrorAction Stop -Encoding UTF8
    $loaded = 0
    foreach ($rawLine in $content) {
        $line = $rawLine.Trim()
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith('#')) { continue }

        # KEY=VALUE を最初の '=' で分割
        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }

        $key = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim()

        if ([string]::IsNullOrWhiteSpace($key)) { continue }

        # 両端の単/二重クォートを剥がす（必要なら）
        if (($value.Length -ge 2) -and (
                ($value.StartsWith('"') -and $value.EndsWith('"')) -or 
                ($value.StartsWith("'") -and $value.EndsWith("'")))) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        $envPath = "Env:\$key"
        $exists = Test-Path -LiteralPath $envPath
        if ($exists -and -not $Override) { continue }

        Set-Item -LiteralPath $envPath -Value $value
        $loaded++
    }

    Write-Verbose ("Loaded {0} variables from {1}{2}" -f $loaded, $Path, $(if ($Override) { " (override)" } else { "" }))
}

<#!
.SYNOPSIS
  指定の基準ディレクトリから .env を探索して最初に見つかったパスを返します。

.PARAMETER SearchFrom
  探索開始ディレクトリ。未指定時はカレントディレクトリ (Get-Location)。

.OUTPUTS
  string (.env のフルパス) もしくは $null
#>
function Get-DotEnvPath {
    [CmdletBinding()]
    param(
        [string]$SearchFrom
    )

    if (-not $SearchFrom) {
        $SearchFrom = (Get-Location).Path
    }

    $candidates = @()
    $parent = Split-Path -Path $SearchFrom -Parent
    if ($parent) {
        $candidates += (Join-Path -Path $parent -ChildPath '.env')
    }
    $candidates += (Join-Path -Path $SearchFrom -ChildPath '.env')
    $candidates += (Join-Path -Path (Get-Location).Path -ChildPath '.env')

    foreach ($p in $candidates) {
        if (Test-Path -LiteralPath $p) { return (Resolve-Path -LiteralPath $p).Path }
    }
    return $null
}

<#!
.SYNOPSIS
  .env を読み込み、Sentry を環境変数から初期化します。

.DESCRIPTION
  - .env から環境変数を読み込む（Import-DotEnv）
  - SENTRY_DSN を検証
  - Import-Module Sentry の後、Start-Sentry で DSN と PII 設定を適用

.PARAMETER DotEnvPath
  直接 .env のパスを指定します。未指定時は Find-DotEnvPath で探索します。

.PARAMETER SearchFrom
  .env 探索の起点パス。未指定時はカレントディレクトリ。

.PARAMETER Override
  既存の環境変数を上書きします。

.PARAMETER SendDefaultPii
  Start-Sentry 時に SendDefaultPii を有効化します。

.EXAMPLE
  Initialize-SentryFromDotEnv -SearchFrom $PSScriptRoot -SendDefaultPii

#>
function Initialize-SentryFromDotEnv {
    [CmdletBinding()]
    param(
        [string]$DotEnvPath,
        [string]$SearchFrom,
        [switch]$Override,
        [switch]$SendDefaultPii
    )

    if (-not $DotEnvPath) {
        $DotEnvPath = Get-DotEnvPath -SearchFrom $SearchFrom
    }

    if (-not $DotEnvPath -or -not (Test-Path -LiteralPath $DotEnvPath)) {
        throw ".env not found. Specify -DotEnvPath or place a .env near your script."
    }

    Write-Verbose "Loading dotenv from: $DotEnvPath"
    Import-DotEnv -Path $DotEnvPath -Override:$Override.IsPresent

    if (-not $env:SENTRY_DSN) {
        throw "SENTRY_DSN is not set. Define it in .env or environment variables."
    }

    Import-Module Sentry -ErrorAction Stop

    Start-Sentry {
        if ($env:SENTRY_DSN) { $_.Dsn = $env:SENTRY_DSN }
        if ($SendDefaultPii) { $_.SendDefaultPii = $true }
    }
}
