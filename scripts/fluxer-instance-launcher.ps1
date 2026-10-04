<#
.SYNOPSIS
  Starts the official Fluxer desktop app on your chosen instance and keeps it there after Fluxer updates.
.DESCRIPTION
  Actions: launch (default), apply, repair, status, uninstall. See README.md.
  Reads config\config.json (falls back to config\config.example.json). No network, no admin rights.
  Writes only: the HKCU Run value FluxerInstance, its own shortcuts, and (opt-in) the fluxer:// handler.
  Test and safety parameters: -Root redirects Desktop, Start Menu and LocalAppData into a folder,
  -RegistryBase redirects the registry writes to another key, -DryRun prints instead of changing anything.
.EXAMPLE
  .\fluxer-instance-launcher.ps1 status
.EXAMPLE
  .\fluxer-instance-launcher.ps1 apply -DryRun
#>
[CmdletBinding()]
param(
    [Parameter(Position = 0)]
    [ValidateSet('launch', 'apply', 'repair', 'status', 'uninstall')]
    [string]$Action = 'launch',
    [string]$ConfigPath,
    [string]$Root,
    [string]$RegistryBase = 'HKCU:\Software',
    [string]$FluxerExe,
    [int]$DelaySeconds = 0,
    [switch]$DryRun,
    [switch]$AllowInsecure,
    [switch]$ForceRestart
)

$ErrorActionPreference = 'Stop'
$sw = [System.Diagnostics.Stopwatch]::StartNew()
$RunValueName = 'FluxerInstance'
$FluxerRunValueName = 'Fluxer.Fluxer'
$ScriptPath = $PSCommandPath
$PowerShellExe = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'

function Stop-WithError([string]$Message) {
    Write-Host "ERROR: $Message"
    exit 2
}

# ---------- config ----------
function Get-Config {
    if (-not $ConfigPath) { $script:ConfigPath = Join-Path $PSScriptRoot '..\config\config.json' }
    $path = $ConfigPath
    if (-not (Test-Path $path)) {
        $path = Join-Path (Split-Path -Parent $ConfigPath) 'config.example.json'
        if (-not (Test-Path $path)) { Stop-WithError "No config found at $ConfigPath or $path" }
    }
    try { $c = Get-Content -Raw -Path $path | ConvertFrom-Json } catch { Stop-WithError "Config is not valid JSON: $path" }
    Write-Host "Config: $path"
    $get = { param($n, $d) if ($null -ne $c.$n) { $c.$n } else { $d } }
    [pscustomobject]@{
        Url             = [string](& $get 'instance_url' '')
        Autostart       = [bool](& $get 'autostart' $true)
        AutostartDelay  = [int](& $get 'autostart_delay_seconds' 15)
        HandlerPatch    = [bool](& $get 'handler_patch' $false)
        ShortcutName    = [string](& $get 'shortcut_name' 'Fluxer (my instance)')
        RepairAfterSecs = [int](& $get 'repair_after_launch_seconds' 15)
    }
}

function Test-InstanceUrl([string]$Url) {
    if ($Url -match '[\s"''<>|^&%]') { return 'instance_url contains a space, quote or special character' }
    $u = $null
    if (-not [uri]::TryCreate($Url, [UriKind]::Absolute, [ref]$u) -or -not $u.Host) { return 'instance_url is not a valid URL with a host' }
    if ($u.Scheme -eq 'https') { return $null }
    if ($u.Scheme -eq 'http' -and $AllowInsecure) { return $null }
    if ($u.Scheme -eq 'http') { return 'instance_url uses http; use https (or pass -AllowInsecure if you really mean it)' }
    return 'instance_url must start with https://'
}

