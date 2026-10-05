#Requires -Version 5.1
# Pester 3 syntax (the version built into Windows PowerShell 5.1). Run: Invoke-Pester tests
# Every test points the launcher at a throwaway folder (-Root) and a throwaway registry key (-RegistryBase),
# so the real registry, Start Menu, Desktop and taskbar are never touched.
# The sandbox mirrors Fluxer's three icon locations: Desktop\Fluxer.lnk, StartMenu\Fluxer Platform AB\Fluxer.lnk, Taskbar\Fluxer.lnk.

# Test seam: no test may start a real update helper process.
$env:FLI_TEST_NO_SPAWN = '1'

$repo = Split-Path -Parent $PSScriptRoot
$script:Ps1 = Join-Path $repo 'scripts\fluxer-instance-launcher.ps1'
$script:Bat = Join-Path $repo 'scripts\Fluxer Instance Setup.bat'
$script:Flag = '--fluxer-app-url=https://chat.example.com'

function New-Sandbox {
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $dir = Join-Path $env:TEMP "fli-test-$id"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $reg = "HKCU:\Software\FluxerLauncherTest_$id"
    New-Item -Path $reg -Force | Out-Null
    $exe = Join-Path $dir 'FakeFluxer\Fluxer.exe'
    New-Item -ItemType Directory -Path (Split-Path -Parent $exe) -Force | Out-Null
    'x' | Set-Content $exe
    [pscustomobject]@{
        Dir = $dir; Reg = $reg; LogDir = (Join-Path $dir 'logs'); Config = (Join-Path $dir 'config.json'); Exe = $exe
        Desktop = (Join-Path $dir 'Desktop\Fluxer.lnk')
        Start   = (Join-Path $dir 'StartMenu\Fluxer Platform AB\Fluxer.lnk')
        Task    = (Join-Path $dir 'Taskbar\Fluxer.lnk')
        OldDesktop = (Join-Path $dir 'Desktop\Fluxer (my instance).lnk')
        OldStart   = (Join-Path $dir 'StartMenu\Fluxer (my instance).lnk')
    }
}

function Remove-Sandbox($sb) {
    Remove-Item -Recurse -Force $sb.Dir -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $sb.Reg -ErrorAction SilentlyContinue
}

function Set-TestConfig($sb, $url = 'https://chat.example.com', $autostart = $true) {
    $cfg = [ordered]@{ instance_url = $url; autostart = $autostart; autostart_delay_seconds = 15 }
    ($cfg | ConvertTo-Json) | Set-Content -Path $sb.Config -Encoding UTF8
}

function New-Lnk($path, $target, [string]$arguments = '', $workDir = $null) {
    New-Item -ItemType Directory -Path (Split-Path -Parent $path) -Force | Out-Null
    $l = (New-Object -ComObject WScript.Shell).CreateShortcut($path)
    $l.TargetPath = $target
    $l.Arguments = $arguments
    if ($workDir) { $l.WorkingDirectory = $workDir }
    $l.Save()
}

# Creates Fluxer's icons in the sandbox. $which: any of Desktop, Start, Task.
function New-FluxerIcons($sb, [string]$arguments = '', [string[]]$which = @('Desktop', 'Start', 'Task')) {
    foreach ($w in $which) { New-Lnk $sb.$w $sb.Exe $arguments (Split-Path -Parent $sb.Exe) }
}

# Runs the launcher in a child process; returns @{Code; Out}.
function Invoke-Launcher($sb, [string]$Action, [string[]]$Extra = @()) {
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Ps1, $Action,
        '-ConfigPath', $sb.Config, '-Root', $sb.Dir, '-RegistryBase', $sb.Reg, '-FluxerExe', $sb.Exe, '-LogDir', $sb.LogDir) + $Extra
    $out = & powershell.exe @args2 2>&1 | Out-String
    @{ Code = $LASTEXITCODE; Out = $out }
}

function Get-RunValue($sb, $name) {
    $k = Join-Path $sb.Reg 'Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path $k)) { return $null }
    (Get-ItemProperty -Path $k -Name $name -ErrorAction SilentlyContinue).$name
}
function Get-LnkArgs($path) {
    $l = (New-Object -ComObject WScript.Shell).CreateShortcut($path)
    @{ Target = $l.TargetPath; Args = $l.Arguments; WorkDir = $l.WorkingDirectory }
}
function Set-FluxerOwnRun($sb) {
    $k = Join-Path $sb.Reg 'Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $k -Force | Out-Null
    Set-ItemProperty -Path $k -Name 'Fluxer.Fluxer' -Value '"C:\FakeFluxer\Fluxer.exe"'
}
function Get-LauncherLnkCount($sb) {
    @(Get-ChildItem $sb.Dir -Recurse -Filter '*(my instance)*.lnk' -ErrorAction SilentlyContinue).Count
}

Describe 'fluxer-instance-launcher apply' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb
    $r = Invoke-Launcher $sb 'apply'

    It 'exits 0' { $r.Code | Should Be 0 }
    It 'writes the FluxerInstance Run value with launch, the script and the delay' {
        $v = Get-RunValue $sb 'FluxerInstance'
        $v | Should Not BeNullOrEmpty
        $v | Should Match 'launch'
        $v | Should Match 'fluxer-instance-launcher\.ps1'
        $v | Should Match '15'
    }
    It 'adds the flag to all three existing Fluxer icons and keeps their target and working folder' {
        foreach ($w in 'Desktop', 'Start', 'Task') {
            $a = Get-LnkArgs $sb.$w
            $a.Args | Should Be $script:Flag
            $a.Target | Should Be $sb.Exe
            $a.WorkDir | Should Be (Split-Path -Parent $sb.Exe)
        }
    }
    It 'creates no shortcut of its own' {
        Get-LauncherLnkCount $sb | Should Be 0
        @(Get-ChildItem $sb.Dir -Recurse -Filter *.lnk).Count | Should Be 3
    }
    Remove-Sandbox $sb
}

Describe 'apply only patches icons that exist' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb '' @('Start', 'Task')
    $r = Invoke-Launcher $sb 'apply'
    It 'does not create a Desktop icon' {
        $r.Code | Should Be 0
        Test-Path $sb.Desktop | Should Be $false
        (Get-LnkArgs $sb.Start).Args | Should Be $script:Flag
    }
    Remove-Sandbox $sb
}

