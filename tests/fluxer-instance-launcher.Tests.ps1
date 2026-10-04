#Requires -Version 5.1
# Pester 3 syntax (the version built into Windows PowerShell 5.1). Run: Invoke-Pester tests
# Every test points the launcher at a throwaway folder (-Root) and a throwaway registry key (-RegistryBase),
# so the real registry, Start Menu and Desktop are never touched.

$repo = Split-Path -Parent $PSScriptRoot
$script:Ps1 = Join-Path $repo 'scripts\fluxer-instance-launcher.ps1'
$script:Bat = Join-Path $repo 'scripts\Fluxer Instance Setup.bat'

function New-Sandbox {
    $id = [guid]::NewGuid().ToString('N').Substring(0, 8)
    $dir = Join-Path $env:TEMP "fli-test-$id"
    New-Item -ItemType Directory -Path $dir -Force | Out-Null
    $reg = "HKCU:\Software\FluxerLauncherTest_$id"
    New-Item -Path $reg -Force | Out-Null
    [pscustomobject]@{ Dir = $dir; Reg = $reg; Config = (Join-Path $dir 'config.json') }
}

function Remove-Sandbox($sb) {
    Remove-Item -Recurse -Force $sb.Dir -ErrorAction SilentlyContinue
    Remove-Item -Recurse -Force $sb.Reg -ErrorAction SilentlyContinue
}

function Set-TestConfig($sb, $url = 'https://chat.example.com', $autostart = $true, $handler = $false) {
    $cfg = [ordered]@{ instance_url = $url; autostart = $autostart; autostart_delay_seconds = 15; handler_patch = $handler }
    ($cfg | ConvertTo-Json) | Set-Content -Path $sb.Config -Encoding UTF8
}

# Runs the launcher in a child process; returns @{Code; Out}.
function Invoke-Launcher($sb, [string]$Action, [string[]]$Extra = @()) {
    $args2 = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-File', $script:Ps1, $Action,
        '-ConfigPath', $sb.Config, '-Root', $sb.Dir, '-RegistryBase', $sb.Reg) + $Extra
    $out = & powershell.exe @args2 2>&1 | Out-String
    @{ Code = $LASTEXITCODE; Out = $out }
}

function Get-RunValue($sb, $name) {
    $k = Join-Path $sb.Reg 'Microsoft\Windows\CurrentVersion\Run'
    if (-not (Test-Path $k)) { return $null }
    (Get-ItemProperty -Path $k -Name $name -ErrorAction SilentlyContinue).$name
}
function Get-HandlerValue($sb) {
    $k = Join-Path $sb.Reg 'Classes\fluxer\shell\open\command'
    if (-not (Test-Path $k)) { return $null }
    (Get-ItemProperty -Path $k).'(default)'
}
function Set-StockHandler($sb) {
    $k = Join-Path $sb.Reg 'Classes\fluxer\shell\open\command'
    New-Item -Path $k -Force | Out-Null
    Set-ItemProperty -Path $k -Name '(default)' -Value '"C:\FakeFluxer\Fluxer.exe" "%1"'
}
function Get-LnkArgs($path) {
    $sh = New-Object -ComObject WScript.Shell
    $l = $sh.CreateShortcut($path)
    @{ Target = $l.TargetPath; Args = $l.Arguments }
}

Describe 'fluxer-instance-launcher apply' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    $r = Invoke-Launcher $sb 'apply'

    It 'exits 0' { $r.Code | Should Be 0 }
    It 'writes the FluxerInstance Run value with launch, the script and the delay' {
        $v = Get-RunValue $sb 'FluxerInstance'
        $v | Should Not BeNullOrEmpty
        $v | Should Match 'launch'
        $v | Should Match 'fluxer-instance-launcher\.ps1'
        $v | Should Match '15'
    }
    It 'creates its own shortcut on the Desktop and in the Start Menu' {
        $d = Get-ChildItem (Join-Path $sb.Dir 'Desktop') -Filter *.lnk
        $s = Get-ChildItem (Join-Path $sb.Dir 'StartMenu') -Filter *.lnk
        @($d).Count | Should Be 1
        @($s).Count | Should Be 1
        $d[0].Name | Should Not Be 'Fluxer.lnk'
        (Get-LnkArgs $d[0].FullName).Args | Should Match 'launch'
    }
    It 'does not touch the fluxer:// handler when handler_patch is false' {
        Get-HandlerValue $sb | Should BeNullOrEmpty
    }
    Remove-Sandbox $sb
}

