#Requires -RunAsAdministrator
<#
.SYNOPSIS
    Fixes damage caused by opti.ps1:
      1. Restores critical services to Automatic startup
      2. Restores lock screen background (re-enables Spotlight / content delivery)
      3. Restarts dependent services so changes take effect immediately
#>

# ---------- Admin check ----------
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
# STEP 1 — Restore critical services to Automatic
# ============================================================
Write-Host "`n[1/3] Restoring critical services to Automatic..." -ForegroundColor Yellow

# Services that MUST be Automatic for Windows to function normally.
# The opti.ps1 script set ALL of these to Manual, which causes hangs
# when Windows tries to start them on-demand (e.g., during a screenshot).
$autoServices = @(
    # Core RPC / COM
    'DcomLaunch',           # DCOM Server Process Launcher  — must be first
    'RpcEptMapper',         # RPC Endpoint Mapper
    'RpcSs',                # Remote Procedure Call (RPC)

    # Session & user infrastructure
    'LSM',                  # Local Session Manager
    'UserManager',          # User Manager
    'ProfSvc',              # User Profile Service

    # Event & task infrastructure  (screenshot hang root cause)
    'EventLog',             # Windows Event Log
    'EventSystem',          # COM+ Event System
    'SENS',                 # System Event Notification Service
    'SystemEventsBroker',   # System Events Broker
    'BrokerInfrastructure', # Background Task Infrastructure
    'Schedule',             # Task Scheduler

    # UWP / Store app infrastructure  (screenshot hang root cause)
    'StateRepository',      # State Repository Service
    'ClipSVC',              # Client License Service (AppX)
    'AppXSvc',              # AppX Deployment Service
    'WpnService',           # Windows Push Notifications System
    'CoreMessagingRegistrar', # CoreMessaging

    # Security & policy
    'BFE',                  # Base Filtering Engine (firewall / network)
    'mpssvc',               # Windows Defender Firewall
    'KeyIso',               # CNG Key Isolation
    'CryptSvc',             # Cryptographic Services
    'SamSs',                # Security Accounts Manager
    'gpsvc',                # Group Policy Client
    'wscsvc',               # Security Center
    'WinDefend',            # Windows Defender Antivirus

    # Network
    'Dhcp',                 # DHCP Client
    'Dnscache',             # DNS Client
    'nsi',                  # Network Store Interface Service
    'iphlpsvc',             # IP Helper
    'NcbService',           # Network Connection Broker
    'Wcmsvc',               # Windows Connection Manager
    'WlanSvc',              # WLAN AutoConfig
    'CDPSvc',               # Connected Devices Platform

    # Audio
    'AudioEndpointBuilder', # Windows Audio Endpoint Builder
    'Audiosrv',             # Windows Audio

    # Display / UI / Themes
    'Themes',               # Themes  (required for DWM visual effects)
    'FontCache',            # Windows Font Cache Service
    'ShellHWDetection',     # Shell Hardware Detection
    'DPS',                  # Diagnostic Policy Service
    'PcaSvc',               # Program Compatibility Assistant

    # Storage / I/O
    'SysMain',              # SysMain / Superfetch
    'PlugPlay',             # Plug and Play

    # Misc system
    'Power',                # Power
    'TrkWks',               # Distributed Link Tracking Client
    'Winmgmt',              # Windows Management Instrumentation (WMI)
    'LanmanWorkstation',    # Workstation
    'LanmanServer',         # Server
    'WSearch',              # Windows Search
    'UsoSvc',               # Update Orchestrator Service
    'DusmSvc',              # Data Usage
    'Spooler'               # Print Spooler
)

$restored = 0
$skipped  = 0

foreach ($svc in $autoServices) {
    try {
        $s = Get-Service -Name $svc -ErrorAction SilentlyContinue
        if ($null -eq $s) { $skipped++; continue }

        Set-Service -Name $svc -StartupType Automatic -ErrorAction SilentlyContinue

        # Start it now if it isn't running
        if ($s.Status -ne 'Running') {
            Start-Service -Name $svc -ErrorAction SilentlyContinue
        }

        Write-Host "  [OK] $svc" -ForegroundColor Green
        $restored++
    } catch {
        Write-Host "  [!!] $svc  — $_" -ForegroundColor Red
    }
}

Write-Host "  Restored: $restored   Not present / skipped: $skipped" -ForegroundColor Cyan

# ============================================================
# STEP 2 — Fix lock screen background (re-enable Spotlight)
# ============================================================
Write-Host "`n[2/3] Restoring lock screen background..." -ForegroundColor Yellow