Describe 'apply handles existing arguments' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-Lnk $sb.Desktop $sb.Exe '--fluxer-app-url=https://official.example --other-flag'
    New-Lnk $sb.Start $sb.Exe '--fluxer-app-url=https://chat.example.com'
    New-Lnk $sb.Task $sb.Exe '--keep-me'
    Invoke-Launcher $sb 'apply' | Out-Null
    It 'replaces a different url, keeping other arguments' {
        $a = (Get-LnkArgs $sb.Desktop).Args
        $a | Should Match '--other-flag'
        $a | Should Match '--fluxer-app-url=https://chat\.example\.com'
        $a | Should Not Match 'official'
    }
    It 'leaves a correct icon alone and adds the flag after other arguments' {
        (Get-LnkArgs $sb.Start).Args | Should Be $script:Flag
        $a = (Get-LnkArgs $sb.Task).Args
        $a | Should Match '--keep-me'
        $a | Should Match '--fluxer-app-url=https://chat\.example\.com'
    }
    It 'never leaves two url flags' {
        foreach ($w in 'Desktop', 'Start', 'Task') {
            ([regex]::Matches((Get-LnkArgs $sb.$w).Args, '--fluxer-app-url=')).Count | Should Be 1
        }
    }
    Remove-Sandbox $sb
}

Describe 'apply is idempotent' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb
    Invoke-Launcher $sb 'apply' | Out-Null
    $first = Get-RunValue $sb 'FluxerInstance'
    $r = Invoke-Launcher $sb 'apply'
    It 'second run exits 0, leaves the same value and says nothing changed' {
        $r.Code | Should Be 0
        Get-RunValue $sb 'FluxerInstance' | Should Be $first
        $r.Out | Should Match 'already in place'
        (Get-LnkArgs $sb.Start).Args | Should Be $script:Flag
    }
    Remove-Sandbox $sb
}

Describe 'apply removes the old own shortcuts of earlier versions' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    New-Lnk $sb.OldDesktop $ps ('-NoProfile -File "{0}" launch' -f $script:Ps1)
    New-Lnk $sb.OldStart $ps ('-NoProfile -File "{0}" launch' -f $script:Ps1)
    $mine = Join-Path $sb.Dir 'Desktop\Fluxer (my instance) 2.lnk'
    New-Lnk $mine $ps '-File "C:\somewhere\else.ps1"'
    Invoke-Launcher $sb 'apply' | Out-Null
    It 'deletes the old shortcuts that point at this script' {
        Test-Path $sb.OldDesktop | Should Be $false
        Test-Path $sb.OldStart | Should Be $false
    }
    It 'leaves a similar one that points elsewhere' {
        Test-Path $mine | Should Be $true
    }
    Remove-Sandbox $sb
}

Describe 'a legacy shortcut with the old name that targets something else is not ours' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb
    New-Lnk $sb.OldDesktop $sb.Exe ''
    Invoke-Launcher $sb 'apply' | Out-Null
    It 'is kept' { Test-Path $sb.OldDesktop | Should Be $true }
    Remove-Sandbox $sb
}

Describe 'apply removes Fluxer own autostart' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    $k = Join-Path $sb.Reg 'Microsoft\Windows\CurrentVersion\Run'
    New-Item -Path $k -Force | Out-Null
    Set-ItemProperty -Path $k -Name 'Fluxer.Fluxer' -Value '"C:\FakeFluxer\Fluxer.exe"'
    Set-ItemProperty -Path $k -Name 'SomethingElse' -Value 'keep-me'
    Invoke-Launcher $sb 'apply' | Out-Null
    It 'deletes Fluxer.Fluxer and leaves other values alone' {
        Get-RunValue $sb 'Fluxer.Fluxer' | Should BeNullOrEmpty
        Get-RunValue $sb 'SomethingElse' | Should Be 'keep-me'
    }
    Remove-Sandbox $sb
}

Describe 'autostart disabled in config' {
    $sb = New-Sandbox
    Set-TestConfig $sb 'https://chat.example.com' $false
    Invoke-Launcher $sb 'apply' | Out-Null
    It 'writes no FluxerInstance Run value' {
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
    }
    Remove-Sandbox $sb
}

Describe 'status' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb '' @('Start', 'Task')
    $before = Invoke-Launcher $sb 'status'
    Invoke-Launcher $sb 'apply' | Out-Null
    $after = Invoke-Launcher $sb 'status'
    It 'exits 1 before apply, leads with the summary and names the problems in plain words' {
        $before.Code | Should Be 1
        $before.Out.TrimStart() | Should Match '^Something needs fixing\. Pick Install and it will be put right\.'
        $before.Out | Should Match '  - Start Menu icon: opens the official server\.'
        $before.Out | Should Match '  - Taskbar icon: opens the official server\.'
        $before.Out | Should Match 'sign in to Windows'
        $before.Out | Should Not Match '\[good\]|\[problem\]|your address'
    }
    It 'exits 0 after apply with the exact good wording, listing only icons that exist' {
        $after.Code | Should Be 0
        $after.Out | Should Match 'Everything is working\. Fluxer opens on your self-hosted server \(https://chat\.example\.com\)\.'
        $after.Out | Should Match '  - Start Menu icon: opens your server\.'
        $after.Out | Should Match '  - Sign-in start: Fluxer opens on your server when you sign in to Windows\.'
        $after.Out | Should Match '  - Fluxer''s own sign-in start: off'
        $after.Out | Should Match '  - Desktop icon: not there, nothing to change\.'
    }
    It 'exits 1 if Fluxer re-added its own autostart' {
        Set-FluxerOwnRun $sb
        $r = Invoke-Launcher $sb 'status'
        $r.Code | Should Be 1
        $r.Out | Should Match 'own sign-in start: on'
    }
    It 'exits 1 if an icon was rewritten by a Fluxer update and lost the flag' {
        Remove-Item (Join-Path $sb.Reg 'Microsoft\Windows\CurrentVersion\Run') -Recurse -Force
        Invoke-Launcher $sb 'apply' | Out-Null
        New-Lnk $sb.Start $sb.Exe ''
        $r = Invoke-Launcher $sb 'status'
        $r.Code | Should Be 1
        $r.Out | Should Match 'Start Menu icon: opens the official server'
    }
    It 'says a different server when the flag points elsewhere' {
        New-Lnk $sb.Start $sb.Exe '--fluxer-app-url=https://other.example'
        (Invoke-Launcher $sb 'status').Out | Should Match 'Start Menu icon: opens a different server'
    }
    Remove-Sandbox $sb
}