Describe 'apply is idempotent' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    Invoke-Launcher $sb 'apply' | Out-Null
    $first = Get-RunValue $sb 'FluxerInstance'
    $r = Invoke-Launcher $sb 'apply'
    It 'second run exits 0 and leaves the same value' {
        $r.Code | Should Be 0
        Get-RunValue $sb 'FluxerInstance' | Should Be $first
    }
    It 'still has exactly one shortcut per folder' {
        @(Get-ChildItem (Join-Path $sb.Dir 'Desktop') -Filter *.lnk).Count | Should Be 1
    }
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

Describe 'handler patch is opt-in' {
    $sb = New-Sandbox
    Set-TestConfig $sb 'https://chat.example.com' $true $true
    Set-StockHandler $sb
    Invoke-Launcher $sb 'apply' | Out-Null
    It 'adds the flag and keeps "%1" quoted when enabled' {
        $h = Get-HandlerValue $sb
        $h | Should Match '--fluxer-app-url=https://chat\.example\.com'
        $h | Should Match '"%1"$'
    }
    It 'uninstall restores the stock handler' {
        Invoke-Launcher $sb 'uninstall' | Out-Null
        Get-HandlerValue $sb | Should Be '"C:\FakeFluxer\Fluxer.exe" "%1"'
    }
    Remove-Sandbox $sb
}

Describe 'status' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    $before = Invoke-Launcher $sb 'status'
    Invoke-Launcher $sb 'apply' | Out-Null
    $after = Invoke-Launcher $sb 'status'
    It 'exits 1 before apply and names the missing entries' {
        $before.Code | Should Be 1
        $before.Out | Should Match 'FluxerInstance'
    }
    It 'exits 0 after apply' { $after.Code | Should Be 0 }
    It 'exits 1 if Fluxer re-added its own autostart' {
        $k = Join-Path $sb.Reg 'Microsoft\Windows\CurrentVersion\Run'
        Set-ItemProperty -Path $k -Name 'Fluxer.Fluxer' -Value '"C:\FakeFluxer\Fluxer.exe"'
        (Invoke-Launcher $sb 'status').Code | Should Be 1
    }
    Remove-Sandbox $sb
}

Describe 'repair' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    Invoke-Launcher $sb 'apply' | Out-Null
    $k = Join-Path $sb.Reg 'Microsoft\Windows\CurrentVersion\Run'
    Set-ItemProperty -Path $k -Name 'Fluxer.Fluxer' -Value '"C:\FakeFluxer\Fluxer.exe"'
    Remove-Item (Join-Path $sb.Dir 'Desktop\*.lnk') -Force
    $r = Invoke-Launcher $sb 'repair'
    It 'fixes drift: shortcut back, Fluxer.Fluxer gone, status green' {
        $r.Code | Should Be 0
        @(Get-ChildItem (Join-Path $sb.Dir 'Desktop') -Filter *.lnk).Count | Should Be 1
        Get-RunValue $sb 'Fluxer.Fluxer' | Should BeNullOrEmpty
        (Invoke-Launcher $sb 'status').Code | Should Be 0
    }
    Remove-Sandbox $sb
}

