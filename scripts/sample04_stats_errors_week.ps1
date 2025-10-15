# sample04: 今週（過去7日間）のエラー数をSentry APIで取得し表示
# Independent script: loads .env from repo root, no Sentry SDK initialization
# Requirements: $env:SENTRY_AUTH_TOKEN, $env:SENTRY_ORG
# Optional:     $env:SENTRY_PROJECT (slug) → プロジェクトに絞り込み
# Optional:     $env:SENTRY_REGION_URL or $env:SENTRY_BASE_URL → API ベースURL
# Note: .env supports line-head comments only (# ...). Inline comments after values are stripped.

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Import-RepoRootDotEnv {
    [CmdletBinding()]
    param(
        [switch]$Override
    )

    $repoRoot = (Resolve-Path (Join-Path $PSScriptRoot '..')).Path
    $dotenv = Join-Path $repoRoot '.env'
    $script:LastDotEnvPath = $dotenv
    if (-not (Test-Path -LiteralPath $dotenv)) {
        $script:LastLoadedCount = 0
        Write-Verbose "No .env found at: $dotenv";
        return
    }

    Write-Verbose ("Loading .env: {0}" -f $dotenv)

    # Read with BOM detection for robustness (UTF-8/UTF-16LE/UTF-16BE)
    $bytes = [System.IO.File]::ReadAllBytes($dotenv)
    $enc = $null
    if ($bytes.Length -ge 3 -and $bytes[0] -eq 0xEF -and $bytes[1] -eq 0xBB -and $bytes[2] -eq 0xBF) {
        $enc = [System.Text.Encoding]::UTF8
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFF -and $bytes[1] -eq 0xFE) {
        $enc = [System.Text.Encoding]::Unicode  # UTF-16 LE
    }
    elseif ($bytes.Length -ge 2 -and $bytes[0] -eq 0xFE -and $bytes[1] -eq 0xFF) {
        $enc = [System.Text.Encoding]::BigEndianUnicode  # UTF-16 BE
    }
    else {
        $enc = [System.Text.Encoding]::UTF8  # assume UTF-8 (no BOM)
    }

    $text = $enc.GetString($bytes)
    $lines = $text -split "(`r`n|`n|`r)"

    $loaded = 0
    foreach ($raw in $lines) {
        $line = if ($null -eq $raw) { '' } else { $raw.Trim() }
        if ([string]::IsNullOrWhiteSpace($line)) { continue }
        if ($line.StartsWith('#')) { continue }

        $eq = $line.IndexOf('=')
        if ($eq -lt 1) { continue }

        $key = $line.Substring(0, $eq).Trim()
        $value = $line.Substring($eq + 1).Trim()

        # strip inline comment (anything after first '#')
        $hash = $value.IndexOf('#')
        if ($hash -ge 0) { $value = $value.Substring(0, $hash).TrimEnd() }

        # unquote
        if (($value.Length -ge 2) -and (
                ($value.StartsWith('"') -and $value.EndsWith('"')) -or
                ($value.StartsWith("'") -and $value.EndsWith("'"))
            )) {
            $value = $value.Substring(1, $value.Length - 2)
        }

        if ([string]::IsNullOrWhiteSpace($key)) { continue }

        $envPath = "Env:\$key"
        $exists = Test-Path -LiteralPath $envPath
        if ($exists -and -not $Override) { continue }

        Set-Item -LiteralPath $envPath -Value $value
        $loaded++
    }
    $script:LastLoadedCount = $loaded
    Write-Verbose ("Loaded {0} variables from {1}{2}" -f $loaded, $dotenv, $(if ($Override) { " (override)" } else { "" }))
}