Describe 'status when Fluxer is not installed or has no icons' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    Remove-Item $sb.Exe -Force
    $r = Invoke-Launcher $sb 'status'
    It 'says Fluxer is not installed as the summary and exits 1' {
        $r.Code | Should Be 1
        $r.Out.TrimStart() | Should Match '^Fluxer is not installed'
    }
    'x' | Set-Content $sb.Exe
    $r2 = Invoke-Launcher $sb 'status'
    It 'reports missing icons as a problem when Fluxer is installed' {
        $r2.Code | Should Be 1
        $r2.Out | Should Match 'No Fluxer icon'
    }
    Remove-Sandbox $sb
}

Describe 'repair' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb
    Invoke-Launcher $sb 'apply' | Out-Null
    Set-FluxerOwnRun $sb
    New-Lnk $sb.Desktop $sb.Exe ''
    $r = Invoke-Launcher $sb 'repair'
    It 'fixes drift: flag back, Fluxer.Fluxer gone, status green' {
        $r.Code | Should Be 0
        (Get-LnkArgs $sb.Desktop).Args | Should Be $script:Flag
        Get-RunValue $sb 'Fluxer.Fluxer' | Should BeNullOrEmpty
        (Invoke-Launcher $sb 'status').Code | Should Be 0
    }
    Remove-Sandbox $sb
}

Describe 'uninstall' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-Lnk $sb.Desktop $sb.Exe '--keep-me'
    New-Lnk $sb.Start $sb.Exe ''
    New-Lnk $sb.Task $sb.Exe '--fluxer-app-url=https://chat.example.com --also-keep'
    $ps = Join-Path $env:SystemRoot 'System32\WindowsPowerShell\v1.0\powershell.exe'
    New-Lnk $sb.OldStart $ps ('-File "{0}" launch' -f $script:Ps1)
    Invoke-Launcher $sb 'apply' | Out-Null
    $r = Invoke-Launcher $sb 'uninstall'
    It 'removes the Run value, the flag and any old own shortcut, but keeps the icons and other arguments' {
        $r.Code | Should Be 0
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
        (Get-LnkArgs $sb.Desktop).Args | Should Be '--keep-me'
        (Get-LnkArgs $sb.Start).Args | Should Be ''
        (Get-LnkArgs $sb.Task).Args | Should Be '--also-keep'
        Get-LauncherLnkCount $sb | Should Be 0
        (Get-LnkArgs $sb.Task).Target | Should Be $sb.Exe
    }
    Remove-Sandbox $sb
}

Describe 'URL validation' {
    $sb = New-Sandbox
    It 'refuses http' {
        Set-TestConfig $sb 'http://chat.example.com'
        (Invoke-Launcher $sb 'apply').Code | Should Be 2
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
    }
    It 'accepts http only with -AllowInsecure' {
        (Invoke-Launcher $sb 'apply' @('-AllowInsecure')).Code | Should Be 0
    }
    It 'refuses a URL with a quote or a space' {
        Set-TestConfig $sb 'https://chat.example.com/a" --evil'
        (Invoke-Launcher $sb 'apply').Code | Should Be 2
    }
    It 'refuses a URL with no host' {
        Set-TestConfig $sb 'https://'
        (Invoke-Launcher $sb 'apply').Code | Should Be 2
    }
    Remove-Sandbox $sb
}

Describe 'old config keys are ignored' {
    $sb = New-Sandbox
    '{"instance_url":"https://chat.example.com","shortcut_name":"Whatever","autostart":true,"unknown_key":1}' | Set-Content -Path $sb.Config -Encoding UTF8
    It 'still works with a config from an earlier version' {
        (Invoke-Launcher $sb 'apply').Code | Should Be 0
    }
    Remove-Sandbox $sb
}

Describe 'missing config is created from the embedded template, never from the example' {
    $sb = New-Sandbox
    $example = Join-Path $sb.Dir 'config.example.json'
    '{"instance_url":"https://fallback.example.com","autostart":false}' | Set-Content -Path $example -Encoding UTF8
    $r = Invoke-Launcher $sb 'apply'
    It 'exits 3, prints the path in plain words and writes the default settings' {
        $r.Code | Should Be 3
        $r.Out | Should Match 'Created your settings file at'
        $r.Out | Should Match 'run this again'
        Test-Path $sb.Config | Should Be $true
        $c = Get-Content -Raw $sb.Config | ConvertFrom-Json
        $c.instance_url | Should Be 'https://chat.codered.lol'
        $c.autostart | Should Be $true
        $c.autostart_delay_seconds | Should Be 15
    }
    It 'changes nothing else on that first run' {
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
    }
    It 'never mentions the fallback URL from the example file' {
        $r.Out | Should Not Match 'fallback\.example\.com'
    }
    It 'uses the created file on the next run' {
        (Invoke-Launcher $sb 'apply').Code | Should Be 0
        Get-RunValue $sb 'FluxerInstance' | Should Not BeNullOrEmpty
    }
    Remove-Sandbox $sb
}

Describe 'config.example.json is documentation only' {
    It 'no script mentions it, so no code path can read it' {
        (Get-Content -Raw $script:Ps1) | Should Not Match 'config\.example'
        (Get-Content -Raw $script:Bat) | Should Not Match 'config\.example'
    }
}

Describe 'launch' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    $r = Invoke-Launcher $sb 'launch' @('-DryRun')
    It 'dry run prints the exact command with --fluxer-app-url and does not start anything' {
        $r.Code | Should Be 0
        $r.Out | Should Match '--fluxer-app-url=https://chat\.example\.com'
    }
    Remove-Sandbox $sb
}

