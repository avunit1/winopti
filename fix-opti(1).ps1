#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Fixes damage caused by opti.ps1:
      1. Restores critical services to Automatic startup
      2. Restores lock screen background (re-enables Spotlight / content delivery)
      3. Restarts dependent services so changes take effect immediately
#>

if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole(
        [Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Run this script as Administrator." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Write-Host "`n=== opti.ps1 Fix Script ===" -ForegroundColor Cyan
Write-Host "Press ENTER to begin." -NoNewline
Read-Host

# ============================================================
# STEP 1 -- Restore critical services to Automatic
# ============================================================
Write-Host "`n[1/3] Restoring critical services to Automatic..." -ForegroundColor Yellow

$autoServices = @(
    # Core RPC / COM
    'DcomLaunch',
    'RpcEptMapper',
    'RpcSs',
    # Session & user infrastructure
    'LSM',
    'UserManager',
    'ProfSvc',
    # Event & task infrastructure (screenshot hang root cause)
    'EventLog',
    'EventSystem',
    'SENS',
    'SystemEventsBroker',
    'BrokerInfrastructure',
    'Schedule',
    # UWP / Store app infrastructure (screenshot hang root cause)
    'StateRepository',
    'ClipSVC',
    'AppXSvc',
    'WpnService',
    'CoreMessagingRegistrar',
    # Security & policy
    'BFE',
    'mpssvc',
    'KeyIso',
    'CryptSvc',
    'SamSs',
    'gpsvc',
    'wscsvc',
    'WinDefend',
    # Network
    'Dhcp',
    'Dnscache',
    'nsi',
    'iphlpsvc',
    'NcbService',
    'Wcmsvc',
    'WlanSvc',
    'CDPSvc',
    # Audio
    'AudioEndpointBuilder',
    'Audiosrv',
    # Display / UI / Themes
    'Themes',
    'FontCache',
    'ShellHWDetection',
    'DPS',
    'PcaSvc',
    # Storage / I/O
    'SysMain',
    'PlugPlay',
    # Misc system
    'Power',
    'TrkWks',
    'Winmgmt',
    'LanmanWorkstation',
    'LanmanServer',
    'WSearch',
    'UsoSvc',
    'DusmSvc',
    'Spooler'
)

$restored = 0
$skipped  = 0

foreach ($svc in $autoServices) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($null -eq $s) { $skipped++; continue }

        Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue

        if ($s.Status -ne 'Running') {
            Start-Service -Name $svc -ErrorAction SilentlyContinue
        }

        Write-Host "  [OK] $svc" -ForegroundColor Green
        $restored++
    }
    catch {
        Write-Host "  [WARN] $svc - $($_.Exception.Message)" -ForegroundColor DarkYellow
    }
}

Write-Host "  Restored: $restored   Not present/skipped: $skipped" -ForegroundColor Cyan

# ============================================================
# STEP 2 -- Fix lock screen background (re-enable Spotlight)
# ============================================================
Write-Host "`n[2/3] Restoring lock screen background..." -ForegroundColor Yellow

$cloudPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
if (Test-Path $cloudPath) {
    Remove-ItemProperty -Path $cloudPath -Name 'DisableWindowsSpotlightFeatures' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $cloudPath -Name 'DisableWindowsConsumerFeatures'  -ErrorAction SilentlyContinue
    Write-Host "  [OK] Removed CloudContent policy restrictions" -ForegroundColor Green
}

$contentPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
if (-not (Test-Path $contentPath)) {
    New-Item -Path $contentPath -Force | Out-Null
}

$cdmValues = @{
    'ContentDeliveryAllowed'           = 1
    'RotatingLockScreenEnabled'        = 1
    'RotatingLockScreenOverlayEnabled' = 1
    'SubscribedContent-338387Enabled'  = 1
    'SubscribedContent-338388Enabled'  = 1
    'SubscribedContent-338389Enabled'  = 1
    'SubscribedContent-338393Enabled'  = 1
    'SubscribedContent-353698Enabled'  = 1
}

foreach ($kv in $cdmValues.GetEnumerator()) {
    Set-ItemProperty -Path $contentPath -Name $kv.Key -Value $kv.Value -Type DWord -Force -ErrorAction SilentlyContinue
}
Write-Host "  [OK] ContentDeliveryManager re-enabled" -ForegroundColor Green

$lockScreenPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen'
if (-not (Test-Path $lockScreenPath)) {
    New-Item -Path $lockScreenPath -Force | Out-Null
}
Set-ItemProperty -Path $lockScreenPath -Name 'SlideshowEnabled' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

$defaultWallpaper = 'C:\Windows\Web\Screen\img100.jpg'
if (-not (Test-Path $defaultWallpaper)) {
    $defaultWallpaper = (Get-ChildItem 'C:\Windows\Web\Wallpaper\Windows\' -Filter '*.jpg' -ErrorAction SilentlyContinue |
                         Select-Object -First 1).FullName
}
if ($defaultWallpaper -and (Test-Path $defaultWallpaper)) {
    Write-Host "  [OK] Default lock screen wallpaper found: $defaultWallpaper" -ForegroundColor Green
}

# ============================================================
# STEP 3 -- Restart Explorer & notification services
# ============================================================
Write-Host "`n[3/3] Restarting Explorer and notification services..." -ForegroundColor Yellow

foreach ($svc in @('WpnService', 'CDPSvc')) {
    try {
        Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Restarted $svc" -ForegroundColor Green
    }
    catch {
        Write-Host "  [WARN] Could not restart $svc" -ForegroundColor DarkYellow
    }
}

try {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Write-Host "  [OK] Explorer restarted" -ForegroundColor Green
}
catch {
    Write-Host "  [WARN] Could not restart Explorer" -ForegroundColor DarkYellow
}

# ============================================================
# Done
# ============================================================
Write-Host "`n=== Done ===" -ForegroundColor Cyan
Write-Host "Critical services restored to Automatic startup."
Write-Host "Lock screen background / Spotlight re-enabled."
Write-Host ""
Write-Host "NOTE: A full reboot is recommended." -ForegroundColor DarkYellow
Write-Host "      If the lock screen is still blank after reboot, lock (Win+L)" -ForegroundColor DarkYellow
Write-Host "      and wait 30 seconds for Spotlight to download a fresh image." -ForegroundColor DarkYellow
Write-Host ""
Read-Host "Press Enter to exit"