# ---------- locations ----------
function Get-Locations {
    if ($Root) {
        $desk = Join-Path $Root 'Desktop'
        $menu = Join-Path $Root 'StartMenu'
        $local = Join-Path $Root 'LocalAppData'
    } else {
        $desk = [Environment]::GetFolderPath('Desktop')
        $menu = [Environment]::GetFolderPath('Programs')
        $local = $env:LOCALAPPDATA
    }
    $exe = if ($FluxerExe) { $FluxerExe } else { Join-Path $local 'fluxer_desktop\Fluxer.exe' }
    [pscustomobject]@{
        Folders    = @($desk, $menu)
        FluxerExe  = $exe
        RunKey     = Join-Path $RegistryBase 'Microsoft\Windows\CurrentVersion\Run'
        HandlerKey = Join-Path $RegistryBase 'Classes\fluxer\shell\open\command'
    }
}

# ---------- helpers ----------
function Invoke-Change([string]$Description, [scriptblock]$Do) {
    if ($DryRun) { Write-Host "[dry-run] would: $Description"; return }
    & $Do
    Write-Host "[changed] $Description"
}

function Get-RegValue([string]$Key, [string]$Name) {
    if (-not (Test-Path $Key)) { return $null }
    $p = Get-ItemProperty -Path $Key -Name $Name -ErrorAction SilentlyContinue
    if ($p) { $p.$Name } else { $null }
}

function Get-ExpectedRunValue($cfg) {
    '"{0}" -NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{1}" launch -DelaySeconds {2}' -f $PowerShellExe, $ScriptPath, $cfg.AutostartDelay
}

function Get-ExpectedShortcutArgs {
    '-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File "{0}" launch' -f $ScriptPath
}

function Get-ShortcutState($lnkPath) {
    if (-not (Test-Path $lnkPath)) { return 'missing' }
    $l = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
    if ($l.TargetPath -eq $PowerShellExe -and $l.Arguments -eq (Get-ExpectedShortcutArgs)) { 'ok' } else { 'drift' }
}

function Set-Shortcut($lnkPath, $loc) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $lnkPath) -Force | Out-Null
    $l = (New-Object -ComObject WScript.Shell).CreateShortcut($lnkPath)
    $l.TargetPath = $PowerShellExe
    $l.Arguments = Get-ExpectedShortcutArgs
    $l.WindowStyle = 7
    $l.Description = 'Fluxer on your own instance (fluxer-instance-launcher)'
    if (Test-Path $loc.FluxerExe) { $l.IconLocation = "$($loc.FluxerExe),0" }
    $l.Save()
}

function Get-HandlerExe([string]$Value) {
    if ($Value -match '^"([^"]+)"') { $Matches[1] } else { $null }
}

# ---------- apply / repair ----------
function Sync-Entries($cfg, $loc, [bool]$Quiet) {
    $changed = 0
    $before = $script:ChangeCount
    $script:ChangeCount = 0

    # 1. our Run value
    $runNow = Get-RegValue $loc.RunKey $RunValueName
    if ($cfg.Autostart) {
        $want = Get-ExpectedRunValue $cfg
        if ($runNow -ne $want) {
            # New-Item -Force on an existing key wipes its values, so create only when absent.
            Invoke-Change "set Run value $RunValueName" { if (-not (Test-Path $loc.RunKey)) { New-Item -Path $loc.RunKey -Force | Out-Null }; Set-ItemProperty -Path $loc.RunKey -Name $RunValueName -Value $want }
            $script:ChangeCount++
        }
    } elseif ($null -ne $runNow) {
        Invoke-Change "remove Run value $RunValueName (autostart is off in config)" { Remove-ItemProperty -Path $loc.RunKey -Name $RunValueName }
        $script:ChangeCount++
    }

    # 2. Fluxer's own autostart value would start the official instance
    if ($null -ne (Get-RegValue $loc.RunKey $FluxerRunValueName)) {
        Invoke-Change "delete Fluxer's own Run value $FluxerRunValueName" { Remove-ItemProperty -Path $loc.RunKey -Name $FluxerRunValueName }
        $script:ChangeCount++
    }

    # 3. our shortcuts
    foreach ($folder in $loc.Folders) {
        $lnk = Join-Path $folder "$($cfg.ShortcutName).lnk"
        if ((Get-ShortcutState $lnk) -ne 'ok') {
            Invoke-Change "write shortcut $lnk" { Set-Shortcut $lnk $loc }
            $script:ChangeCount++
        }
    }

    # 4. fluxer:// handler: opt-in only
    $hNow = Get-RegValue $loc.HandlerKey '(default)'
    if ($null -ne $hNow) {
        $exe = Get-HandlerExe $hNow
        if ($cfg.HandlerPatch -and $exe) {
            $want = '"{0}" --fluxer-app-url={1} "%1"' -f $exe, $cfg.Url
            if ($hNow -ne $want) {
                Invoke-Change 'patch the fluxer:// handler (opt-in)' { Set-ItemProperty -Path $loc.HandlerKey -Name '(default)' -Value $want }
                $script:ChangeCount++
            }
        } elseif ($exe -and $hNow -match '--fluxer-app-url=') {
            $stock = '"{0}" "%1"' -f $exe
            Invoke-Change 'restore the stock fluxer:// handler' { Set-ItemProperty -Path $loc.HandlerKey -Name '(default)' -Value $stock }
            $script:ChangeCount++
        }
    }

    if ($script:ChangeCount -eq 0 -and -not $Quiet) { Write-Host '[ok] everything already in place' }
    $script:ChangeCount = $before + $script:ChangeCount
}