Describe 'dry run changes nothing' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb
    $r = Invoke-Launcher $sb 'apply' @('-DryRun')
    It 'apply -DryRun writes no value, leaves the icons alone and says what it would do' {
        $r.Code | Should Be 0
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
        (Get-LnkArgs $sb.Start).Args | Should Be ''
        $r.Out | Should Match '\[dry-run\] would: .*Start Menu'
    }
    Remove-Sandbox $sb
}

Describe 'no network code in the launcher' {
    $text = Get-Content -Raw $script:Ps1
    It 'contains none of the download or obfuscation primitives' {
        $text | Should Not Match 'Invoke-WebRequest|Invoke-RestMethod|Net\.WebClient|Start-BitsTransfer|FromBase64String|\biex\b|Invoke-Expression'
    }
}

Describe 'Fluxer Instance Setup.bat' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    $out = & $script:Bat --no-pause status -ConfigPath $sb.Config -Root $sb.Dir -RegistryBase $sb.Reg -FluxerExe $sb.Exe -LogDir $sb.LogDir 2>&1 | Out-String
    $code = $LASTEXITCODE
    It 'passes args through, prints a timing banner and returns the ps1 exit code' {
        $code | Should Be 1
        $out | Should Match 'Started'
        $out | Should Match 'Finished'
    }
    It 'keeps a blank line before the Finished line' {
        $out | Should Match '(?m)^\s*\r?\n\s*Finished '
    }
    It 'is named for what it does' {
        (Split-Path -Leaf $script:Bat) | Should Be 'Fluxer Instance Setup.bat'
        Test-Path (Join-Path (Split-Path -Parent $script:Bat) 'run.bat') | Should Be $false
    }
    Remove-Sandbox $sb
}

# Menu tests: FLI_TEST_KEYS feeds keys (Up, Down, Enter, Esc, Y, N) instead of the keyboard.
function Invoke-Menu($sb, [string]$Keys, [string[]]$Extra = @()) {
    $env:FLI_TEST_KEYS = $Keys
    try {
        $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Ps1,
            '-ConfigPath', $sb.Config, '-Root', $sb.Dir, '-RegistryBase', $sb.Reg, '-FluxerExe', $sb.Exe, '-LogDir', $sb.LogDir) + $Extra
        $out = & powershell.exe @args2 2>&1 | Out-String
        @{ Code = $LASTEXITCODE; Out = $out }
    } finally { Remove-Item Env:\FLI_TEST_KEYS -ErrorAction SilentlyContinue }
}

Describe 'menu' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb
    It 'shows the status first, then only Install, Uninstall and Quit' {
        $r = Invoke-Menu $sb 'Esc'
        $r.Code | Should Be 0
        $r.Out | Should Match 'Install'
        $r.Out | Should Match 'Uninstall'
        $r.Out | Should Match 'Quit'
        $r.Out | Should Match 'Something needs fixing'
        $r.Out | Should Not Match 'Repair|Launch|Dry'
    }
    It 'keeps a blank line between the status and the menu hint' {
        $r = Invoke-Menu $sb 'Esc'
        $r.Out | Should Match '\r?\n\s*\r?\nUse the arrow keys'
    }
    It 'Esc quits without changing anything' {
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
    }
    It 'Up from the top wraps to Quit and changes nothing' {
        $r = Invoke-Menu $sb 'Up,Enter'
        $r.Code | Should Be 0
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
    }
    It 'Install then N cancels and changes nothing' {
        $r = Invoke-Menu $sb 'Enter,N'
        $r.Out | Should Match 'Cancelled|cancelled|Nothing was changed'
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
        (Get-LnkArgs $sb.Start).Args | Should Be ''
    }
    It 'Install then Y applies and tells the user to use the normal icons' {
        $r = Invoke-Menu $sb 'Enter,Y'
        $r.Code | Should Be 0
        Get-RunValue $sb 'FluxerInstance' | Should Not BeNullOrEmpty
        (Get-LnkArgs $sb.Desktop).Args | Should Be $script:Flag
        $r.Out | Should Not Match 'my instance'
        $r.Out | Should Match '(?m)^  - made the Start Menu icon open https://chat\.example\.com'
        $r.Out | Should Match '(?m)^      \w:\\.*Fluxer\.lnk'
        $r.Out | Should Match 'Changes made:'
    }
    It 'the status shown above the menu reports good after install' {
        $r = Invoke-Menu $sb 'Esc'
        $r.Code | Should Be 0
        $r.Out | Should Match 'Everything is working\. Fluxer opens on your self-hosted server'
    }
    It 'Uninstall then Y reverses the install' {
        $r = Invoke-Menu $sb 'Down,Enter,Y'
        $r.Code | Should Be 0
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
        (Get-LnkArgs $sb.Desktop).Args | Should Be ''
    }
    It 'Install with -Yes skips the question' {
        $r = Invoke-Menu $sb 'Enter' @('-Yes')
        Get-RunValue $sb 'FluxerInstance' | Should Not BeNullOrEmpty
    }
    Remove-Sandbox $sb
}

Describe 'menu is not shown when an action is passed or stdin is redirected' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    It 'an action runs directly even if keys are available' {
        $env:FLI_TEST_KEYS = 'Esc'
        try { $r = Invoke-Launcher $sb 'status' } finally { Remove-Item Env:\FLI_TEST_KEYS -ErrorAction SilentlyContinue }
        $r.Out | Should Not Match 'Use the arrow keys'
    }
    It 'no action and redirected stdin prints the usage line instead of hanging' {
        $out = '' | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Ps1 -ConfigPath $sb.Config -Root $sb.Dir -RegistryBase $sb.Reg -LogDir $sb.LogDir 2>&1 | Out-String
        $LASTEXITCODE | Should Be 2
        $out | Should Match 'Usage'
    }
    Remove-Sandbox $sb
}