function Resolve-BaseUrl {
    if ($env:SENTRY_REGION_URL) { return $env:SENTRY_REGION_URL.TrimEnd('/') }
    if ($env:SENTRY_BASE_URL) { return $env:SENTRY_BASE_URL.TrimEnd('/') }
    if ($env:SENTRY_DSN) {
        try {
            $u = [uri]$env:SENTRY_DSN
            $h = $u.Host.ToLowerInvariant()
            if ($h -eq 'ingest.us.sentry.io' -or $h -like '*.us.sentry.io') {
                return 'https://us.sentry.io'
            }
        }
        catch { }
    }
    return 'https://sentry.io'
}

function Assert-Env {
    param([string[]]$Names)
    foreach ($n in $Names) {
        # Use .NET API for robust read (avoids ${env:$n} pitfalls)
        $value = [Environment]::GetEnvironmentVariable($n, 'Process')
        if ([string]::IsNullOrWhiteSpace($value)) {
            throw "Environment variable $n is not set or empty."
        }
    }
}

function Get-ProjectIdBySlug {
    [CmdletBinding()] param(
        [Parameter(Mandatory)] [string]$Org,
        [Parameter(Mandatory)] [string]$Slug,
        [Parameter(Mandatory)] [string]$Token
    )
    $baseUrl = Resolve-BaseUrl
    $uri = "$baseUrl/api/0/organizations/$Org/projects/"
    $headers = @{ Authorization = "Bearer $Token" }
    $resp = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET
    $match = $resp | Where-Object { $_.slug -eq $Slug }
    if (-not $match) { throw "Project not found: $Slug" }
    return $match.id
}

# 1) Load repo-root .env (override)
Import-RepoRootDotEnv -Override
$__alen = if ($env:SENTRY_AUTH_TOKEN) { $env:SENTRY_AUTH_TOKEN.Length } else { 0 }
Write-Verbose ("After .env: AUTH len={0} ORG={1}" -f $__alen, $env:SENTRY_ORG)
Write-Host ("DEBUG After .env: AUTH len={0} ORG={1} DotEnvPath={2} Loaded={3}" -f $__alen, $env:SENTRY_ORG, $script:LastDotEnvPath, $script:LastLoadedCount)
if ($__alen -eq 0) {
    Write-Host ("DEBUG: AUTH token is empty after .env load. DotEnvPath={0} Loaded={1}" -f $script:LastDotEnvPath, $script:LastLoadedCount) -ForegroundColor Yellow
    Get-ChildItem Env: |
    Where-Object { $_.Name -like 'SENTRY*' } |
    Sort-Object Name |
    ForEach-Object { Write-Host ("DEBUG ENV {0}='{1}'" -f $_.Name, $_.Value) }
}

# 2) Validate required envs for REST API
try {
    Assert-Env @('SENTRY_AUTH_TOKEN', 'SENTRY_ORG')
}
catch {
    Write-Host 'Required environment variables are missing. Please set:' -ForegroundColor Yellow
    Write-Host '$env:SENTRY_AUTH_TOKEN = "<Your API Token>"' -ForegroundColor Yellow
    Write-Host '$env:SENTRY_ORG        = "<org-slug>"' -ForegroundColor Yellow
    Write-Host '$env:SENTRY_PROJECT    = "<project-slug>"   # optional' -ForegroundColor Yellow
    throw
}

$org = $env:SENTRY_ORG
$token = $env:SENTRY_AUTH_TOKEN
$projSlug = $env:SENTRY_PROJECT
$projectParam = ''

if ($projSlug) {
    try {
        $projId = Get-ProjectIdBySlug -Org $org -Slug $projSlug -Token $token
        $projectParam = "&project=$projId"
    }
    catch {
        Write-Warning $_
    }
}

# 3) Build endpoint
$baseUrl = Resolve-BaseUrl
$endpoint = "$baseUrl/api/0/organizations/$org/events-stats/"
$qs = "field=count()&statsPeriod=7d&interval=1d&query=event.type:error$projectParam"
$uri = '{0}?{1}' -f $endpoint, $qs

$headers = @{ Authorization = "Bearer $token" }
Write-Host "Fetching: $uri"