# ---------- status ----------
function Show-Status($cfg, $loc) {
    $bad = 0
    $line = {
        param($state, $text)
        Write-Host ('[{0}] {1}' -f $state, $text)
        if ($state -ne 'OK' -and $state -ne 'INFO') { $script:bad++ }
    }
    $script:bad = 0
    Write-Host "Instance: $($cfg.Url)"
    $runNow = Get-RegValue $loc.RunKey $RunValueName
    if ($cfg.Autostart) {
        if ($runNow -eq (Get-ExpectedRunValue $cfg)) { & $line 'OK' "Run value $RunValueName" }
        elseif ($null -eq $runNow) { & $line 'MISSING' "Run value $RunValueName (run: apply)" }
        else { & $line 'DRIFT' "Run value $RunValueName differs (run: repair)" }
    } else {
        if ($null -eq $runNow) { & $line 'OK' "autostart off, no Run value $RunValueName" } else { & $line 'DRIFT' "Run value $RunValueName present but autostart is off" }
    }
    if ($null -eq (Get-RegValue $loc.RunKey $FluxerRunValueName)) { & $line 'OK' "Fluxer's own autostart ($FluxerRunValueName) absent" }
    else { & $line 'DRIFT' "Fluxer's own autostart ($FluxerRunValueName) is back; it starts the official instance (run: repair)" }
    foreach ($folder in $loc.Folders) {
        $lnk = Join-Path $folder "$($cfg.ShortcutName).lnk"
        $s = Get-ShortcutState $lnk
        $label = "shortcut $lnk"
        if ($s -eq 'ok') { & $line 'OK' $label } elseif ($s -eq 'missing') { & $line 'MISSING' "$label (run: apply)" } else { & $line 'DRIFT' "$label differs (run: repair)" }
    }
    $hNow = Get-RegValue $loc.HandlerKey '(default)'
    if ($cfg.HandlerPatch) {
        if ($null -eq $hNow) { & $line 'INFO' 'fluxer:// handler not registered, nothing to patch' }
        elseif ($hNow -match [regex]::Escape("--fluxer-app-url=$($cfg.Url)")) { & $line 'OK' 'fluxer:// handler carries the instance' }
        else { & $line 'DRIFT' 'fluxer:// handler lacks the instance (Fluxer rewrites it every launch; run: repair)' }
    } else {
        & $line 'INFO' 'fluxer:// handler not managed (handler_patch is false)'
    }
    if (Test-Path $loc.FluxerExe) { & $line 'INFO' "Fluxer found at $($loc.FluxerExe)" } else { & $line 'INFO' "Fluxer.exe not found at $($loc.FluxerExe)" }
    return $script:bad
}