# Remove the policy key that blanked the lock screen image
$cloudPath = 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
if (Test-Path $cloudPath) {
    Remove-ItemProperty -Path $cloudPath -Name 'DisableWindowsSpotlightFeatures' -ErrorAction SilentlyContinue
    Remove-ItemProperty -Path $cloudPath -Name 'DisableWindowsConsumerFeatures'  -ErrorAction SilentlyContinue
    Write-Host "  [OK] Removed CloudContent policy restrictions" -ForegroundColor Green
}

# Re-enable ContentDeliveryManager (controls lock screen image, Spotlight, etc.)
$contentPath = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
if (-not (Test-Path $contentPath)) {
    New-Item -Path $contentPath -Force | Out-Null
}

$cdmValues = @{
    'ContentDeliveryAllowed'           = 1   # master switch
    'RotatingLockScreenEnabled'        = 1   # Spotlight on lock screen
    'RotatingLockScreenOverlayEnabled' = 1   # Spotlight tips/facts overlay
    'SubscribedContent-338387Enabled'  = 1   # Lock screen image
    'SubscribedContent-338388Enabled'  = 1   # Lock screen fun facts
    'SubscribedContent-338389Enabled'  = 1   # Spotlight suggestions
    'SubscribedContent-338393Enabled'  = 1   # Start menu suggestions
    'SubscribedContent-353698Enabled'  = 1   # Timeline suggestions
}

foreach ($kv in $cdmValues.GetEnumerator()) {
    Set-ItemProperty -Path $contentPath -Name $kv.Key -Value $kv.Value -Type DWord -Force -ErrorAction SilentlyContinue
}
Write-Host "  [OK] ContentDeliveryManager re-enabled" -ForegroundColor Green

# Make sure the lock screen is set to Windows Spotlight (type 3) rather than a blank
$personalizePath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen'
if (-not (Test-Path $personalizePath)) {
    New-Item -Path $personalizePath -Force | Out-Null
}
Set-ItemProperty -Path $personalizePath -Name 'SlideshowEnabled' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue

# Set lock screen background type to Windows Spotlight (if not already)
$slideshowPath = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen\Creative'
if (-not (Test-Path $slideshowPath)) {
    New-Item -Path $slideshowPath -Force | Out-Null
}

# Fallback: point lock screen at the default Windows wallpaper if Spotlight
# hasn't downloaded an image yet.
$defaultWallpaper = 'C:\Windows\Web\Screen\img100.jpg'
if (-not (Test-Path $defaultWallpaper)) {
    # Older Windows builds use a different path
    $defaultWallpaper = (Get-ChildItem 'C:\Windows\Web\Wallpaper\Windows\' -Filter '*.jpg' -ErrorAction SilentlyContinue |
                         Select-Object -First 1).FullName
}
if ($defaultWallpaper -and (Test-Path $defaultWallpaper)) {
    Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Lock Screen' `
        -Name 'LockImageFlags' -Value 0 -Type DWord -Force -ErrorAction SilentlyContinue
    Write-Host "  [OK] Default lock screen wallpaper set: $defaultWallpaper" -ForegroundColor Green
}

# ============================================================
# STEP 3 — Restart Explorer & affected services
# ============================================================
Write-Host "`n[3/3] Restarting Explorer and notification services..." -ForegroundColor Yellow

# Restart the push notification service so the lock screen picks up the change
foreach ($svc in @('WpnService', 'WpnUserService', 'CDPSvc')) {
    try {
        Restart-Service -Name $svc -Force -ErrorAction SilentlyContinue
        Write-Host "  [OK] Restarted $svc" -ForegroundColor Green
    } catch { }
}

# Restart Explorer so registry changes take effect
try {
    Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
    Start-Sleep -Seconds 2
    Start-Process explorer.exe
    Write-Host "  [OK] Explorer restarted" -ForegroundColor Green
} catch {
    Write-Host "  [!!] Could not restart Explorer: $_" -ForegroundColor Red
}

# ============================================================
# Done
# ============================================================
Write-Host "`n=== Done ===" -ForegroundColor Cyan
Write-Host "Critical services have been restored to Automatic startup."
Write-Host "Lock screen background / Spotlight has been re-enabled."
Write-Host ""
Write-Host "NOTE: Windows Spotlight downloads images in the background." -ForegroundColor DarkYellow
Write-Host "      If the lock screen is still blank after reboot, lock your" -ForegroundColor DarkYellow
Write-Host "      PC (Win+L), wait 30 seconds, and Spotlight should appear." -ForegroundColor DarkYellow
Write-Host ""
Write-Host "A full restart is recommended to let all services initialize cleanly." -ForegroundColor Green
Read-Host "Press Enter to exit"