Describe 'per-run log' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb
    $dry = Invoke-Launcher $sb 'apply' @('-DryRun')
    $dryLogs = @(Get-ChildItem $sb.LogDir -Filter '*.log')
    $r = Invoke-Launcher $sb 'apply'
    $allLogs = @(Get-ChildItem $sb.LogDir -Filter '*.log')
    $applyLog = @($allLogs | Where-Object { $_.FullName -ne $dryLogs[0].FullName })[0]
    $text = if ($applyLog) { Get-Content -Raw $applyLog.FullName } else { '' }
    $dryText = Get-Content -Raw $dryLogs[0].FullName

    It 'creates exactly one log file per run, named with date, time and action' {
        $dryLogs.Count | Should Be 1
        $allLogs.Count | Should Be 2
        $dryLogs[0].Name | Should Match '^\d{4}-\d{2}-\d{2}_\d{2}-\d{2}-\d{2}_apply(_\d+)?\.log$'
    }
    It 'timestamps every line' {
        $lines = @($text -split "`r?`n" | Where-Object { $_ })
        $lines.Count | Should BeGreaterThan 3
        @($lines | Where-Object { $_ -notmatch '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2}\.\d{3} ' }).Count | Should Be 0
    }
    It 'logs the action, instance URL, exe path, changes and exit code' {
        $text | Should Match "action 'apply'"
        $text | Should Match 'instance URL: https://chat.example.com'
        $text | Should Match ([regex]::Escape($sb.Exe))
        $text | Should Match 'change: set Run value FluxerInstance'
        $text | Should Match ([regex]::Escape($sb.Desktop))
        $text | Should Match 'Arguments old'
        $text | Should Match 'exit code 0, duration'
    }
    It 'dry-run logs would lines and changes nothing' {
        $dryText | Should Match 'dry-run: would: set Run value FluxerInstance'
        $dryText | Should Not Match 'change done:'
    }
    It 'terminal output has no log mention' {
        $r.Out | Should Not Match '\.log'
    }
    Remove-Sandbox $sb
}

Describe 'logging failure never breaks a run' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb
    $blocker = Join-Path $sb.Dir 'iamafile'
    'x' | Set-Content $blocker
    $sb.LogDir = Join-Path $blocker 'logs'
    $r = Invoke-Launcher $sb 'status'
    It 'still exits normally and prints nothing about the log' {
        $r.Code | Should Be 1
        $r.Out | Should Match 'Something needs fixing'
        $r.Out | Should Not Match 'log'
        $r.Out | Should Not Match 'ERROR'
    }
    Remove-Sandbox $sb
}

Describe 'menu log does not repeat an unchanged status' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb
    [void](Invoke-Menu $sb 'Down,Up,Down,Up,Esc')
    $log = Get-Content -Raw (Get-ChildItem $sb.LogDir -Filter '*_menu.log')[0].FullName
    It 'logs each status line once however many keys were pressed' {
        ([regex]::Matches($log, 'status \(\w+\): Start Menu icon')).Count | Should Be 1
    }
    It 'still logs the menu choice' { $log | Should Match 'menu: choice Quit' }
    Remove-Sandbox $sb
}

# ---------- optional update watcher ----------
function Set-WatchConfig($sb, $watch) {
    $cfg = [ordered]@{ instance_url = 'https://chat.example.com'; autostart = $true; autostart_delay_seconds = 15; extra_key = 'keep-me' }
    if ($null -ne $watch) { $cfg['watch_updates'] = $watch }
    ($cfg | ConvertTo-Json) | Set-Content -Path $sb.Config -Encoding UTF8
}
function Get-ConfigJson($sb) { Get-Content -Raw $sb.Config | ConvertFrom-Json }

Describe 'watch_updates config' {
    $sb = New-Sandbox
    $r = Invoke-Launcher $sb 'apply'
    It 'is false in the embedded template and in config.example.json' {
        (Get-ConfigJson $sb).watch_updates | Should Be $false
        (Get-Content -Raw (Join-Path $repo 'config\config.example.json') | ConvertFrom-Json).watch_updates | Should Be $false
    }
    Remove-Sandbox $sb
}

Describe 'Run value form for watch off and on' {
    $sb = New-Sandbox
    Set-WatchConfig $sb $false
    New-FluxerIcons $sb
    Invoke-Launcher $sb 'apply' | Out-Null
    $off = Get-RunValue $sb 'FluxerInstance'
    Set-WatchConfig $sb $true
    Invoke-Launcher $sb 'apply' | Out-Null
    $on = Get-RunValue $sb 'FluxerInstance'
    It 'off runs launch, hidden' {
        $off | Should Match '-WindowStyle Hidden'
        $off | Should Match 'fluxer-instance-launcher\.ps1" launch -DelaySeconds 15'
    }
    It 'on runs watch, hidden' {
        $on | Should Match '-WindowStyle Hidden'
        $on | Should Match 'fluxer-instance-launcher\.ps1" watch -DelaySeconds 15'
    }
    It 'both forms start through conhost --headless so no console window shows (Windows Terminal ignores -WindowStyle Hidden)' {
        $off | Should Match '^"[^"]*conhost\.exe" --headless "[^"]*powershell\.exe" -NoProfile'
        $on | Should Match '^"[^"]*conhost\.exe" --headless "[^"]*powershell\.exe" -NoProfile'
    }
    Remove-Sandbox $sb
}

Describe 'status lines for the update watcher' {
    $sb = New-Sandbox
    Set-WatchConfig $sb $false
    New-FluxerIcons $sb
    Invoke-Launcher $sb 'apply' | Out-Null
    It 'shows no watcher line when it is off' {
        (Invoke-Launcher $sb 'status').Out | Should Not Match 'Update watcher'
    }
    It 'is bad when on in settings but the Run value is the plain form' {
        Set-WatchConfig $sb $true
        $r = Invoke-Launcher $sb 'status'
        $r.Code | Should Be 1
        $r.Out | Should Match 'Update watcher: on in your settings, but not set up'
    }
    It 'is good once applied' {
        Invoke-Launcher $sb 'apply' | Out-Null
        $r = Invoke-Launcher $sb 'status'
        $r.Code | Should Be 0
        $r.Out | Should Match '  - Update watcher: on, so updates will not undo your server\.'
    }
    Remove-Sandbox $sb
}

