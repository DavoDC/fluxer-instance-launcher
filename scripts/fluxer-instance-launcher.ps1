<#
.SYNOPSIS
  Starts the official Fluxer desktop app on your chosen instance and keeps it there after Fluxer updates.
.DESCRIPTION
  With no action it opens an arrow-key menu (shows your status, then Install, Uninstall, Quit) for people.
  Actions for scripts and tests: launch, apply, repair, status, uninstall. See README.md.
  Reads config\config.json; if it is missing, creates it from a template built into this script and exits 3.
  No network, no admin rights.
  Writes only: the HKCU Run value FluxerInstance, the --fluxer-app-url argument of Fluxer's own icons
  (Start Menu, Desktop, taskbar). It creates no shortcut of its own.
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
    [string]$LogDir,
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

# ---------- log (side channel only: never prints, never throws) ----------
$script:LogFile = $null
function Write-Log([string]$Message) {
    if (-not $script:LogFile) { return }
    try {
        $line = '{0} {1}' -f (Get-Date).ToString('yyyy-MM-dd HH:mm:ss.fff'), $Message
        [System.IO.File]::AppendAllText($script:LogFile, $line + [Environment]::NewLine, [System.Text.Encoding]::UTF8)
    } catch { }
}

function Initialize-Log {
    try {
        $dir = if ($LogDir) { $LogDir } else { Join-Path $PSScriptRoot '..\logs' }
        $dir = [System.IO.Path]::GetFullPath($dir)
        [void][System.IO.Directory]::CreateDirectory($dir)
        $name = if ($Action) { $Action } else { 'menu' }
        $stamp = (Get-Date).ToString('yyyy-MM-dd_HH-mm-ss')
        $file = Join-Path $dir "${stamp}_$name.log"
        $n = 2
        while (Test-Path -LiteralPath $file) { $file = Join-Path $dir "${stamp}_${name}_$n.log"; $n++ }
        [System.IO.File]::AppendAllText($file, '', [System.Text.Encoding]::UTF8)
        $script:LogFile = $file
    } catch { $script:LogFile = $null }
}

function Exit-Run([int]$Code) {
    Write-Log ('exit code {0}, duration {1:N3}s' -f $Code, $sw.Elapsed.TotalSeconds)
    exit $Code
}

trap {
    Write-Log "ERROR (unhandled): $($_.Exception.Message)"
    Write-Log "stack: $($_.ScriptStackTrace)"
    Write-Log "detail: $($_ | Out-String)"
    Write-Log ('exit code 1 (unhandled error), duration {0:N3}s' -f $sw.Elapsed.TotalSeconds)
    break
}

function Stop-WithError([string]$Message) {
    Write-Host "ERROR: $Message"
    Write-Log "ERROR: $Message"
    Exit-Run 2
}

# ---------- config ----------
$DefaultConfigJson = @'
{
  "instance_url": "https://chat.codered.lol",
  "autostart": true,
  "autostart_delay_seconds": 15,
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
            Write-Log "dry-run: would create config file $full from the built-in template"
        } else {
            New-Item -ItemType Directory -Path (Split-Path -Parent $full) -Force | Out-Null
            Set-Content -Path $full -Value $DefaultConfigJson -Encoding UTF8
            Write-Host "Created your settings file at $full. Open it, check the instance address, save, then run this again."
            Write-Log "created config file $full from the built-in template"
        }
        Exit-Run 3
    }
    Write-Log "config path: $([System.IO.Path]::GetFullPath($path))"
    try { $c = Get-Content -Raw -Path $path | ConvertFrom-Json } catch { Stop-WithError "Config is not valid JSON: $path" }
    $get = { param($n, $d) if ($null -ne $c.$n) { $c.$n } else { $d } }
    [pscustomobject]@{
        Url             = [string](& $get 'instance_url' '')
        Autostart       = [bool](& $get 'autostart' $true)
        AutostartDelay  = [int](& $get 'autostart_delay_seconds' 15)
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
    }
}

