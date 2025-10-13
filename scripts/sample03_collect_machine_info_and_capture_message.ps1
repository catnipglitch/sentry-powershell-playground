# sample03: init スクリプトで Sentry を初期化し、マシン情報を収集して送信
# Initialize Sentry from .env via external initializer, collect machine diagnostics, and send a message

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

# 1) 初期化（sample02 と同様に、外部 ps1 を使用）
. "$PSScriptRoot\init_sentry_and_load_env.ps1"
Initialize-SentryFromDotEnv -SearchFrom $PSScriptRoot -SendDefaultPii -Verbose:$false

# 2) マシン情報の収集
function Get-MachineDiagnostics {
    [CmdletBinding()] param()

    $safe = {
        param($expr)
        try { & $expr } catch { $null }
    }

    $os = & $safe { Get-CimInstance -ClassName Win32_OperatingSystem }
    $cpu = & $safe { Get-CimInstance -ClassName Win32_Processor }
    $gpu = & $safe { Get-CimInstance -ClassName Win32_VideoController }
    $bios = & $safe { Get-CimInstance -ClassName Win32_BIOS }
    $cs = & $safe { Get-CimInstance -ClassName Win32_ComputerSystem }
    $ld = & $safe { Get-CimInstance -ClassName Win32_LogicalDisk -Filter "DriveType=3" }
    $dd = & $safe { Get-CimInstance -ClassName Win32_DiskDrive }

    $uptime = $null
    if ($os -and $os.LastBootUpTime) {
        $uptime = (Get-Date) - ([datetime]$os.LastBootUpTime)
    }

    $diag = [ordered]@{
        computer = [ordered]@{
            name   = $env:COMPUTERNAME
            domain = $env:USERDOMAIN
        }
        os       = if ($os) {
            [ordered]@{
                caption        = $os.Caption
                version        = $os.Version
                build          = $os.BuildNumber
                architecture   = $os.OSArchitecture
                installDate    = $os.InstallDate
                lastBootUpTime = $os.LastBootUpTime
                uptime         = if ($uptime) { $uptime.ToString() } else { $null }
            }
        }
        else { $null }
        cpu      = if ($cpu) {
            @($cpu | ForEach-Object {
                    [ordered]@{
                        name              = $_.Name
                        manufacturer      = $_.Manufacturer
                        cores             = $_.NumberOfCores
                        logicalProcessors = $_.NumberOfLogicalProcessors
                        maxClockMHz       = $_.MaxClockSpeed
                    }
                }) 
        }
        else { @() }
        gpu      = if ($gpu) {
            @($gpu | ForEach-Object {
                    [ordered]@{
                        name          = $_.Name
                        driverVersion = $_.DriverVersion
                        driverDate    = $_.DriverDate
                        adapterRAM    = $_.AdapterRAM
                    }
                }) 
        }
        else { @() }
        storage  = [ordered]@{
            logicalDisks = if ($ld) {
                @($ld | ForEach-Object {
                        [ordered]@{
                            deviceId   = $_.DeviceID
                            fileSystem = $_.FileSystem
                            size       = $_.Size
                            freeSpace  = $_.FreeSpace
                            volumeName = $_.VolumeName
                        }
                    }) 
            }
            else { @() }
            diskDrives   = if ($dd) {
                @($dd | ForEach-Object {
                        [ordered]@{
                            model     = $_.Model
                            size      = $_.Size
                            mediaType = $_.MediaType
                            interface = $_.InterfaceType
                        }
                    }) 
            }
            else { @() }
        }
        bios     = if ($bios) {
            [ordered]@{
                version      = $bios.SMBIOSBIOSVersion
                releaseDate  = $bios.ReleaseDate
                manufacturer = $bios.Manufacturer
            }
        }
        else { $null }
        memory   = if ($cs) {
            [ordered]@{
                totalPhysicalMemory = $cs.TotalPhysicalMemory
            }
        }
        else { $null }
        runtime  = [ordered]@{
            powershellVersion = $PSVersionTable.PSVersion.ToString()
            processArch       = $env:PROCESSOR_ARCHITECTURE
            dotnetVersion     = [System.Environment]::Version.ToString()
            culture           = [System.Globalization.CultureInfo]::CurrentCulture.Name
            uiCulture         = [System.Globalization.CultureInfo]::CurrentUICulture.Name
            timeZone          = (Get-TimeZone).Id
        }
    }

    [pscustomobject]$diag
}

$diag = Get-MachineDiagnostics

# 3) 送信前のプレビューと確認
Write-Host '=== Preview: diagnostics to be sent (JSON) ==='
$previewJson = $diag | ConvertTo-Json -Depth 6
Write-Host $previewJson

$answer = Read-Host '上記の情報をSentryに送信しますか？ [y/N]'
if ($answer -notin @('y', 'Y', 'yes', 'YES')) {
    Write-Host '送信をキャンセルしました。'
    return
}

# 4) Sentry に送信（メッセージとして送る：例外は使わない）
[Sentry.SentrySdk]::ConfigureScope({
        param($scope)
        $scope.SetTag('sample', 'sample03')
        $scope.SetTag('kind', 'diagnostics')
        $scope.SetExtra('diagnostics_json', $previewJson)
        $scope.SetExtra('computer_name', $env:COMPUTERNAME)
    })

$eventId = [Sentry.SentrySdk]::CaptureMessage('Sample03: Machine diagnostics snapshot (message)')
Write-Host "EventId: $eventId"

# 送信完了を軽く待機（任意）
[Sentry.SentrySdk]::FlushAsync([TimeSpan]::FromSeconds(3)).GetAwaiter().GetResult()

Write-Host 'Sample03: diagnostics collected and sent to Sentry as a message.'