Describe 'install question for the update watcher' {
    $sb = New-Sandbox
    Set-WatchConfig $sb $null
    New-FluxerIcons $sb
    It 'is not asked when the menu Install is cancelled' {
        $r = Invoke-Menu $sb 'Enter,N,Y'
        $r.Out | Should Not Match 'background helper'
        (Get-ConfigJson $sb).PSObject.Properties['watch_updates'] | Should BeNullOrEmpty
    }
    It 'is asked after Y, on its own after a blank line, and N writes false keeping other keys' {
        $r = Invoke-Menu $sb 'Enter,Y,N'
        $r.Out | Should Match '(?m)^\s*\r?\nKeep Fluxer on your server after updates\? It uses a small background helper\. \(y/n\)'
        $c = Get-ConfigJson $sb
        $c.watch_updates | Should Be $false
        $c.extra_key | Should Be 'keep-me'
        $c.instance_url | Should Be 'https://chat.example.com'
        $r.Out | Should Match 'saved your update choice'
        (Get-RunValue $sb 'FluxerInstance') | Should Match ' launch '
    }
    It 'Y writes true and installs the watch form' {
        $r = Invoke-Menu $sb 'Enter,Y,Y'
        (Get-ConfigJson $sb).watch_updates | Should Be $true
        (Get-RunValue $sb 'FluxerInstance') | Should Match ' watch '
    }
    It 'never says everything is already in place under a Changes made list' {
        $r = Invoke-Menu $sb 'Enter,Y,Y'
        $r.Out | Should Match 'Changes made:'
        $r.Out | Should Not Match 'already in place'
    }
    It 'is not asked with -Yes, and keeps the config value' {
        $r = Invoke-Menu $sb 'Enter' @('-Yes')
        $r.Out | Should Not Match 'background helper'
        (Get-ConfigJson $sb).watch_updates | Should Be $true
    }
    It 'is not asked by the apply action' {
        $r = Invoke-Launcher $sb 'apply'
        $r.Out | Should Not Match 'background helper'
    }
    Remove-Sandbox $sb
}

Describe 'watch action' {
    $sb = New-Sandbox
    Set-WatchConfig $sb $true
    New-FluxerIcons $sb
    It 'dry run only says what it would do' {
        $r = Invoke-Launcher $sb 'watch' @('-DryRun')
        $r.Code | Should Be 0
        $r.Out | Should Match '--fluxer-app-url=https://chat\.example\.com'
        $r.Out | Should Match 'would'
    }
    It 'with the test hook and no change it times out cleanly' {
        $env:FLI_TEST_WATCH_ONCE = '2'
        try { $r = Invoke-Launcher $sb 'watch' } finally { Remove-Item Env:\FLI_TEST_WATCH_ONCE -ErrorAction SilentlyContinue }
        $r.Code | Should Be 0
        (Get-LnkArgs $sb.Start).Args | Should Be ''
    }
    It 'logs its pid at start and a stopped line when it ends' {
        $env:FLI_TEST_WATCH_ONCE = '2'
        try { $r = Invoke-Launcher $sb 'watch' } finally { Remove-Item Env:\FLI_TEST_WATCH_ONCE -ErrorAction SilentlyContinue }
        $text = Get-Content -Raw (Get-ChildItem $sb.LogDir -Filter '*_watch*.log' | Sort-Object LastWriteTime, Name | Select-Object -Last 1).FullName
        $text | Should Match 'watch: pid \d+'
        $text | Should Match 'watch: stopped'
    }
    It 'reports an earlier watcher log that ended without an exit line' {
        [void][System.IO.Directory]::CreateDirectory($sb.LogDir)
        $old = Join-Path $sb.LogDir '2000-01-01_00-00-00_watch.log'
        [System.IO.File]::WriteAllText($old, '2000-01-01 00:00:00.000 watch: pid 999999' + [Environment]::NewLine)
        $env:FLI_TEST_WATCH_ONCE = '2'
        try { $r = Invoke-Launcher $sb 'watch' } finally { Remove-Item Env:\FLI_TEST_WATCH_ONCE -ErrorAction SilentlyContinue }
        $text = Get-Content -Raw (Get-ChildItem $sb.LogDir -Filter '*_watch*.log' | Where-Object Name -ne '2000-01-01_00-00-00_watch.log' | Sort-Object LastWriteTime, Name | Select-Object -Last 1).FullName
        $text | Should Match 'previous watcher \(pid 999999.*without an exit line'
        Remove-Item $old -ErrorAction SilentlyContinue
    }
    It 'patches an icon an update rewrote and tries to close Fluxer on another server' {
        $env:FLI_TEST_WATCH_ONCE = '40'
        try {
            $a = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', ('"{0}"' -f $script:Ps1), 'watch', '-ConfigPath', ('"{0}"' -f $sb.Config), '-Root', ('"{0}"' -f $sb.Dir),
                '-RegistryBase', $sb.Reg, '-FluxerExe', ('"{0}"' -f $sb.Exe), '-LogDir', ('"{0}"' -f $sb.LogDir))
            $p = Start-Process -FilePath powershell.exe -ArgumentList $a -WindowStyle Hidden -PassThru
        } finally { Remove-Item Env:\FLI_TEST_WATCH_ONCE -ErrorAction SilentlyContinue }
        $ready = $false
        $log = $null
        for ($i = 0; $i -lt 60 -and -not $ready; $i++) {
            Start-Sleep -Milliseconds 500
            $log = Get-ChildItem $sb.LogDir -Filter '*_watch*.log' -ErrorAction SilentlyContinue | Sort-Object LastWriteTime | Select-Object -Last 1
            if ($log -and ((Get-Content -Raw $log.FullName) -match 'watch: waiting')) { $ready = $true }
        }
        $ready | Should Be $true
        New-Lnk $sb.Start $sb.Exe '' (Split-Path -Parent $sb.Exe)
        $p.WaitForExit(60000) | Should Be $true
        $p.ExitCode | Should Be 0
        (Get-LnkArgs $sb.Start).Args | Should Be $script:Flag
        $text = Get-Content -Raw $log.FullName
        $text | Should Match 'watch: icon change seen'
        $text | Should Match 'close: no Fluxer process open on another server'
    }
    Remove-Sandbox $sb
}

