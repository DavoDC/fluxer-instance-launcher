<#
.SYNOPSIS
  Starts the official Fluxer desktop app on your chosen instance and keeps it there after Fluxer updates.
.DESCRIPTION
  With no action it opens an arrow-key menu (shows your status, then Install, Uninstall, Quit) for people.
  Actions for scripts and tests: launch, apply, repair, status, uninstall. See README.md.
  Reads config\config.json; if it is missing, creates it from a template built into this script and exits 3.
  No network, no admin rights.
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
    [ValidateSet('', 'launch', 'apply', 'repair', 'status', 'uninstall')]
    [string]$Action = '',
    [string]$ConfigPath,
    [string]$Root,
    [string]$RegistryBase = 'HKCU:\Software',
    [string]$FluxerExe,
    [int]$DelaySeconds = 0,
    [switch]$DryRun,
    [switch]$AllowInsecure,
    [switch]$ForceRestart,
    [switch]$Yes
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
$DefaultConfigJson = @'
{
  "instance_url": "https://chat.codered.lol",
  "autostart": true,
  "autostart_delay_seconds": 15,
  "handler_patch": false,
  "shortcut_name": "Fluxer (my instance)",
  "repair_after_launch_seconds": 15
}
'@

function Get-Config {
    if (-not $ConfigPath) { $script:ConfigPath = Join-Path $PSScriptRoot '..\config\config.json' }
    $path = $ConfigPath
    if (-not (Test-Path $path)) {
        $full = [System.IO.Path]::GetFullPath($path)
        if ($DryRun) {
            Write-Host "[dry-run] would create your settings file at $full (it does not exist yet)"
        } else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            Set-Content -Path $full -Value $DefaultConfigJson -Encoding UTF8
            Write-Host "Created your settings file at $full. Open it, check the instance address, save, then run this again."
        }
        exit 3
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

# ---------- menu (for people; scripts and tests pass an action instead) ----------
$MenuItems = @('Install', 'Uninstall', 'Quit')
$script:MenuCfg = $null
$script:MenuLoc = $null

# Reads one key code. FLI_TEST_KEYS (comma list of Up, Down, Enter, Esc, Y, N) replaces the keyboard in tests.
function Read-KeyCode {
    if ($null -ne $env:FLI_TEST_KEYS) {
        if ($null -eq $script:TestKeys) {
            $script:TestKeys = New-Object System.Collections.Queue
            foreach ($k in ($env:FLI_TEST_KEYS -split ',')) { if ($k.Trim()) { $script:TestKeys.Enqueue($k.Trim()) } }
        }
        if ($script:TestKeys.Count -eq 0) { return 27 }
        $map = @{ Up = 38; Down = 40; Enter = 13; Esc = 27; Y = 89; N = 78 }
        return [int]$map[[string]$script:TestKeys.Dequeue()]
    }
    return $Host.UI.RawUI.ReadKey('NoEcho,IncludeKeyDown').VirtualKeyCode
}

# Pure key handling: returns the new selected index, or 'enter' / 'quit'.
function Step-Menu([int]$Index, [int]$Count, [int]$Key) {
    switch ($Key) {
        38 { return (($Index - 1 + $Count) % $Count) }
        40 { return (($Index + 1) % $Count) }
        13 { return 'enter' }
        27 { return 'quit' }
    }
    return $Index
}

function Show-Menu([int]$Index) {
    try { Clear-Host } catch { }
    Write-Host 'Fluxer Instance Setup'
    Write-Host ''
    if ($null -ne $script:MenuCfg) { [void](Show-StatusPlain $script:MenuCfg $script:MenuLoc); Write-Host '' }
    Write-Host 'Use the arrow keys, then press Enter. Press Esc to quit.'
    Write-Host ''
    for ($i = 0; $i -lt $MenuItems.Count; $i++) {
        if ($i -eq $Index) { Write-Host ('  > {0}' -f $MenuItems[$i]) -ForegroundColor Cyan } else { Write-Host ('    {0}' -f $MenuItems[$i]) }
    }
    Write-Host ''
}

function Read-Menu {
    $i = 0
    while ($true) {
        Show-Menu $i
        $r = Step-Menu $i $MenuItems.Count (Read-KeyCode)
        if ($r -is [string]) { if ($r -eq 'enter') { return $MenuItems[$i] } else { return $null } }
        $i = [int]$r
    }
}

function Confirm-Yes([string]$Question) {
    if ($Yes) { return $true }
    Write-Host "$Question (y/n)"
    while ($true) {
        $k = Read-KeyCode
        if ($k -eq 89) { return $true }
        if ($k -eq 78 -or $k -eq 27) { return $false }
    }
}

function Show-StatusPlain($cfg, $loc) {
    $script:plainBad = 0
    $say = {
        param($good, $goodText, $badText)
        if ($good) { Write-Host "  [good] $goodText" -ForegroundColor Green } else { Write-Host "  [problem] $badText" -ForegroundColor Red; $script:plainBad++ }
    }
    Write-Host "Your Fluxer address: $($cfg.Url)"
    & $say (Test-Path $loc.FluxerExe) 'Fluxer is installed.' 'Fluxer does not seem to be installed yet. Install Fluxer first.'
    $runNow = Get-RegValue $loc.RunKey $RunValueName
    if ($cfg.Autostart) { & $say ($runNow -eq (Get-ExpectedRunValue $cfg)) 'Fluxer will open on your address when you sign in to Windows.' 'Fluxer is not set to open on your address at sign-in. Pick Install to fix it.' }
    else { & $say ($null -eq $runNow) 'Opening at sign-in is switched off in your settings, and it is off.' 'Opening at sign-in is switched off in your settings, but it is still on. Pick Install to fix it.' }
    & $say ($null -eq (Get-RegValue $loc.RunKey $FluxerRunValueName)) 'Fluxer is not starting itself on the official server.' 'Fluxer is set to start itself on the official server. Pick Install to fix it.'
    $names = @('Desktop', 'Start Menu')
    for ($i = 0; $i -lt $loc.Folders.Count; $i++) {
        $s = Get-ShortcutState (Join-Path $loc.Folders[$i] "$($cfg.ShortcutName).lnk")
        & $say ($s -eq 'ok') "The $($names[$i]) shortcut `"$($cfg.ShortcutName)`" is in place." "The $($names[$i]) shortcut `"$($cfg.ShortcutName)`" is missing or wrong. Pick Install to fix it."
    }
    if ($script:plainBad -eq 0) { Write-Host 'Everything is working.' -ForegroundColor Green } else { Write-Host 'Something needs fixing. Pick Install and it will be put right.' -ForegroundColor Red }
    return $script:plainBad
}

function Invoke-Menu($cfg, $loc) {
    $script:MenuCfg = $cfg
    $script:MenuLoc = $loc
    $choice = Read-Menu
    if ($null -eq $choice -or $choice -eq 'Quit') { return 0 }
    Write-Host ''
    switch ($choice) {
        'Install' {
            Write-Host 'Install will:'
            Write-Host "  - make Fluxer open on $($cfg.Url)"
            Write-Host "  - add a shortcut called `"$($cfg.ShortcutName)`" to your Desktop and Start Menu"
            if ($cfg.Autostart) { Write-Host '  - open Fluxer that way when you sign in to Windows' }
            Write-Host "  - turn off Fluxer's own start-up entry, so it does not open the official server"
            Write-Host 'Nothing needs administrator rights, and Uninstall undoes it all.'
            if (-not (Confirm-Yes 'Go ahead?')) { Write-Host 'Cancelled. Nothing was changed.'; return 0 }
            Sync-Entries $cfg $loc $false
            Write-Host "Done. Open Fluxer from the `"$($cfg.ShortcutName)`" shortcut."
            return 0
        }
        'Uninstall' {
            Write-Host 'Uninstall removes the shortcuts and the sign-in entry this tool made. Fluxer itself is not touched.'
            if (-not (Confirm-Yes 'Go ahead?')) { Write-Host 'Cancelled. Nothing was changed.'; return 0 }
            Remove-Entries $cfg $loc
            return 0
        }
    }
    return 0
}

# ---------- main ----------
$script:ChangeCount = 0
if ($Action -eq '' -and $null -eq $env:FLI_TEST_KEYS -and [Console]::IsInputRedirected) {
    Write-Host 'Usage: run "Fluxer Instance Setup.bat" with no arguments for the menu, or pass an action: launch, apply, repair, status, uninstall (options: -DryRun, -Yes).'
    exit 2
}
$cfg = Get-Config
if ($Action -ne 'uninstall') {
    $err = Test-InstanceUrl $cfg.Url
    if ($err) { Stop-WithError $err }
}
$loc = Get-Locations
if ($DryRun) { Write-Host '(dry run: nothing will be changed)' }
$code = 0
if ($Action -eq '') {
    $code = Invoke-Menu $cfg $loc
    exit $code
}
switch ($Action) {
    'apply'     { Sync-Entries $cfg $loc $false }
    'repair'    { Sync-Entries $cfg $loc $true }
    'status'    { $code = if ((Show-Status $cfg $loc) -gt 0) { 1 } else { 0 } }
    'uninstall' { Remove-Entries $cfg $loc }
    'launch'    { $code = Start-Fluxer $cfg $loc }
}
if ($Action -ne 'repair' -or $script:ChangeCount -gt 0) { Write-Host ('Done in {0:N1}s (exit {1})' -f $sw.Elapsed.TotalSeconds, $code) }
exit $code