# ---------- launch ----------
function Get-MainFluxerProcess {
    try {
        Get-CimInstance Win32_Process -Filter "Name='Fluxer.exe'" |
            Where-Object { $_.CommandLine -and $_.CommandLine -notmatch '--type=' }
    } catch { @() }
}

function Start-Fluxer($cfg, $loc) {
    $flag = "--fluxer-app-url=$($cfg.Url)"
    if ($DelaySeconds -gt 0 -and -not $DryRun) { Write-Host "Waiting $DelaySeconds s before launch"; Start-Sleep -Seconds $DelaySeconds }
    if ($DryRun) { Write-Host "[dry-run] would run: `"$($loc.FluxerExe)`" $flag"; return 0 }
    if (-not (Test-Path $loc.FluxerExe)) { Write-Host "ERROR: Fluxer not found at $($loc.FluxerExe). Install Fluxer first."; return 2 }
    $main = @(Get-MainFluxerProcess)
    if ($main.Count -gt 0) {
        if ($main[0].CommandLine -match [regex]::Escape($flag)) { Write-Host 'Fluxer is already running on your instance.'; return 0 }
        if (-not $ForceRestart) {
            Write-Host 'Fluxer is already running on another instance, and a second launch cannot change that. Quit Fluxer (tray icon too) and run launch again, or add -ForceRestart.'
            return 3
        }
        Write-Host 'Stopping the running Fluxer (-ForceRestart)'
        Get-Process -Name Fluxer -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
    }
    Start-Process -FilePath $loc.FluxerExe -ArgumentList $flag
    Write-Host "Started Fluxer on $($cfg.Url)"
    if ($cfg.RepairAfterSecs -gt 0) {
        Start-Sleep -Seconds $cfg.RepairAfterSecs
        $script:ChangeCount = 0
        Sync-Entries $cfg $loc $true
    }
    return 0
}

# ---------- uninstall ----------
function Remove-Entries($cfg, $loc) {
    if ($null -ne (Get-RegValue $loc.RunKey $RunValueName)) {
        Invoke-Change "remove Run value $RunValueName" { Remove-ItemProperty -Path $loc.RunKey -Name $RunValueName }
    }
    foreach ($folder in $loc.Folders) {
        $lnk = Join-Path $folder "$($cfg.ShortcutName).lnk"
        if (Test-Path $lnk) { Invoke-Change "delete shortcut $lnk" { Remove-Item -Path $lnk -Force } }
    }
    $hNow = Get-RegValue $loc.HandlerKey '(default)'
    $exe = if ($hNow) { Get-HandlerExe $hNow } else { $null }
    if ($exe -and $hNow -match '--fluxer-app-url=') {
        $stock = '"{0}" "%1"' -f $exe
        Invoke-Change 'restore the stock fluxer:// handler' { Set-ItemProperty -Path $loc.HandlerKey -Name '(default)' -Value $stock }
    }
    Write-Host 'Uninstall done. Fluxer itself is untouched; turn its own autostart on in its settings if you want it.'
}

# ---------- main ----------
$script:ChangeCount = 0
$cfg = Get-Config
if ($Action -ne 'uninstall') {
    $err = Test-InstanceUrl $cfg.Url
    if ($err) { Stop-WithError $err }
}
$loc = Get-Locations
if ($DryRun) { Write-Host '(dry run: nothing will be changed)' }
$code = 0
switch ($Action) {
    'apply'     { Sync-Entries $cfg $loc $false }
    'repair'    { Sync-Entries $cfg $loc $true }
    'status'    { $code = if ((Show-Status $cfg $loc) -gt 0) { 1 } else { 0 } }
    'uninstall' { Remove-Entries $cfg $loc }
    'launch'    { $code = Start-Fluxer $cfg $loc }
}
if ($Action -ne 'repair' -or $script:ChangeCount -gt 0) { Write-Host ('Done in {0:N1}s (exit {1})' -f $sw.Elapsed.TotalSeconds, $code) }
exit $code