Describe 'uninstall stops only the watcher of this script' {
    $sb = New-Sandbox
    Set-WatchConfig $sb $true
    New-FluxerIcons $sb
    $copy = Join-Path $sb.Dir 'copy\fluxer-instance-launcher.ps1'
    New-Item -ItemType Directory -Path (Split-Path -Parent $copy) -Force | Out-Null
    Copy-Item $script:Ps1 $copy
    # decoys: one that looks like this script's watcher, one bystander
    $mine = Start-Process powershell.exe -ArgumentList '-NoProfile', '-Command', "Start-Sleep -Seconds 120 # $copy watch" -WindowStyle Hidden -PassThru
    $other = Start-Process powershell.exe -ArgumentList '-NoProfile', '-Command', 'Start-Sleep -Seconds 120 # unrelated' -WindowStyle Hidden -PassThru
    Start-Sleep -Seconds 2
    $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $copy uninstall -ConfigPath $sb.Config -Root $sb.Dir -RegistryBase $sb.Reg -FluxerExe $sb.Exe -LogDir $sb.LogDir 2>&1 | Out-String
    Start-Sleep -Seconds 1
    It 'stops the matching helper, leaves other processes, and says so in plain words' {
        $mine.HasExited | Should Be $true
        $other.HasExited | Should Be $false
        $out | Should Match 'stopped the background update helper'
    }
    if (-not $other.HasExited) { Stop-Process -Id $other.Id -Force }
    if (-not $mine.HasExited) { Stop-Process -Id $mine.Id -Force }
    Remove-Sandbox $sb
}

Describe 'a sandboxed uninstall never stops a watcher of the real script' {
    $sb = New-Sandbox
    Set-WatchConfig $sb $true
    New-FluxerIcons $sb
    # decoy carries the REAL script path plus ' watch', like the user's real hidden watcher, but no sandbox root
    $real = Start-Process powershell.exe -ArgumentList '-NoProfile', '-Command', "Start-Sleep -Seconds 120 # `"$script:Ps1`" watch -DelaySeconds 15" -WindowStyle Hidden -PassThru
    try {
        Start-Sleep -Seconds 2
        $r = Invoke-Launcher $sb 'uninstall'
        Start-Sleep -Seconds 1
        It 'leaves the decoy alive' {
            $real.HasExited | Should Be $false
        }
        It 'does not treat it as already running for apply' {
            Set-WatchConfig $sb $true
            $r2 = Invoke-Launcher $sb 'apply'
            (Get-ChildItem $sb.LogDir -Filter '*apply*.log' | Sort-Object LastWriteTime | Select-Object -Last 1 | Get-Content -Raw) | Should Not Match 'already running'
        }
    } finally { if (-not $real.HasExited) { Stop-Process -Id $real.Id -Force } }
    Remove-Sandbox $sb
}

Describe 'Install and apply start the update helper right away' {
    $sb = New-Sandbox
    New-FluxerIcons $sb
    $copy = Join-Path $sb.Dir 'copy\fluxer-instance-launcher.ps1'
    New-Item -ItemType Directory -Path (Split-Path -Parent $copy) -Force | Out-Null
    Copy-Item $script:Ps1 $copy
    function Get-LastLog($sb) { Get-Content -Raw (Get-ChildItem $sb.LogDir -Filter '*.log' | Sort-Object LastWriteTime, Name | Select-Object -Last 1).FullName }
    It 'is attempted by apply when watch_updates is on' {
        Set-WatchConfig $sb $true
        $r = Invoke-Launcher $sb 'apply'
        $r.Out | Should Match 'started the background update helper'
        (Get-LastLog $sb) | Should Match 'would start watcher'
    }
    It 'is attempted by the menu Install when the question is answered yes' {
        Set-WatchConfig $sb $null
        $r = Invoke-Menu $sb 'Enter,Y,Y'
        $r.Out | Should Match 'started the background update helper'
    }
    It 'is not attempted when watch_updates is off' {
        Set-WatchConfig $sb $false
        $r = Invoke-Launcher $sb 'apply'
        $r.Out | Should Not Match 'background update helper'
        (Get-LastLog $sb) | Should Not Match 'would start watcher'
        $r = Invoke-Menu $sb 'Enter,Y,N'
        $r.Out | Should Not Match 'background update helper'
    }
    It 'is not attempted under -DryRun' {
        Set-WatchConfig $sb $true
        $r = Invoke-Launcher $sb 'apply' @('-DryRun')
        $r.Out | Should Not Match 'started the background update helper'
        (Get-LastLog $sb) | Should Not Match 'would start watcher'
    }
    It 'is not attempted when a helper for this script already runs' {
        $mine = Start-Process powershell.exe -ArgumentList '-NoProfile', '-Command', "Start-Sleep -Seconds 120 # $copy watch" -WindowStyle Hidden -PassThru
        Start-Sleep -Seconds 2
        try {
            Set-WatchConfig $sb $true
            $out = & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $copy apply -ConfigPath $sb.Config -Root $sb.Dir -RegistryBase $sb.Reg -FluxerExe $sb.Exe -LogDir $sb.LogDir 2>&1 | Out-String
            $out | Should Not Match 'started the background update helper'
            (Get-LastLog $sb) | Should Match 'already running'
        } finally { if (-not $mine.HasExited) { Stop-Process -Id $mine.Id -Force } }
    }
    Remove-Sandbox $sb
}

# ---------- Uninstall undoes everything Install did (round trip) ----------
function Get-RunSnapshot($sb) {
    $k = Join-Path $sb.Reg 'Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path $k)) { return '' }
    $o = Get-Item $k
    ($o.GetValueNames() | Sort-Object | ForEach-Object { '{0}={1}|{2}' -f $_, $o.GetValue($_, $null, 'DoNotExpandEnvironmentNames'), $o.GetValueKind($_) }) -join "`n"
}
function Get-IconSnapshot($sb) { (@('Desktop', 'Start', 'Task') | ForEach-Object { "$_=" + (Get-LnkArgs $sb.$_).Args }) -join "`n" }
function Get-WatchSetting($sb) { $c = Get-Content -Raw $sb.Config | ConvertFrom-Json; [bool]$c.watch_updates }