Describe 'uninstall' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    Invoke-Launcher $sb 'apply' | Out-Null
    $r = Invoke-Launcher $sb 'uninstall'
    It 'removes the Run value and both shortcuts' {
        $r.Code | Should Be 0
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
        @(Get-ChildItem (Join-Path $sb.Dir 'Desktop') -Filter *.lnk -ErrorAction SilentlyContinue).Count | Should Be 0
        @(Get-ChildItem (Join-Path $sb.Dir 'StartMenu') -Filter *.lnk -ErrorAction SilentlyContinue).Count | Should Be 0
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
        $c.handler_patch | Should Be $false
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
    $r = Invoke-Launcher $sb 'apply' @('-DryRun')
    It 'apply -DryRun writes no value and no shortcut' {
        $r.Code | Should Be 0
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
        @(Get-ChildItem (Join-Path $sb.Dir 'Desktop') -Filter *.lnk -ErrorAction SilentlyContinue).Count | Should Be 0
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
    $out = & $script:Bat --no-pause status -ConfigPath $sb.Config -Root $sb.Dir -RegistryBase $sb.Reg 2>&1 | Out-String
    $code = $LASTEXITCODE
    It 'passes args through, prints a timing banner and returns the ps1 exit code' {
        $code | Should Be 1
        $out | Should Match 'Started'
        $out | Should Match 'Finished'
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
            '-ConfigPath', $sb.Config, '-Root', $sb.Dir, '-RegistryBase', $sb.Reg) + $Extra
        $out = & powershell.exe @args2 2>&1 | Out-String
        @{ Code = $LASTEXITCODE; Out = $out }
    } finally { Remove-Item Env:\FLI_TEST_KEYS -ErrorAction SilentlyContinue }
}

Describe 'menu' {
    $sb = New-Sandbox
    Set-TestConfig $sb
    It 'shows only Install, Uninstall and Status' {
        $r = Invoke-Menu $sb 'Esc'
        $r.Code | Should Be 0
        $r.Out | Should Match 'Install'
        $r.Out | Should Match 'Uninstall'
        $r.Out | Should Match 'Status'
        $r.Out | Should Not Match 'Repair|Launch|Dry'
    }
    It 'Esc quits without changing anything' {
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
    }
    It 'Down wraps and Up moves back: Status is reachable with Up from the top' {
        $r = Invoke-Menu $sb 'Up,Enter'
        $r.Out | Should Match 'working|problem|Fluxer is'
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
    }
    It 'Install then N cancels and changes nothing' {
        $r = Invoke-Menu $sb 'Enter,N'
        $r.Out | Should Match 'Cancelled|cancelled|Nothing was changed'
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
    }
    It 'Install then Y applies' {
        $r = Invoke-Menu $sb 'Enter,Y'
        $r.Code | Should Be 0
        Get-RunValue $sb 'FluxerInstance' | Should Not BeNullOrEmpty
        @(Get-ChildItem (Join-Path $sb.Dir 'Desktop') -Filter *.lnk).Count | Should Be 1
    }
    It 'Status in plain words reports good after install' {
        $fake = Join-Path $sb.Dir 'Fluxer.exe'
        'x' | Set-Content $fake
        $r = Invoke-Menu $sb 'Up,Enter' @('-FluxerExe', $fake)
        $r.Code | Should Be 0
        $r.Out | Should Match 'Everything is working'
    }
    It 'Uninstall then Y reverses the install' {
        $r = Invoke-Menu $sb 'Down,Enter,Y'
        $r.Code | Should Be 0
        Get-RunValue $sb 'FluxerInstance' | Should BeNullOrEmpty
        @(Get-ChildItem (Join-Path $sb.Dir 'Desktop') -Filter *.lnk -ErrorAction SilentlyContinue).Count | Should Be 0
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
        $out = '' | & powershell.exe -NoProfile -ExecutionPolicy Bypass -File $script:Ps1 -ConfigPath $sb.Config -Root $sb.Dir -RegistryBase $sb.Reg 2>&1 | Out-String
        $LASTEXITCODE | Should Be 2
        $out | Should Match 'Usage'
    }
    Remove-Sandbox $sb
}
