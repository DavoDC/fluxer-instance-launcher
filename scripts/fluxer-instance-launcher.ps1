<#
.SYNOPSIS
  Starts the official Fluxer desktop app on your chosen instance and keeps it there after Fluxer updates.
.DESCRIPTION
  With no action it opens an arrow-key menu (shows your status, then Install, Uninstall, Quit) for people.
  Actions for scripts and tests: launch, apply, repair, status, uninstall. See README.md.
  Reads config\config.json; if it is missing, creates it from a template built into this script and exits 3.
  No network, no admin rights.
  Writes only: the HKCU Run value FluxerInstance, the --fluxer-app-url argument of Fluxer's own icons
  (Start Menu, Desktop, taskbar), and (opt-in) the fluxer:// handler. It creates no shortcut of its own.
  Test and safety parameters: -Root redirects Desktop, Start Menu, taskbar and LocalAppData into a folder,
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
    $get = { param($n, $d) if ($null -ne $c.$n) { $c.$n } else { $d } }
    [pscustomobject]@{
        Url             = [string](& $get 'instance_url' '')
        Autostart       = [bool](& $get 'autostart' $true)
        AutostartDelay  = [int](& $get 'autostart_delay_seconds' 15)
        HandlerPatch    = [bool](& $get 'handler_patch' $false)
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
        $task = Join-Path $Root 'Taskbar'
    } else {
        $desk = [Environment]::GetFolderPath('Desktop')
        $menu = [Environment]::GetFolderPath('Programs')
        $local = $env:LOCALAPPDATA
        $task = Join-Path $env:APPDATA 'Microsoft\Internet Explorer\Quick Launch\User Pinned\TaskBar'
    }
    $exe = if ($FluxerExe) { $FluxerExe } else { Join-Path $local 'fluxer_desktop\current\Fluxer.exe' }
    [pscustomobject]@{
        # Fluxer's own icons; only those that exist are ever touched.
        Icons      = @(
            [pscustomobject]@{ Name = 'Start Menu'; Path = (Join-Path $menu 'Fluxer Platform AB\Fluxer.lnk') }
            [pscustomobject]@{ Name = 'Desktop'; Path = (Join-Path $desk 'Fluxer.lnk') }
            [pscustomobject]@{ Name = 'taskbar'; Path = (Join-Path $task 'Fluxer.lnk') }
        )
        # Shortcuts an earlier version of this launcher made.
        Legacy     = @((Join-Path $desk 'Fluxer (my instance).lnk'), (Join-Path $menu 'Fluxer (my instance).lnk'))
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

$UrlFlagPattern = '--fluxer-app-url=("[^"]*"|\S*)'

# Returns the argument string with exactly one --fluxer-app-url=<Url> (replacing the first, dropping extras, keeping all else).
# With -Url '' it strips the flag instead.
function Set-UrlFlag([string]$ArgString, [string]$Url) {
    $script:flagSeen = 0
    $flag = if ($Url) { "--fluxer-app-url=$Url" } else { '' }
    $new = [regex]::Replace($ArgString, $UrlFlagPattern, [System.Text.RegularExpressions.MatchEvaluator] {
        param($m)
        $script:flagSeen++
        if ($script:flagSeen -eq 1) { $flag } else { '' }
    })
    if ($flag -and $script:flagSeen -eq 0) { $new = "$new $flag" }
    ($new -replace '\s{2,}', ' ').Trim()
}

# 'ok' (exactly the wanted flag), 'official' (no flag), 'other' (a different or duplicated flag).
function Get-FlagState([string]$ArgString, [string]$Url) {
    $m = [regex]::Matches($ArgString, $UrlFlagPattern)
    if ($m.Count -eq 0) { return 'official' }
    if ($m.Count -eq 1 -and $m[0].Value -eq "--fluxer-app-url=$Url") { return 'ok' }
    'other'
}

function Get-LnkArguments([string]$Path) {
    (New-Object -ComObject WScript.Shell).CreateShortcut($Path).Arguments
}

# Saving through WScript.Shell keeps target, working folder, icon and the AppUserModelID/toast properties
# (checked on a copy of the real Fluxer.lnk), so only Arguments is assigned.
function Set-LnkArguments([string]$Path, [string]$ArgString) {
    $l = (New-Object -ComObject WScript.Shell).CreateShortcut($Path)
    $l.Arguments = $ArgString
    $l.Save()
}

# True for a shortcut an earlier version of this launcher made (it ran this script through PowerShell).
function Test-LegacyOwn([string]$Path) {
    if (-not (Test-Path $Path)) { return $false }
    $l = (New-Object -ComObject WScript.Shell).CreateShortcut($Path)
    ($l.TargetPath -eq $PowerShellExe) -and ($l.Arguments -match 'fluxer-instance-launcher\.ps1')
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

    # 3. Fluxer's own icons: make each existing one carry the flag
    foreach ($icon in $loc.Icons) {
        if (-not (Test-Path $icon.Path)) { continue }
        $cur = Get-LnkArguments $icon.Path
        if ((Get-FlagState $cur $cfg.Url) -ne 'ok') {
            $want = Set-UrlFlag $cur $cfg.Url
            $lnkPath = $icon.Path
            Invoke-Change "make the $($icon.Name) Fluxer icon open $($cfg.Url) ($lnkPath)" { Set-LnkArguments $lnkPath $want }
            $script:ChangeCount++
        }
    }

    # 3b. shortcuts of an earlier version of this launcher
    foreach ($old in $loc.Legacy) {
        if (Test-LegacyOwn $old) {
            Invoke-Change "delete the old launcher shortcut $old" { Remove-Item -Path $old -Force }
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
function Get-Cap([string]$t) { $t.Substring(0,1).ToUpper() + $t.Substring(1) }
function Join-Names([string[]]$Names) {
    if ($Names.Count -le 1) { return ($Names -join '') }
    ($Names[0..($Names.Count - 2)] -join ', ') + ' and ' + $Names[-1]
}

# Plain status: summary first, then dot points. Returns the number of problems (0 = all well).
function Show-StatusPlain($cfg, $loc) {
    if (-not (Test-Path $loc.FluxerExe)) {
        Write-Host 'Fluxer is not installed yet. Install Fluxer first, then open this setup again.' -ForegroundColor Red
        return 1
    }
    # Every thing this tool touches gets a line: kind is good, bad or note.
    $lines = New-Object System.Collections.Generic.List[object]
    $bad = 0
    function Add-Line([string]$kind, [string]$text) {
        $lines.Add([pscustomobject]@{ Kind = $kind; Text = $text })
        if ($kind -eq 'bad') { $script:statusBad++ }
    }
    $script:statusBad = 0

    $presentCount = 0
    foreach ($icon in $loc.Icons) {
        if (-not (Test-Path $icon.Path)) {
            Add-Line 'note' "$(Get-Cap $icon.Name) icon: not there, nothing to change."
            continue
        }
        $presentCount++
        switch (Get-FlagState (Get-LnkArguments $icon.Path) $cfg.Url) {
            'ok'       { Add-Line 'good' "$(Get-Cap $icon.Name) icon: opens your server." }
            'official' { Add-Line 'bad' "$(Get-Cap $icon.Name) icon: opens the official server." }
            default    { Add-Line 'bad' "$(Get-Cap $icon.Name) icon: opens a different server." }
        }
    }
    if ($presentCount -eq 0) { Add-Line 'bad' 'No Fluxer icon (Start Menu, Desktop or taskbar) was found. Open Fluxer once so it makes its icons, then pick Install.' }

    $runNow = Get-RegValue $loc.RunKey $RunValueName
    if ($cfg.Autostart) {
        if ($runNow -eq (Get-ExpectedRunValue $cfg)) { Add-Line 'good' 'Sign-in start: Fluxer opens on your server when you sign in to Windows.' }
        else { Add-Line 'bad' 'Sign-in start: not set up, so Fluxer will not open on your server when you sign in to Windows.' }
    } else {
        if ($null -eq $runNow) { Add-Line 'note' 'Sign-in start: off, as set in your settings.' }
        else { Add-Line 'bad' 'Sign-in start: switched off in your settings, but still on.' }
    }
    if ($null -eq (Get-RegValue $loc.RunKey $FluxerRunValueName)) { Add-Line 'good' "Fluxer's own sign-in start: off, so it will not open on the official server." }
    else { Add-Line 'bad' "Fluxer's own sign-in start: on, so Fluxer will open on the official server when you sign in to Windows." }

    if ($cfg.HandlerPatch) {
        $hNow = Get-RegValue $loc.HandlerKey '(default)'
        if ($null -ne $hNow -and $hNow -notmatch [regex]::Escape("--fluxer-app-url=$($cfg.Url)")) { Add-Line 'bad' 'fluxer:// links: do not use your server.' }
        else { Add-Line 'good' 'fluxer:// links: open on your server.' }
    } else {
        Add-Line 'note' 'fluxer:// links: left as Fluxer set them.'
    }
    if (@($loc.Legacy | Where-Object { Test-LegacyOwn $_ }).Count -gt 0) { Add-Line 'bad' 'Old shortcut made by an earlier version of this setup: still there.' }
    else { Add-Line 'good' 'Old shortcut made by an earlier version of this setup: none.' }
    Add-Line 'note' 'Nothing else is changed: no scheduled tasks, services or admin rights.'

    $bad = $script:statusBad
    if ($bad -eq 0) { Write-Host "Everything is working. Fluxer opens on your self-hosted server ($($cfg.Url))." -ForegroundColor Green }
    else { Write-Host 'Something needs fixing. Pick Install and it will be put right.' -ForegroundColor Red }
    foreach ($l in $lines) {
        $color = switch ($l.Kind) { 'good' { 'Green' } 'bad' { 'Red' } default { 'DarkGray' } }
        Write-Host "  - $($l.Text)" -ForegroundColor $color
    }
    return $bad
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
    foreach ($icon in $loc.Icons) {
        if (-not (Test-Path $icon.Path)) { continue }
        $cur = Get-LnkArguments $icon.Path
        if ((Get-FlagState $cur $cfg.Url) -ne 'official' -or $cur -match '--fluxer-app-url=') {
            $want = Set-UrlFlag $cur ''
            $lnkPath = $icon.Path
            Invoke-Change "take the server address off the $($icon.Name) Fluxer icon ($lnkPath)" { Set-LnkArguments $lnkPath $want }
        }
    }
    foreach ($old in $loc.Legacy) {
        if (Test-LegacyOwn $old) { Invoke-Change "delete the old launcher shortcut $old" { Remove-Item -Path $old -Force } }
    }
    $hNow = Get-RegValue $loc.HandlerKey '(default)'
    $exe = if ($hNow) { Get-HandlerExe $hNow } else { $null }
    if ($exe -and $hNow -match '--fluxer-app-url=') {
        $stock = '"{0}" "%1"' -f $exe
        Invoke-Change 'restore the stock fluxer:// handler' { Set-ItemProperty -Path $loc.HandlerKey -Name '(default)' -Value $stock }
    }
    Write-Host 'Uninstall done. Fluxer and its icons are still there and open the official server again; turn its own autostart on in its settings if you want it.'
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
            Write-Host '  - set up the Fluxer icons you already have (Start Menu, Desktop, taskbar) to open your server'
            if ($cfg.Autostart) { Write-Host '  - open Fluxer that way when you sign in to Windows' }
            Write-Host "  - turn off Fluxer's own start-up entry, so it does not open the official server"
            Write-Host 'Nothing needs administrator rights, and Uninstall undoes it all.'
            if (-not (Confirm-Yes 'Go ahead?')) { Write-Host 'Cancelled. Nothing was changed.'; return 0 }
            Sync-Entries $cfg $loc $false
            Write-Host 'Done. Open Fluxer from its normal Start Menu, Desktop or taskbar icon.'
            return 0
        }
        'Uninstall' {
            Write-Host 'Uninstall takes your server off the Fluxer icons and removes the sign-in entry this tool made. Fluxer itself is not touched.'
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
    'status'    { $code = if ((Show-StatusPlain $cfg $loc) -gt 0) { 1 } else { 0 } }
    'uninstall' { Remove-Entries $cfg $loc }
    'launch'    { $code = Start-Fluxer $cfg $loc }
}
if ($Action -ne 'repair' -or $script:ChangeCount -gt 0) { Write-Host ('Done in {0:N1}s (exit {1})' -f $sw.Elapsed.TotalSeconds, $code) }
exit $code