Describe 'Install then Uninstall puts everything back as it was' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb
    Set-FluxerOwnRun $sb
    $k = Join-Path $sb.Reg 'Microsoft\Windows\CurrentVersion\Run'
    Set-ItemProperty -Path $k -Name 'SomethingElse' -Value 'keep-me'
    $runBefore = Get-RunSnapshot $sb
    $iconsBefore = Get-IconSnapshot $sb
    $watchBefore = Get-WatchSetting $sb
    $i = Invoke-Menu $sb 'Enter,Y,Y'
    $afterInstall = Get-RunSnapshot $sb
    $u = Invoke-Menu $sb 'Down,Enter,Y'
    It 'Install really changed things (the test is not vacuous)' {
        $afterInstall | Should Not Be $runBefore
        Get-WatchSetting $sb | Should Be $false
    }
    It 'restores the exact registry values, with FluxerInstance gone' {
        Get-RunSnapshot $sb | Should Be $runBefore
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
        Get-RunValue $sb 'Fluxer.Fluxer' | Should Be '"C:\FakeFluxer\Fluxer.exe"'
    }
    It 'restores every icon Arguments and the update choice' {
        Get-IconSnapshot $sb | Should Be $iconsBefore
        Get-WatchSetting $sb | Should Be $watchBefore
    }
    It 'says so in plain past tense in the done list' {
        $u.Out | Should Match 'turned Fluxer''s own sign-in start back on'
    }
    It 'status afterwards reports Fluxer''s own sign-in start as on, as a fact' {
        $r = Invoke-Launcher $sb 'status'
        $r.Out | Should Match '  - Fluxer''s own sign-in start: on\.'
        $r.Out | Should Not Match 'own sign-in start: off'
    }
    It 'a second Install and Uninstall still restores the first original' {
        Invoke-Menu $sb 'Enter,Y,Y' | Out-Null
        Get-RunValue $sb 'Fluxer.Fluxer' | Should BeNullOrEmpty
        Invoke-Menu $sb 'Down,Enter,Y' | Out-Null
        Get-RunSnapshot $sb | Should Be $runBefore
        Get-IconSnapshot $sb | Should Be $iconsBefore
    }
    Remove-Sandbox $sb
}

Describe 'saved original of Fluxer own sign-in start' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb
    Set-FluxerOwnRun $sb
    $state = Join-Path $sb.Dir 'data\state.json'
    Invoke-Launcher $sb 'apply' | Out-Null
    It 'is saved before the value is deleted' {
        Test-Path $state | Should Be $true
        (Get-Content -Raw $state) | Should Match 'FakeFluxer'
    }
    It 'is not overwritten by a later absent reading' {
        Invoke-Launcher $sb 'apply' | Out-Null
        (Get-Content -Raw $state) | Should Match 'FakeFluxer'
    }
    It 'is removed from the saved file once restored' {
        Invoke-Launcher $sb 'uninstall' | Out-Null
        Get-RunValue $sb 'Fluxer.Fluxer' | Should Be '"C:\FakeFluxer\Fluxer.exe"'
        (Get-Content -Raw $state) | Should Not Match 'FakeFluxer'
    }
    Remove-Sandbox $sb
}

Describe 'Uninstall with nothing saved never invents a value' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb
    Invoke-Launcher $sb 'apply' | Out-Null
    $r = Invoke-Launcher $sb 'uninstall'
    It 'leaves Fluxer.Fluxer absent and does not claim to have turned it on' {
        $r.Code | Should Be 0
        Get-RunValue $sb 'Fluxer.Fluxer' | Should BeNullOrEmpty
        $r.Out | Should Not Match 'sign-in start back on'
    }
    Remove-Sandbox $sb
}

Describe 'status wording for Fluxer own sign-in start' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    New-FluxerIcons $sb
    Set-FluxerOwnRun $sb
    It 'is a note, not a problem, while our sign-in start is not installed' {
        $r = Invoke-Launcher $sb 'status'
        $r.Out | Should Match '  - Fluxer''s own sign-in start: on\.'
    }
    It 'is a problem when our sign-in start is installed and Fluxer''s is on' {
        $k = Join-Path $sb.Reg 'Microsoft\Windows\CurrentVersion\Run'
        Set-ItemProperty -Path $k -Name 'FluxerInstance' -Value 'x'
        (Invoke-Launcher $sb 'status').Out | Should Match 'own sign-in start: on, so Fluxer will open on the official server'
    }
    Remove-Sandbox $sb
}

Describe 'the started helper does not open Fluxer, the sign-in Run value does' {
    $sb = New-Sandbox
    New-FluxerIcons $sb
    function Get-LastLog2($sb) { Get-Content -Raw (Get-ChildItem $sb.LogDir -Filter '*.log' | Sort-Object LastWriteTime, Name | Select-Object -Last 1).FullName }
    It 'Start-WatcherNow passes -NoLaunch to the helper it starts' {
        Set-WatchConfig $sb $true
        [void](Invoke-Launcher $sb 'apply')
        (Get-LastLog2 $sb) | Should Match 'would start watcher.*\bwatch -NoLaunch\b'
    }
    It 'Start-WatcherNow starts the helper through conhost --headless' {
        (Get-LastLog2 $sb) | Should Match 'would start watcher.*conhost\.exe --headless .*powershell\.exe'
    }
    It 'the sign-in Run value form has no -NoLaunch' {
        $v = Get-RunValue $sb 'FluxerInstance'
        $v | Should Match ' watch -DelaySeconds \d+$'
        $v | Should Not Match 'NoLaunch'
    }
    It 'watch -NoLaunch does not open Fluxer at start' {
        $env:FLI_TEST_WATCH_ONCE = '2'
        try { $r = Invoke-Launcher $sb 'watch' @('-NoLaunch') } finally { Remove-Item Env:\FLI_TEST_WATCH_ONCE -ErrorAction SilentlyContinue }
        $r.Code | Should Be 0
        (Get-LastLog2 $sb) | Should Match 'not opening Fluxer at start'
        (Get-LastLog2 $sb) | Should Not Match 'would open Fluxer'
    }
    It 'plain watch still opens Fluxer at start' {
        $env:FLI_TEST_WATCH_ONCE = '2'
        try { $r = Invoke-Launcher $sb 'watch' } finally { Remove-Item Env:\FLI_TEST_WATCH_ONCE -ErrorAction SilentlyContinue }
        $r.Code | Should Be 0
        (Get-LastLog2 $sb) | Should Match 'would open Fluxer at start'
        (Get-LastLog2 $sb) | Should Not Match 'not opening Fluxer'
    }
    Remove-Sandbox $sb
}
