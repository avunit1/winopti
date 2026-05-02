<#
.SYNOPSIS
    Windows Optimizer - run as Administrator, no forced restart.
.DESCRIPTION
    Must be elevated. Press ENTER to start. Each task prints its name and counter.
    Explorer is automatically restarted after all non-reboot tasks.
#>

# ---------- Admin check ----------
if (-NOT ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole] "Administrator")) {
    Write-Host "Run this app as admin." -ForegroundColor Red
    Read-Host "Press Enter to exit"
    exit 1
}

Set-Location (Split-Path -Parent $MyInvocation.MyCommand.Path)

# ---------- Task definitions ----------
$tasks = @(
    @{
        Name = "Creating restore point"
        Script = {
            Checkpoint-Computer -Description 'optimizer restore point' -RestorePointType MODIFY_SETTINGS -ErrorAction SilentlyContinue
        }
    },
    @{
        Name = "Installing Windows updates"
        Script = {
            Set-ExecutionPolicy -Scope Process -ExecutionPolicy Bypass -Force -ErrorAction SilentlyContinue
            Install-PackageProvider -Name NuGet -Force -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            Install-Module -Name PSWindowsUpdate -Force -AllowClobber -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            Import-Module PSWindowsUpdate -WarningAction SilentlyContinue -ErrorAction SilentlyContinue | Out-Null
            Get-WindowsUpdate -MicrosoftUpdate -AcceptAll -Install -IgnoreReboot -ErrorAction SilentlyContinue | Out-Null
        }
    },
    @{
        Name = "Enabling Hyper-V"
        Script = {
            & {
                $ErrorActionPreference = 'SilentlyContinue'
                $editionId = (Get-ItemProperty 'HKLM:\SOFTWARE\Microsoft\Windows NT\CurrentVersion' -ErrorAction SilentlyContinue).EditionID
                if ($editionId -match 'Pro|Enterprise|Education|Server|Ultimate') {
                    Enable-WindowsOptionalFeature -Online -FeatureName Microsoft-Hyper-V -All -NoRestart -WarningAction SilentlyContinue -ErrorAction SilentlyContinue *> $null
                }
            }
        }
    },
    @{
        Name = "Installing redistributables"
        Script = {
            Get-ChildItem ".\red\*" -Include *.exe, *.msi -ErrorAction SilentlyContinue | ForEach-Object {
                try {
                    $n = $_.BaseName.ToLower()
                    if ($_.Extension -ieq '.msi') {
                        Start-Process 'msiexec.exe' -ArgumentList "/i `"$($_.FullName)`" /qn /norestart" -Wait -ErrorAction SilentlyContinue
                    } elseif ($n -match 'dxwebsetup') {
                        # Web installer stub — extract first, then run dxsetup.exe /silent
                        $tmp = Join-Path $env:TEMP 'dxwebsetup_ext'
                        New-Item -ItemType Directory -Path $tmp -Force | Out-Null
                        Start-Process $_.FullName -ArgumentList "/T:`"$tmp`" /C" -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                        $dxsetup = Join-Path $tmp 'dxsetup.exe'
                        if (Test-Path $dxsetup) {
                            Start-Process $dxsetup -ArgumentList '/silent' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                        }
                        Remove-Item $tmp -Recurse -Force -ErrorAction SilentlyContinue
                    } elseif ($n -match 'dxsetup|directx') {
                        Start-Process $_.FullName -ArgumentList '/silent' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                    } elseif ($n -match 'physx') {
                        # NSIS installer — /S must be used with WindowStyle Hidden, not -NoNewWindow
                        Start-Process $_.FullName -ArgumentList '/s' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                    } elseif ($n -match 'oalinst') {
                        Start-Process $_.FullName -ArgumentList '/S' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                    } elseif ($n -match 'netfx') {
                        # .NET Framework (3.5, 4.8, etc.)
                        Start-Process $_.FullName -ArgumentList '/q /norestart' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                    } elseif ($n -match 'netsdk') {
                        # .NET SDK
                        Start-Process $_.FullName -ArgumentList '/install /quiet /norestart' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                    } elseif ($n -match '^net\d') {
                        # .NET Runtime (net7.0, net8.0, net9.0, net10.0, net11.0)
                        Start-Process $_.FullName -ArgumentList '/install /quiet /norestart' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                    } elseif ($n -match 'vcredist.*200[0-8]|vc.*200[0-8]') {
                        # VC++ 2005–2008 use old InstallShield syntax
                        Start-Process $_.FullName -ArgumentList '/q:a /r:n' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                    } elseif ($n -match 'vcredist|vc_redist') {
                        Start-Process $_.FullName -ArgumentList '/install /quiet /norestart' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                    } else {
                        Start-Process $_.FullName -ArgumentList '/quiet /norestart' -Wait -WindowStyle Hidden -ErrorAction SilentlyContinue
                    }
                } catch { }
            }
        }
    },
    @{
        Name = "Disabling activity history"
        Script = {
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'EnableActivityFeed' -Value 0 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'PublishUserActivities' -Value 0 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\System' -Name 'UploadUserActivities' -Value 0 -Force -ErrorAction SilentlyContinue
            Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection' -Name 'AllowTelemetry' -Value 0 -Force -ErrorAction SilentlyContinue
            Stop-Service 'DiagTrack' -Force -ErrorAction SilentlyContinue
            Set-Service 'DiagTrack' -StartupType Disabled -ErrorAction SilentlyContinue
        }
    },
    @{
        Name = "Disabling consumer features"
        Script = {
            & {
                $ErrorActionPreference='SilentlyContinue'
                $cloudPath='HKLM:\SOFTWARE\Policies\Microsoft\Windows\CloudContent'
                $contentPath='HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\ContentDeliveryManager'
                New-Item -Path $cloudPath -Force | Out-Null
                Set-ItemProperty -Path $cloudPath -Name 'DisableWindowsConsumerFeatures' -Value 1 -Type DWord
                Set-ItemProperty -Path $cloudPath -Name 'DisableWindowsSpotlightFeatures' -Value 1 -Type DWord
                New-Item -Path $contentPath -Force | Out-Null
                Set-ItemProperty -Path $contentPath -Name 'SilentInstalledAppsEnabled' -Value 0 -Type DWord
                Set-ItemProperty -Path $contentPath -Name 'ContentDeliveryAllowed' -Value 0 -Type DWord
                Set-ItemProperty -Path $contentPath -Name 'OemPreInstalledAppsEnabled' -Value 0 -Type DWord
                Set-ItemProperty -Path $contentPath -Name 'PreInstalledAppsEnabled' -Value 0 -Type DWord
                Set-ItemProperty -Path $contentPath -Name 'SubscribedContent-338389Enabled' -Value 0 -Type DWord
                Set-ItemProperty -Path $contentPath -Name 'SubscribedContent-338393Enabled' -Value 0 -Type DWord
                Set-ItemProperty -Path $contentPath -Name 'SubscribedContent-353698Enabled' -Value 0 -Type DWord
            }
        }
    },
    @{
        Name = "Enabling end task on right-click"
        Script = {
            & {
                $p='HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced\TaskbarDeveloperSettings'
                if(-not (Test-Path $p)){ New-Item -Path $p -Force | Out-Null }
                Set-ItemProperty -Path $p -Name 'TaskbarEndTask' -Value 1 -Force
            }
        }
    },
    @{
        Name = "Disabling file explorer folder discovery"
        Script = {
            & {
                $p='HKCU:\Software\Classes\Local Settings\Software\Microsoft\Windows\Shell\Bags\AllFolders\Shell'
                if(-not (Test-Path $p)){ New-Item -Path $p -Force | Out-Null }
                Set-ItemProperty -Path $p -Name 'FolderType' -Value 'NotSpecified' -Force
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            }
        }
    },
    @{
        Name = "Disabling location tracking"
        Script = {
            & {
                $ErrorActionPreference='SilentlyContinue'
                Set-Service -Name 'lfsvc' -StartupType Disabled
                Stop-Service -Name 'lfsvc' -Force
                $regPath='HKLM:\SOFTWARE\Policies\Microsoft\Windows\LocationAndSensors'
                if(-not (Test-Path $regPath)){ New-Item -Path $regPath -Force | Out-Null }
                Set-ItemProperty -Path $regPath -Name 'DisableLocation' -Value 1 -Type DWord -Force
                New-Item -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' -Force | Out-Null
                Set-ItemProperty -Path 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\CapabilityAccessManager\ConsentStore\location' -Name 'Value' -Value 'Deny' -Type String -Force
            }
        }
    },
    @{
        Name = "Disabling PowerShell telemetry"
        Script = {
            [System.Environment]::SetEnvironmentVariable('POWERSHELL_TELEMETRY_OPTOUT', '1', 'Machine')
        }
    },
    @{
        Name = "Setting all services to manual"
        Script = {
            Get-Service | Where-Object { $_.StartType -ne 'Disabled' } | ForEach-Object {
                Set-Service -Name $_.Name -StartupType Manual -ErrorAction SilentlyContinue
            }
        }
    },
    @{
        Name = "Disabling all system telemetry"
        Script = {
            Get-Service -Name DiagTrack, dmwappushservice, diagnosticshub.standardcollector.service -ErrorAction SilentlyContinue | ForEach-Object {
                Stop-Service $_.Name -Force -ErrorAction SilentlyContinue
                Set-Service $_.Name -StartupType Disabled -ErrorAction SilentlyContinue
            }
            Get-ScheduledTask -TaskPath '\Microsoft\Windows\Application Experience\*' -ErrorAction SilentlyContinue | Disable-ScheduledTask -ErrorAction SilentlyContinue | Out-Null
            & {
                $ErrorActionPreference='SilentlyContinue'
                $paths = @('HKLM:\SOFTWARE\Policies\Microsoft\Windows\DataCollection', 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\DataCollection', 'HKLM:\SOFTWARE\Wow6432Node\Microsoft\Windows\CurrentVersion\Policies\DataCollection')
                foreach ($p in $paths) {
                    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
                    Set-ItemProperty -Path $p -Name 'AllowTelemetry' -Value 0 -Type DWord -Force
                }
            }
        }
    },
    @{
        Name = "Removing temporary files"
        Script = {
            & {
                $ErrorActionPreference='SilentlyContinue'
                $paths = @($env:TEMP, 'C:\Windows\Temp', 'C:\Windows\Prefetch', 'C:\Windows\SoftwareDistribution\Download', 'C:\Windows\Logs\CBS', 'C:\Windows\Logs\DISM')
                foreach ($p in $paths) {
                    if (Test-Path $p) {
                        Get-ChildItem -Path $p -Recurse -Force | Remove-Item -Recurse -Force
                    }
                }
                Clear-RecycleBin -Force
            }
        }
    },
    @{
        Name = "Disabling Windows Platform Binary Table"
        Script = {
            & {
                $p='HKLM:\SYSTEM\CurrentControlSet\Control\Session Manager'
                if(-not (Test-Path $p)){ New-Item -Path $p -Force | Out-Null }
                Set-ItemProperty -Path $p -Name 'DisableWpbtExecution' -Value 1 -Type DWord -Force
            }
        }
    },
    @{
        Name = "Disabling background apps"
        Script = {
            & {
                $ErrorActionPreference='SilentlyContinue'
                Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\BackgroundAccessApplications' -Name 'GlobalUserDisabled' -Value 1 -Type DWord -Force
                Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'BackgroundAppGlobalToggle' -Value 0 -Type DWord -Force
                New-Item -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Force | Out-Null
                Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\AppPrivacy' -Name 'LetAppsRunInBackground' -Value 2 -Type DWord -Force
            }
        }
    },
    @{
        Name = "Disabling Microsoft Copilot"
        Script = {
            & {
                $ErrorActionPreference='SilentlyContinue'
                $Path='HKCU:\Software\Policies\Microsoft\Windows\WindowsCopilot'
                if(-not (Test-Path $Path)){ New-Item -Path $Path -Force | Out-Null }
                Set-ItemProperty -Path $Path -Name 'TurnOffWindowsCopilot' -Value 1 -Force
                Get-AppxPackage -Name '*copilot*' | Remove-AppxPackage -ErrorAction SilentlyContinue
            }
        }
    },
    @{
        Name = "Removing Microsoft Edge"
        Script = {
            winget uninstall --id Microsoft.Edge -e --silent --accept-source-agreements *> $null
            winget uninstall --id Microsoft.EdgeWebView2Runtime -e --silent --accept-source-agreements *> $null
        }
    },
    @{
        Name = "Removing Microsoft OneDrive"
        Script = {
            taskkill /f /im OneDrive.exe *> $null
            winget uninstall --id Microsoft.OneDrive -e --silent --accept-source-agreements *> $null
        }
    },
    @{
        Name = "Enabling right-click menu previous layout"
        Script = {
            & {
                $ErrorActionPreference = 'SilentlyContinue'
                $path = "HKCU:\Software\Classes\CLSID\{86ca1aa0-34aa-4e8b-a509-50c905bae2a2}\InprocServer32"
                New-Item -Path $path -Force | Out-Null
                Set-ItemProperty -Path $path -Name '(Default)' -Value '' -Type String -Force
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            }
        }
    },
    @{
        Name = "Setting visual effects to best performance"
        Script = {
            Set-ItemProperty -Path "HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\VisualEffects" -Name "VisualFXSetting" -Value 3 -Type DWord -Force -ErrorAction SilentlyContinue
            Restart-Service -Name "Themes" -Force -ErrorAction SilentlyContinue
        }
    },
    @{
        Name = "Removing Xbox & gaming components"
        Script = {
            $j = Start-Job -ScriptBlock {
                $ErrorActionPreference = 'SilentlyContinue'
                # XboxGameCallableUI is a protected system app and cannot be removed — skip it
                Get-AppxPackage -AllUsers *xbox* |
                    Where-Object { $_.Name -ne 'Microsoft.XboxGameCallableUI' } |
                    ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
                Get-AppxPackage -AllUsers *Microsoft.GamingServices* |
                    ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
                Get-AppxPackage -AllUsers *Microsoft.XboxGamingOverlay* |
                    ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
                Get-AppxPackage -AllUsers *Microsoft.XboxSpeechToTextOverlay* |
                    ForEach-Object { Remove-AppxPackage -Package $_.PackageFullName -AllUsers -ErrorAction SilentlyContinue }
                $dvr = 'HKCU:\SOFTWARE\Microsoft\Windows\CurrentVersion\GameDVR'
                if (-not (Test-Path $dvr)) { New-Item $dvr -Force | Out-Null }
                Set-ItemProperty $dvr AppCaptureEnabled 0 -Type DWord -Force
                $store = 'HKCU:\System\GameConfigStore'
                if (-not (Test-Path $store)) { New-Item $store -Force | Out-Null }
                Set-ItemProperty $store GameDVR_Enabled 0 -Type DWord -Force
                'XblAuthManager','XblGameSave','XboxNetApiSvc','XboxGipSvc','Xbgm' | ForEach-Object {
                    Stop-Service $_ -Force -ErrorAction SilentlyContinue
                    Set-Service $_ -StartupType Disabled -ErrorAction SilentlyContinue
                }
            }
            Wait-Job $j | Out-Null
            Remove-Job $j -Force
        }
    },
    @{
        Name = "Disabling Game Mode"
        Script = {
            & {
                $ErrorActionPreference='SilentlyContinue'
                $gb='HKCU:\Software\Microsoft\GameBar'
                if(-not (Test-Path $gb)){New-Item $gb -Force|Out-Null}
                Set-ItemProperty $gb AutoGameModeEnabled 0 -Type DWord -Force
                Set-ItemProperty $gb AllowAutoGameMode 0 -Type DWord -Force
                $gd='HKLM:\SOFTWARE\Policies\Microsoft\Windows\GameDVR'
                if(-not (Test-Path $gd)){New-Item $gd -Force|Out-Null}
                Set-ItemProperty $gd AllowGameMode 0 -Type DWord -Force
            }
        }
    },
    @{
        Name = "Disabling cross-device resume"
        Script = {
            & {
                $ErrorActionPreference='SilentlyContinue'
                $PolicyPath='HKLM:\SOFTWARE\Microsoft\PolicyManager\default\Connectivity\DisableCrossDeviceResume'
                $UserPath='HKCU:\Software\Microsoft\Windows\CurrentVersion\CrossDeviceResume\Configuration'
                foreach ($p in @($PolicyPath, $UserPath)) {
                    if (-not (Test-Path $p)) { New-Item -Path $p -Force | Out-Null }
                }
                Set-ItemProperty -Path $PolicyPath -Name 'value' -Value 1 -Type DWord -Force
                Set-ItemProperty -Path $UserPath -Name 'IsResumeAllowed' -Value 0 -Type DWord -Force
            }
        }
    },
    @{
        Name = "Enabling dark mode"
        Script = {
            & {
                $ErrorActionPreference='SilentlyContinue'
                $path='HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize'
                if(-not (Test-Path $path)){New-Item -Path $path -Force | Out-Null}
                Set-ItemProperty -Path $path -Name 'AppsUseLightTheme' -Value 0 -Type DWord -Force
                Set-ItemProperty -Path $path -Name 'SystemUsesLightTheme' -Value 0 -Type DWord -Force
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            }
        }
    },
    @{
        Name = "Enabling file extensions and hidden files"
        Script = {
            & {
                $ErrorActionPreference='SilentlyContinue'
                Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'HideFileExt' -Value 0 -Type DWord -Force
                Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Hidden' -Value 1 -Type DWord -Force
                Stop-Process -Name explorer -Force
            }
        }
    },
    @{
        Name = "Enabling logon verbose mode"
        Script = {
            & {
                $ErrorActionPreference='SilentlyContinue'
                $path = 'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Policies\System'
                if(-not (Test-Path $path)) { New-Item -Path $path -Force | Out-Null }
                Set-ItemProperty -Path $path -Name 'VerboseStatus' -Value 1 -Type DWord -Force
            }
        }
    },
    @{
        Name = "Enabling Num-Lock on startup"
        Script = {
            & {
                $ErrorActionPreference='SilentlyContinue'
                $guPath='Registry::HKEY_USERS\.DEFAULT\Control Panel\Keyboard'
                $cuPath='HKCU:\Control Panel\Keyboard'
                foreach($p in @($guPath,$cuPath)){
                    if(-not (Test-Path $p)){New-Item -Path $p -Force | Out-Null}
                    Set-ItemProperty -Path $p -Name 'InitialKeyboardIndicators' -Value 2 -Type String -Force
                }
            }
        }
    },
    @{
        Name = "Disabling Start menu Bing search & suggestions"
        Script = {
            & {
                $ErrorActionPreference='SilentlyContinue'
                $Paths=@('HKCU:\Software\Policies\Microsoft\Windows\Explorer','HKCU:\Software\Microsoft\Windows\CurrentVersion\Search','HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced','HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer')
                foreach($p in $Paths){if(-not (Test-Path $p)){New-Item -Path $p -Force | Out-Null}}
                Set-ItemProperty -Path 'HKCU:\Software\Policies\Microsoft\Windows\Explorer' -Name 'DisableSearchBoxSuggestions' -Value 1 -Type DWord -Force
                Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'BingSearchEnabled' -Value 0 -Type DWord -Force
                Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Search' -Name 'CortanaConsent' -Value 0 -Type DWord -Force
                Set-ItemProperty -Path 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Explorer\Advanced' -Name 'Start_IrisRecommendations' -Value 0 -Type DWord -Force
                Set-ItemProperty -Path 'HKLM:\SOFTWARE\Policies\Microsoft\Windows\Explorer' -Name 'NoUseStoreOpenWith' -Value 1 -Type DWord -Force
                Stop-Process -Name explorer -Force -ErrorAction SilentlyContinue
            }
        }
    },
    @{
        Name = "Disabling Sticky Keys"
        Script = {
            & {
                $ErrorActionPreference='SilentlyContinue'
                $path='HKCU:\Control Panel\Accessibility\StickyKeys'
                if(-not (Test-Path $path)){New-Item -Path $path -Force | Out-Null}
                Set-ItemProperty -Path $path -Name 'Flags' -Value '506' -Type String -Force
            }
        }
    },
    @{
        Name = "HPET optimization"
        Script = {
            bcdedit /set useplatformtick yes *> $null
            bcdedit /set disabledynamictick yes *> $null
            bcdedit /deletevalue useplatformclock *> $null
        }
    },
    @{
        Name = "Disabling all startup apps"
        Script = {
            & {
                $ErrorActionPreference='SilentlyContinue'
                $runKeys = @(
                    'HKCU:\Software\Microsoft\Windows\CurrentVersion\Run',
                    'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Run',
                    'HKLM:\SOFTWARE\WOW6432Node\Microsoft\Windows\CurrentVersion\Run'
                )
                foreach ($key in $runKeys) {
                    $item = Get-Item -Path $key -ErrorAction SilentlyContinue
                    if ($item) {
                        $item.Property | ForEach-Object {
                            Remove-ItemProperty -Path $key -Name $_ -Force -ErrorAction SilentlyContinue
                        }
                    }
                }
                Get-ChildItem "$env:APPDATA\Microsoft\Windows\Start Menu\Programs\Startup" -Filter *.lnk -ErrorAction SilentlyContinue | Remove-Item -Force
                Get-ChildItem 'C:\ProgramData\Microsoft\Windows\Start Menu\Programs\StartUp' -Filter *.lnk -ErrorAction SilentlyContinue | Remove-Item -Force
            }
        }
    },
    @{
        Name = "Running O&O ShutUp10++"
        Script = {
            Start-Process -FilePath '.\oo\OOSU10.exe' -ArgumentList '.\oo\ooshutup10.cfg /quiet /nosrp' -Wait -NoNewWindow -ErrorAction SilentlyContinue
        }
    },
    @{
        Name = "Updating Windows Update settings"
        Script = {
            & {
                $p='HKLM:\SOFTWARE\Policies\Microsoft\Windows\WindowsUpdate'
                if(-not (Test-Path $p)){New-Item -Path $p -Force | Out-Null}
                Set-ItemProperty -Path $p -Name 'DeferFeatureUpdates' -Value 1 -Type DWord -Force
                Set-ItemProperty -Path $p -Name 'DeferFeatureUpdatesPeriodInDays' -Value 30 -Type DWord -Force
                Set-ItemProperty -Path $p -Name 'DeferQualityUpdates' -Value 1 -Type DWord -Force
                Set-ItemProperty -Path $p -Name 'DeferQualityUpdatesPeriodInDays' -Value 2 -Type DWord -Force
                Set-ItemProperty -Path $p -Name 'ExcludeWUDriversInQualityUpdate' -Value 1 -Type DWord -Force
            }
        }
    },
    @{
        Name = "Running additional tweaks"
        Script = {
            $job = Start-Job -ScriptBlock {
                Set-Location $using:PWD
                & '.\scripts\add.ps1' *> $null
            }
            $timeout = 180
            $completed = Wait-Job $job -Timeout $timeout
            if (-not $completed) {
                Stop-Job $job
            }
            Remove-Job $job -Force
        }
    }
)

# ---------- Main execution ----------
$total = $tasks.Count
Write-Host "Press ENTER to start." -NoNewline
Read-Host
Write-Host "Starting..."

$i = 1
foreach ($task in $tasks) {
    Write-Host "$($task.Name) ($i/$total)"
    try {
        & $task.Script
    }
    catch {
        Write-Host "  ERROR: $_" -ForegroundColor Red
    }
    $i++
}

# ---------- Final message & restore Explorer ----------
Write-Host "Done. Please restart your system." -ForegroundColor Green

# Bring Explorer back if it was killed
try {
    if (-not (Get-Process -Name explorer -ErrorAction SilentlyContinue)) {
        Start-Process explorer.exe -NoNewWindow
    }
}
catch { }

# Stay open for a few seconds, then close
Start-Sleep -Seconds 5