try {
    $res = Invoke-RestMethod -Uri $uri -Headers $headers -Method GET
}
catch {
    $status = $null
    try { $status = $_.Exception.Response.StatusCode.value__ } catch { }
    if ($status -in 401, 403) {
        Write-Error "API unauthorized. Ensure the token has org:read (and project:read if filtering)."
    }
    throw
}

function Get-CountFrom {
    param($Value)
    if ($null -eq $Value) { return 0 }
    if ($Value -is [int] -or $Value -is [long]) { return [int]$Value }
    if ($Value -is [double] -or $Value -is [decimal]) { return [int][math]::Round([double]$Value) }
    if ($Value -is [string]) {
        $n = 0
        if ([int]::TryParse($Value, [ref]$n)) { return $n }
        $d = 0.0
        if ([double]::TryParse($Value, [ref]$d)) { return [int][math]::Round($d) }
    }
    # PSCustomObject/Hashtable: common keys
    try {
        if ($Value.PSObject.Properties.Name -contains 'count') { return (Get-CountFrom $Value.count) }
        if ($Value.PSObject.Properties.Name -contains 'count()') { return (Get-CountFrom ($Value.'count()')) }
        if ($Value.PSObject.Properties.Name -contains 'value') { return (Get-CountFrom $Value.value) }
    }
    catch { }
    # Array-like → first resolvable value
    if ($Value -is [System.Collections.IEnumerable]) {
        foreach ($item in $Value) {
            $c = Get-CountFrom $item
            if ($c -ne $null) { return [int]$c }
        }
    }
    return 0
}

function Convert-EventsStatsToPoints {
    param([Parameter(Mandatory = $true)] $res)
    $points = @()

    if (-not $res -or -not $res.data) { return $points }

    $d = $res.data

    # Case A: [[timestamp, valueOrObjectOrArray], ...]
    $isArrayOfPairs = ($d -is [System.Collections.IEnumerable]) -and -not ($d.PSObject.Properties.Name -contains 'series')
    if ($isArrayOfPairs) {
        foreach ($p in $d) {
            if ($p -isnot [System.Collections.IList] -or $p.Count -lt 2) { continue }
            $tsRaw = $p[0]
            $valRaw = $p[1]

            $ts = $null
            try { $ts = [DateTimeOffset]::FromUnixTimeSeconds([long]$tsRaw).DateTime } catch { }
            if (-not $ts) {
                try { $ts = [datetime]$tsRaw } catch { $ts = Get-Date 0 }
            }

            $cnt = Get-CountFrom $valRaw
            $points += [pscustomobject]@{ date = $ts; count = [int]$cnt }
        }
        return $points
    }

    # Case B: { series: { 'count()': [..] }, timestamps: [..] }
    if ($d.PSObject.Properties.Name -contains 'series') {
        $timestamps = $d.timestamps
        $series = $d.series
        $values = $null
        if ($series.PSObject.Properties.Name -contains 'count()') { $values = $series.'count()' }
        elseif ($series.PSObject.Properties.Name -contains 'count') { $values = $series.count }

        if ($timestamps -and $values) {
            for ($i = 0; $i -lt $timestamps.Count; $i++) {
                $ts = [DateTimeOffset]::FromUnixTimeSeconds([long]$timestamps[$i]).DateTime
                $cnt = Get-CountFrom $values[$i]
                $points += [pscustomobject]@{ date = $ts; count = [int]$cnt }
            }
        }
    }

    return $points
}

# Response format: various. Normalize to points.
$points = Convert-EventsStatsToPoints -res $res

if (-not $points) {
    Write-Host 'No data.' -ForegroundColor Yellow
    return
}

$total = ($points | Measure-Object -Property count -Sum).Sum
Write-Host "`nTotal errors in the last 7 days: $total"
Write-Host 'Daily breakdown:'
$points | ForEach-Object {
    $bar = '#' * ([math]::Clamp($_.count, 0, 50))
    '{0:yyyy-MM-dd}  {1,6}  {2}' -f $_.date, $_.count, $bar
}