# ---------- helpers ----------
function Invoke-Change([string]$Description, [scriptblock]$Do, [string]$Done = '') {
    if ($DryRun) { Write-Host "[dry-run] would: $Description"; Write-Log "dry-run: would: $Description"; return }
    Write-Log "change: $Description"
    & $Do
    Write-Log "change done: $Description"
    $text = if ($Done) { $Done } else { $Description }
    if ($text -match '^(.*) \((\w:\\.*)\)$') {
        Write-Host "  - $($Matches[1])"
        Write-Host "      $($Matches[2])" -ForegroundColor DarkGray
    } else { Write-Host "  - $text" }
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

# ---------- apply / repair ----------
function Sync-Entries($cfg, $loc, [bool]$Quiet) {
    $changed = 0
    $before = $script:ChangeCount
    $script:ChangeCount = 0

    # 1. our Run value
    $runNow = Get-RegValue $loc.RunKey $RunValueName
    Write-Log "sync: Run key $($loc.RunKey), value $RunValueName currently: $(if ($null -eq $runNow) { '(not present)' } else { $runNow })"
    if ($cfg.Autostart) {
        $want = Get-ExpectedRunValue $cfg
        if ($runNow -eq $want) { Write-Log "sync: Run value $RunValueName already ok" }
        if ($runNow -ne $want) {
            Write-Log "sync: Run value $RunValueName needs change, new value: $want"
            # New-Item -Force on an existing key wipes its values, so create only when absent.
            Invoke-Change "set Run value $RunValueName" { if (-not (Test-Path $loc.RunKey)) { New-Item -Path $loc.RunKey -Force | Out-Null }; Set-ItemProperty -Path $loc.RunKey -Name $RunValueName -Value $want } 'set Fluxer to open on your server when you sign in to Windows'
            $script:ChangeCount++
        }
    } elseif ($null -eq $runNow) {
        Write-Log "sync: autostart off in config, Run value $RunValueName not present, ok"
    } elseif ($null -ne $runNow) {
        Invoke-Change "remove Run value $RunValueName (autostart is off in config)" { Remove-ItemProperty -Path $loc.RunKey -Name $RunValueName } 'removed the sign-in start, as your settings say'
        $script:ChangeCount++
    }

    # 2. Fluxer's own autostart value would start the official instance
    if ($null -ne (Get-RegValue $loc.RunKey $FluxerRunValueName)) {
        Invoke-Change "delete Fluxer's own Run value $FluxerRunValueName" { Remove-ItemProperty -Path $loc.RunKey -Name $FluxerRunValueName } 'turned off Fluxer''s own sign-in start'
        $script:ChangeCount++
    } else { Write-Log "sync: Fluxer's own Run value $FluxerRunValueName not present, ok" }

    # 3. Fluxer's own icons: make each existing one carry the flag
    foreach ($icon in $loc.Icons) {
        if (-not (Test-Path $icon.Path)) { Write-Log "sync: $($icon.Name) icon not present: $($icon.Path)"; continue }
        $cur = Get-LnkArguments $icon.Path
        $state = Get-FlagState $cur $cfg.Url
        Write-Log "sync: $($icon.Name) icon $($icon.Path) state $state, Arguments: '$cur'"
        if ($state -ne 'ok') {
            $want = Set-UrlFlag $cur $cfg.Url
            Write-Log "sync: $($icon.Name) icon needs change, Arguments old: '$cur' new: '$want'"
            $lnkPath = $icon.Path
            Invoke-Change "make the $($icon.Name) Fluxer icon open $($cfg.Url) ($lnkPath)" { Set-LnkArguments $lnkPath $want } "made the $($icon.Name) icon open $($cfg.Url) ($lnkPath)"
            $script:ChangeCount++
        }
    }

    # 3b. shortcuts of an earlier version of this launcher
    foreach ($old in $loc.Legacy) {
        if (Test-LegacyOwn $old) {
            Invoke-Change "delete the old launcher shortcut $old" { Remove-Item -Path $old -Force } "deleted the old shortcut ($old)"
            $script:ChangeCount++
        } else { Write-Log "sync: no legacy launcher shortcut at $old" }
    }

    Write-Log "sync: $($script:ChangeCount) change(s) needed or made (quiet=$Quiet)"
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
        Write-Log "status: Fluxer exe not found at $($loc.FluxerExe)"
        Write-Host 'Fluxer is not installed yet. Install Fluxer first, then open this setup again.' -ForegroundColor Red
        return 1
    }
    # Every thing this tool touches gets a line: kind is good, bad or note.
    $lines = New-Object System.Collections.Generic.List[object]
    $logBuf = New-Object System.Collections.Generic.List[string]
    $bad = 0
    function Add-Line([string]$kind, [string]$text) {
        $lines.Add([pscustomobject]@{ Kind = $kind; Text = $text })
        $logBuf.Add("status ($kind): $text")
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

    if (@($loc.Legacy | Where-Object { Test-LegacyOwn $_ }).Count -gt 0) { Add-Line 'bad' 'Old shortcut made by an earlier version of this setup: still there.' }

    $bad = $script:statusBad
    # The menu redraws the status on every key press; log it only when it differs from the last one logged.
    $block = $logBuf -join "`n"
    if ($block -ne $script:LastStatusLogged) { foreach ($entry in $logBuf) { Write-Log $entry }; $script:LastStatusLogged = $block }
    if ($bad -eq 0) { Write-Host "Everything is working. Fluxer opens on your self-hosted server ($($cfg.Url))." -ForegroundColor Green }
    else { Write-Host 'Something needs fixing. Pick Install and it will be put right.' -ForegroundColor Red }
    foreach ($l in $lines) {
        $color = switch ($l.Kind) { 'good' { 'Green' } 'bad' { 'Red' } default { 'DarkGray' } }
        Write-Host "  - $($l.Text)" -ForegroundColor $color
    }
    return $bad
}
# ---------- launch ----------
# Install closes a Fluxer that is open on another server, so its next start uses the new icons.
function Get-FluxerNotOnServer($cfg, $loc) {
    try {
        $all = @(Get-CimInstance Win32_Process -Filter "Name='Fluxer.exe'" | Where-Object { $_.ExecutablePath -eq $loc.FluxerExe })
    } catch { return @() }
    $main = @($all | Where-Object { $_.CommandLine -and $_.CommandLine -notmatch '--type=' })
    if (@($main | Where-Object { $_.CommandLine -notmatch [regex]::Escape("--fluxer-app-url=$($cfg.Url)") }).Count -eq 0) { return @() }
    return $all
}

function Stop-FluxerNotOnServer($cfg, $loc) {
    $procs = @(Get-FluxerNotOnServer $cfg $loc)
    if ($procs.Count -eq 0) { Write-Log 'close: no Fluxer process open on another server'; return }
    foreach ($p in $procs) { Write-Log "close: Fluxer process PID $($p.ProcessId), path $($p.ExecutablePath), command line: $($p.CommandLine)" }
    Invoke-Change 'close Fluxer, which was open on another server' { $procs | ForEach-Object { Stop-Process -Id $_.ProcessId -Force -ErrorAction SilentlyContinue } } 'closed Fluxer, which was open on another server'
}

function Get-MainFluxerProcess {
    try {
        Get-CimInstance Win32_Process -Filter "Name='Fluxer.exe'" |
            Where-Object { $_.CommandLine -and $_.CommandLine -notmatch '--type=' }
    } catch { @() }
}

function Start-Fluxer($cfg, $loc) {
    $flag = "--fluxer-app-url=$($cfg.Url)"
    if ($DelaySeconds -gt 0 -and -not $DryRun) { Write-Host "Waiting $DelaySeconds s before launch"; Start-Sleep -Seconds $DelaySeconds }
    if ($DryRun) { Write-Host "[dry-run] would run: `"$($loc.FluxerExe)`" $flag"; Write-Log "dry-run: would run: `"$($loc.FluxerExe)`" $flag"; return 0 }
    if (-not (Test-Path $loc.FluxerExe)) { Write-Log "ERROR: Fluxer not found at $($loc.FluxerExe)"; Write-Host "ERROR: Fluxer not found at $($loc.FluxerExe). Install Fluxer first."; return 2 }
    $main = @(Get-MainFluxerProcess)
    foreach ($p in $main) { Write-Log "launch: Fluxer process found, PID $($p.ProcessId), path $($p.ExecutablePath), command line: $($p.CommandLine)" }
    if ($main.Count -gt 0) {
        if ($main[0].CommandLine -match [regex]::Escape($flag)) { Write-Host 'Fluxer is already running on your instance.'; return 0 }
        if (-not $ForceRestart) {
            Write-Host 'Fluxer is already running on another instance, and a second launch cannot change that. Quit Fluxer (tray icon too) and run launch again, or add -ForceRestart.'
            return 3
        }
        Write-Host 'Stopping the running Fluxer (-ForceRestart)'
        foreach ($p in @(Get-Process -Name Fluxer -ErrorAction SilentlyContinue)) { Write-Log "launch: closing Fluxer process PID $($p.Id), path $($p.Path)" }
        Get-Process -Name Fluxer -ErrorAction SilentlyContinue | Stop-Process -Force
        Start-Sleep -Seconds 2
    }
    Write-Log "launch: running `"$($loc.FluxerExe)`" $flag"
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
    Write-Host ''
    Write-Host 'Uninstall done:'
    if ($null -ne (Get-RegValue $loc.RunKey $RunValueName)) {
        Invoke-Change "remove Run value $RunValueName" { Remove-ItemProperty -Path $loc.RunKey -Name $RunValueName } 'removed the sign-in start'
    } else { Write-Log "uninstall: Run value $RunValueName not present in $($loc.RunKey)" }
    foreach ($icon in $loc.Icons) {
        if (-not (Test-Path $icon.Path)) { Write-Log "uninstall: $($icon.Name) icon not present: $($icon.Path)"; continue }
        $cur = Get-LnkArguments $icon.Path
        Write-Log "uninstall: $($icon.Name) icon $($icon.Path), Arguments: '$cur'"
        if ((Get-FlagState $cur $cfg.Url) -ne 'official' -or $cur -match '--fluxer-app-url=') {
            $want = Set-UrlFlag $cur ''
            Write-Log "uninstall: $($icon.Name) icon needs change, Arguments old: '$cur' new: '$want'"
            $lnkPath = $icon.Path
            Invoke-Change "take the server address off the $($icon.Name) Fluxer icon ($lnkPath)" { Set-LnkArguments $lnkPath $want } "took your server off the $($icon.Name) icon ($lnkPath)"
        }
    }
    foreach ($old in $loc.Legacy) {
        if (Test-LegacyOwn $old) { Invoke-Change "delete the old launcher shortcut $old" { Remove-Item -Path $old -Force } "deleted the old shortcut ($old)" }
    }
    Write-Host ''
    Write-Host 'Fluxer is untouched and opens the official server again.'
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
    if ($Yes) { Write-Log "menu: '$Question' auto-confirmed by -Yes"; return $true }
    Write-Host "$Question (y/n)"
    while ($true) {
        $k = Read-KeyCode
        if ($k -eq 89) { Write-Log "menu: '$Question' answered y"; return $true }
        if ($k -eq 78 -or $k -eq 27) { Write-Log "menu: '$Question' answered n"; return $false }
    }
}

function Invoke-Menu($cfg, $loc) {
    $script:MenuCfg = $cfg
    $script:MenuLoc = $loc
    $choice = Read-Menu
    Write-Log "menu: choice $(if ($null -eq $choice) { 'Quit (Esc)' } else { $choice })"
    if ($null -eq $choice -or $choice -eq 'Quit') { return 0 }
    Write-Host ''
    switch ($choice) {
        'Install' {
            Write-Host 'Install will:'
            Write-Host "  - make the Fluxer icons you already have (Start Menu, Desktop, taskbar) open $($cfg.Url)"
            if ($cfg.Autostart) { Write-Host '  - open Fluxer on your server when you sign in to Windows' }
            Write-Host "  - turn off Fluxer's own sign-in start, so it does not open the official server"
            if (@(Get-FluxerNotOnServer $cfg $loc).Count -gt 0) { Write-Host '  - close Fluxer, which is open on another server, so it opens on yours next time' }
            if (@($loc.Legacy | Where-Object { Test-LegacyOwn $_ }).Count -gt 0) { Write-Host '  - delete the old shortcut an earlier version of this setup made' }
            Write-Host 'It needs no administrator rights, creates no scheduled tasks, and Uninstall undoes it all.'
            Write-Host ''
            if (-not (Confirm-Yes 'Go ahead?')) { Write-Host 'Cancelled. Nothing was changed.'; return 0 }
            Write-Host ''
            Write-Host 'Changes made:'
            Sync-Entries $cfg $loc $false
            Stop-FluxerNotOnServer $cfg $loc
            Write-Host ''
            Write-Host 'Done. Open Fluxer from its normal Start Menu or taskbar icon.'
            return 0
        }
        'Uninstall' {
            Write-Host 'Uninstall takes your server off the Fluxer icons and removes the sign-in start this tool made. Fluxer itself is not touched.'
            Write-Host ''
            if (-not (Confirm-Yes 'Go ahead?')) { Write-Host 'Cancelled. Nothing was changed.'; return 0 }
            Remove-Entries $cfg $loc
            return 0
        }
    }
    return 0
}

# ---------- main ----------
$script:ChangeCount = 0
Initialize-Log
Write-Log ("run start: action '{0}', arguments: {1}" -f $(if ($Action) { $Action } else { 'menu' }), (($PSBoundParameters.GetEnumerator() | ForEach-Object { "-$($_.Key) $($_.Value)" }) -join ' '))
Write-Log "script: $ScriptPath, PowerShell $($PSVersionTable.PSVersion), user $env:USERNAME"
if ($Action -eq '' -and $null -eq $env:FLI_TEST_KEYS -and [Console]::IsInputRedirected) {
    Write-Host 'Usage: run "Fluxer Instance Setup.bat" with no arguments for the menu, or pass an action: launch, apply, repair, status, uninstall (options: -DryRun, -Yes).'
    Write-Log 'ERROR: no action and input is redirected, printed usage'
    Exit-Run 2
}
$cfg = Get-Config
Write-Log "instance URL: $($cfg.Url), autostart: $($cfg.Autostart), autostart delay: $($cfg.AutostartDelay)s, repair after launch: $($cfg.RepairAfterSecs)s"
if ($Action -ne 'uninstall') {
    $err = Test-InstanceUrl $cfg.Url
    if ($err) { Stop-WithError $err }
}
$loc = Get-Locations
Write-Log "Fluxer exe: $($loc.FluxerExe) (exists: $(Test-Path $loc.FluxerExe)), Run key: $($loc.RunKey)"
if ($DryRun) { Write-Host '(dry run: nothing will be changed)'; Write-Log 'dry run: nothing will be changed' }
$code = 0
if ($Action -eq '') {
    $code = Invoke-Menu $cfg $loc
    Exit-Run $code
}
switch ($Action) {
    'apply'     { Sync-Entries $cfg $loc $false }
    'repair'    { Sync-Entries $cfg $loc $true }
    'status'    { $code = if ((Show-StatusPlain $cfg $loc) -gt 0) { 1 } else { 0 } }
    'uninstall' { Remove-Entries $cfg $loc }
    'launch'    { $code = Start-Fluxer $cfg $loc }
}
if ($Action -ne 'repair' -or $script:ChangeCount -gt 0) { Write-Host ('Done in {0:N1}s (exit {1})' -f $sw.Elapsed.TotalSeconds, $code) }
Exit-Run $code
