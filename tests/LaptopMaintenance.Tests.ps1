# Pester 3.4 tests (the Pester that ships with Windows PowerShell 5.1). Run: .\tests\Run-Tests.ps1
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
Import-Module (Join-Path $root 'src\LaptopMaintenance.psm1') -Force

Describe 'Format-LmSize' {
    It 'formats bytes, KB, MB and GB' {
        Format-LmSize 0 | Should Be '0 B'
        Format-LmSize 512 | Should Be '512 B'
        Format-LmSize 2048 | Should Be '2.0 KB'
        Format-LmSize (5 * 1MB) | Should Be '5.0 MB'
        Format-LmSize (1.5 * 1GB) | Should Be '1.50 GB'
    }
}

Describe 'Expand-LmPath' {
    It 'expands %ENV% tokens case-insensitively' {
        $r = Expand-LmPath -Path '%localappdata%\Foo' -Vars @{}
        $r | Should Be (Join-Path $env:LOCALAPPDATA 'Foo')
    }
    It 'expands <VAR> lists into several paths' {
        $vars = @{ 'P' = 'C:\A,C:\B' }
        $r = @(Expand-LmPath -Path '<P>\Cache' -Vars $vars)
        $r.Count | Should Be 2
        $r[0] | Should Be 'C:\A\Cache'
        $r[1] | Should Be 'C:\B\Cache'
    }
    It 'expands env tokens inside var lists' {
        $vars = @{ 'P' = '%TEMP%\x' }
        $r = Expand-LmPath -Path '<P>' -Vars $vars
        $r | Should Be (Join-Path $env:TEMP 'x')
    }
}

Describe 'Resolve-LmWildcardPath' {
    $base = Join-Path $env:TEMP ('lmtest_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path "$base\User Data\Default\Cache" -Force | Out-Null
    New-Item -ItemType Directory -Path "$base\User Data\Profile 1\Cache" -Force | Out-Null
    New-Item -ItemType Directory -Path "$base\User Data\Other\Cache" -Force | Out-Null

    It 'returns a literal existing directory' {
        @(Resolve-LmWildcardPath "$base\User Data\Default\Cache").Count | Should Be 1
    }
    It 'returns nothing for a missing directory' {
        @(Resolve-LmWildcardPath "$base\Nope").Count | Should Be 0
    }
    It 'expands wildcards in the middle of the path' {
        $r = @(Resolve-LmWildcardPath "$base\User Data\Profile*\Cache")
        $r.Count | Should Be 1
        $r[0] | Should Match 'Profile 1\\Cache$'
    }
    Remove-Item $base -Recurse -Force
}

Describe 'Get-LmFileKeyTargets' {
    $base = Join-Path $env:TEMP ('lmtest_' + [guid]::NewGuid().ToString('N'))
    New-Item -ItemType Directory -Path "$base\sub" -Force | Out-Null
    $old = (Get-Date).AddDays(-30)
    'a' | Set-Content "$base\old.log"; $f = Get-Item "$base\old.log"; $f.LastWriteTime = $old; $f.CreationTime = $old
    'b' | Set-Content "$base\new.log"
    'c' | Set-Content "$base\keep.txt"
    'd' | Set-Content "$base\sub\deep.log"; $f = Get-Item "$base\sub\deep.log"; $f.LastWriteTime = $old; $f.CreationTime = $old
    # A file touched long ago but created today must NOT count as old (both timestamps must be past the cutoff).
    'e' | Set-Content "$base\fresh-copy.log"; (Get-Item "$base\fresh-copy.log").LastWriteTime = $old

    It 'matches patterns non-recursively' {
        $t = @(Get-LmFileKeyTargets -FileKey @{ path = $base; patterns = @('*.log'); recurse = $false } -Vars @{})
        (($t | ForEach-Object Name) | Sort-Object) -join ',' | Should Be 'fresh-copy.log,new.log,old.log'
    }
    It 'recurses when asked' {
        $t = @(Get-LmFileKeyTargets -FileKey @{ path = $base; patterns = @('*.log'); recurse = $true } -Vars @{})
        $t.Count | Should Be 4
    }
    It 'honours olderThanDays' {
        $t = @(Get-LmFileKeyTargets -FileKey @{ path = $base; patterns = @('*.log'); recurse = $true; olderThanDays = 7 } -Vars @{})
        (($t | ForEach-Object Name) | Sort-Object) -join ',' | Should Be 'deep.log,old.log'
    }
    It 'never returns files outside the key path' {
        $t = @(Get-LmFileKeyTargets -FileKey @{ path = $base; patterns = @('*'); recurse = $true } -Vars @{})
        @($t | Where-Object { $_.FullName -notlike "$base*" }).Count | Should Be 0
    }
    Remove-Item $base -Recurse -Force
}

Describe 'Test-LmRuleApplicable' {
    It 'skips when an active process is running' {
        $r = Test-LmRuleApplicable -Rule @{ id = 'x'; activeProcesses = @('explorer') } -Vars @{} -RunningProcessNames @('explorer', 'notepad')
        $r.Applicable | Should Be $false
        $r.Reason | Should Match 'explorer'
    }
    It 'skips when detectFile is missing' {
        $r = Test-LmRuleApplicable -Rule @{ id = 'x'; detectFile = 'C:\definitely\not\here' } -Vars @{} -RunningProcessNames @()
        $r.Applicable | Should Be $false
    }
    It 'applies otherwise' {
        $r = Test-LmRuleApplicable -Rule @{ id = 'x'; detectFile = $env:TEMP } -Vars @{} -RunningProcessNames @()
        $r.Applicable | Should Be $true
    }
}

Describe 'Select-LmServiceCandidates' {
    $cfg = @{ cpuPercentThreshold = 3.0; memoryMBThreshold = 150; stopIdleManualServices = $true;
              optionalAutoServices = @('VendorAuto'); alwaysStop = @('ForceMe'); neverTouch = @('WinDefend') }
    function New-TestSvc($name, $state, $mode, $procId, $path) {
        [pscustomobject]@{ Name = $name; DisplayName = $name; State = $state; StartMode = $mode; ProcessId = $procId; ExePath = $path; SharedHost = ($path -like '*svchost.exe*'); RunningDependents = @() }
    }
    $services = @(
        (New-TestSvc 'HungryManual' 'Running' 'Manual' 100 'C:\Program Files\Vendor\svc.exe'),
        (New-TestSvc 'QuietManual'  'Running' 'Manual' 101 'C:\Program Files\Quiet\svc.exe'),
        (New-TestSvc 'WinDefend'    'Running' 'Auto'   102 'C:\Program Files\Windows Defender\MsMpEng.exe'),
        (New-TestSvc 'SharedHost'   'Running' 'Auto'   103 'C:\Windows\System32\svchost.exe -k netsvcs'),
        (New-TestSvc 'VendorAuto'   'Running' 'Auto'   104 'C:\Program Files\Other\svc.exe'),
        (New-TestSvc 'HungryAuto'   'Running' 'Auto'   105 'C:\Program Files\Third\svc.exe'),
        (New-TestSvc 'ForceMe'      'Running' 'Auto'   106 'C:\Program Files\Force\svc.exe'),
        (New-TestSvc 'InUseManual'  'Running' 'Manual' 107 'C:\Program Files\Busy\svc.exe'),
        (New-TestSvc 'Stopped'      'Stopped' 'Manual' 0   'C:\Program Files\Zzz\svc.exe')
    )
    $samples = @{ 100 = @{ CpuPercent = 12.0; WorkingSetMB = 40 }; 101 = @{ CpuPercent = 0.1; WorkingSetMB = 20 };
                  102 = @{ CpuPercent = 20.0; WorkingSetMB = 400 }; 103 = @{ CpuPercent = 9.0; WorkingSetMB = 300 };
                  104 = @{ CpuPercent = 0.0; WorkingSetMB = 200 }; 105 = @{ CpuPercent = 50.0; WorkingSetMB = 900 };
                  106 = @{ CpuPercent = 0.0; WorkingSetMB = 1 };   107 = @{ CpuPercent = 15.0; WorkingSetMB = 300 } }
    $windows = @('C:\Program Files\Busy\app.exe')   # a visible app belonging to InUseManual's vendor

    $c = @(Select-LmServiceCandidates -Services $services -Samples $samples -Config $cfg -VisibleAppPaths $windows)
    $names = @($c | ForEach-Object Name)

    It 'picks a hungry manual-start service' { ($names -contains 'HungryManual') | Should Be $true }
    It 'ignores a quiet manual service' { ($names -contains 'QuietManual') | Should Be $false }
    It 'never touches protected services' { ($names -contains 'WinDefend') | Should Be $false }
    It 'never touches shared svchost hosts' { ($names -contains 'SharedHost') | Should Be $false }
    It 'picks an opted-in auto service above the memory threshold' { ($names -contains 'VendorAuto') | Should Be $true }
    It 'leaves non-opted-in auto services alone even when hungry' { ($names -contains 'HungryAuto') | Should Be $false }
    It 'always stops services on the alwaysStop list' { ($names -contains 'ForceMe') | Should Be $true }
    It 'leaves a service alone while its vendor app has a window' { ($names -contains 'InUseManual') | Should Be $false }
    It 'skips stopped services' { ($names -contains 'Stopped') | Should Be $false }
    It 'reports a reason for each candidate' { @($c | Where-Object { -not $_.Reason }).Count | Should Be 0 }
}

Describe 'Test-LmVendorAppVisible' {
    It 'matches a window from the same vendor folder' {
        Test-LmVendorAppVisible -ServiceExePath 'C:\Program Files\Acme\Service\acmesvc.exe' -VisibleAppPaths @('C:\Program Files\Acme\App\acme.exe') | Should Be $true
    }
    It 'does not match a different vendor' {
        Test-LmVendorAppVisible -ServiceExePath 'C:\Program Files\Acme\acmesvc.exe' -VisibleAppPaths @('C:\Program Files\Other\x.exe') | Should Be $false
    }
    It 'treats Program Files itself as too broad to match' {
        Test-LmVendorAppVisible -ServiceExePath 'C:\Program Files\svc.exe' -VisibleAppPaths @('C:\Program Files\x.exe') | Should Be $false
    }
}

Describe 'ConvertFrom-LmServicePath' {
    It 'strips arguments and quotes' {
        ConvertFrom-LmServicePath '"C:\Program Files\Acme\svc.exe" -run' | Should Be 'C:\Program Files\Acme\svc.exe'
        ConvertFrom-LmServicePath 'C:\Windows\System32\svchost.exe -k netsvcs -p' | Should Be 'C:\Windows\System32\svchost.exe'
        ConvertFrom-LmServicePath 'C:\Windows\system32\lsass.exe' | Should Be 'C:\Windows\system32\lsass.exe'
    }
}

Describe 'Service revert ledger' {
    $ledger = Join-Path $env:TEMP ('lmledger_' + [guid]::NewGuid().ToString('N') + '.json')
    It 'records and reads back changes' {
        Add-LmLedgerEntry -Path $ledger -ServiceName 'Foo' -OldStartMode 'Auto' -NewStartMode 'Manual'
        $e = @(Get-LmLedger -Path $ledger)
        $e.Count | Should Be 1
        $e[0].ServiceName | Should Be 'Foo'
        $e[0].OldStartMode | Should Be 'Auto'
    }
    It 'does not duplicate an entry for the same service' {
        Add-LmLedgerEntry -Path $ledger -ServiceName 'Foo' -OldStartMode 'Manual' -NewStartMode 'Manual'
        @(Get-LmLedger -Path $ledger).Count | Should Be 1
    }
    Remove-Item $ledger -Force -ErrorAction SilentlyContinue
}

Describe 'Get-LmOldDrivers' {
    $inv = @(
        [pscustomobject]@{ DeviceName = 'Old NIC';      DeviceClass = 'Net';     Manufacturer = 'Realtek';                  AgeYears = 5.2 },
        [pscustomobject]@{ DeviceName = 'New GPU';      DeviceClass = 'Display'; Manufacturer = 'NVIDIA';                   AgeYears = 0.3 },
        [pscustomobject]@{ DeviceName = 'MS inbox';     DeviceClass = 'Net';     Manufacturer = 'Microsoft';                AgeYears = 19.0 },
        [pscustomobject]@{ DeviceName = 'Generic';      DeviceClass = 'System';  Manufacturer = '(Standard system devices)'; AgeYears = 19.0 },
        [pscustomobject]@{ DeviceName = 'Old printer';  DeviceClass = 'Printer'; Manufacturer = 'HP';                       AgeYears = 8.0 },
        [pscustomobject]@{ DeviceName = 'No date';      DeviceClass = 'Net';     Manufacturer = 'Intel';                    AgeYears = $null },
        [pscustomobject]@{ DeviceName = 'Inbox AMD';    DeviceClass = 'System';  Manufacturer = 'AMD Workload Profiling Scheduling Device'; AgeYears = 20.3; DriverDate = (Get-Date '2006-06-21') }
    )
    $old = @(Get-LmOldDrivers -Inventory $inv -MaxAgeYears 3 -Classes @('Net', 'Display', 'System'))
    It 'flags only vendor drivers past the age limit in the chosen classes' {
        (($old | ForEach-Object DeviceName) -join ',') | Should Be 'Old NIC'
    }
    It 'includes every class when none are given' {
        (@(Get-LmOldDrivers -Inventory $inv -MaxAgeYears 3) | ForEach-Object DeviceName | Sort-Object) -join ',' | Should Be 'Old NIC,Old printer'
    }
}

Describe 'Protected browser files' {
    It 'recognises password, autofill, cookie, history and bookmark stores' {
        foreach ($n in 'Login Data', 'Web Data', 'Cookies', 'History', 'Bookmarks', 'logins.json', 'key4.db', 'formhistory.sqlite', 'places.sqlite') { Test-LmProtectedFile $n | Should Be $true }
        Test-LmProtectedFile 'data_0' | Should Be $false
        Test-LmProtectedFile 'f_000123' | Should Be $false
    }
    It 'never returns them from a file key, even with a wildcard pattern' {
        $base = Join-Path $env:TEMP ('lmtest_' + [guid]::NewGuid().ToString('N'))
        New-Item -ItemType Directory -Path $base -Force | Out-Null
        foreach ($n in 'Login Data', 'Web Data', 'Cookies', 'data_0', 'index') { 'x' | Set-Content (Join-Path $base $n) }
        $t = @(Get-LmFileKeyTargets -FileKey @{ path = $base; patterns = @('*'); recurse = $true } -Vars @{})
        (($t | ForEach-Object Name) | Sort-Object) -join ',' | Should Be 'data_0,index'
        Remove-Item $base -Recurse -Force
    }
}

Describe 'Vendor driver helpers' {
    It 'converts Windows driver versions to NVIDIA versions' {
        ConvertTo-LmNvidiaVersion '32.0.16.1742' | Should Be '617.42'
        ConvertTo-LmNvidiaVersion '31.0.15.5222' | Should Be '552.22'
        ConvertTo-LmNvidiaVersion '30.0.14.7168' | Should Be '471.68'
    }
    It 'compares versions with V prefixes and zero padding' {
        Compare-LmVersion 'V5.7.0.5115' '5.5.0.3548' | Should Be 1
        Compare-LmVersion '1.0.017.00' '1.0.17.0' | Should Be 0
        Compare-LmVersion '21.51.46.157' 'V23.26.47.823' | Should Be -1
        Compare-LmVersion '617.42' '617.42' | Should Be 0
        Compare-LmVersion 'latest version at the MS store' '1.0' | Should Be $null
    }
    It 'matches OEM downloads to installed drivers and flags the newer ones' {
        $oem = @(
            [pscustomobject]@{ Title = 'MediaTek WLAN Driver'; Version = 'V5.7.0.5115'; Category = 'Networking'; Url = 'u1'; Date = '2026/01/29' },
            [pscustomobject]@{ Title = 'MediaTek WLAN Driver'; Version = 'V5.5.0.3760'; Category = 'Networking'; Url = 'u0'; Date = '2025/05/14' },
            [pscustomobject]@{ Title = 'MediaTek Bluetooth Driver'; Version = 'V1.1045.0.566'; Category = 'Bluetooth'; Url = 'u2'; Date = '2026/01/29' },
            [pscustomobject]@{ Title = 'NVIDIA Graphic Driver'; Version = 'V32.0.15.7665'; Category = 'Graphics'; Url = 'u3'; Date = '2025/07/21' },
            [pscustomobject]@{ Title = 'Aura Wallpaper'; Version = 'V2.0.12.0'; Category = 'Software and Utility'; Url = 'u4'; Date = '2025/02/12' },
            [pscustomobject]@{ Title = 'Realtek Codec Console Application'; Version = 'latest version at the MS store'; Category = 'Audio'; Url = ''; Date = '' },
            [pscustomobject]@{ Title = 'Parade Retimer Driver'; Version = 'V1.0.017.00'; Category = 'USB'; Url = 'u5'; Date = '2025/02/12' },
            [pscustomobject]@{ Title = 'AMD Chipset'; Version = 'V1.2.0.126'; Category = 'Chipset'; Url = 'u6'; Date = '2025/02/12' }
        )
        $inv = @(
            [pscustomobject]@{ DeviceClass = 'NET'; Manufacturer = 'MediaTek, Inc.'; DeviceName = 'MediaTek Wi-Fi 7 MT7925 Wireless LAN Card'; DriverVersion = '5.5.0.3548' },
            [pscustomobject]@{ DeviceClass = 'BLUETOOTH'; Manufacturer = 'Mediatek Inc.'; DeviceName = 'MediaTek Bluetooth Adapter'; DriverVersion = '1.1045.0.566' },
            [pscustomobject]@{ DeviceClass = 'SYSTEM'; Manufacturer = 'Advanced Micro Devices, Inc'; DeviceName = 'AMD GPIO Controller'; DriverVersion = '2.2.0.136' },
            [pscustomobject]@{ DeviceClass = 'SYSTEM'; Manufacturer = 'Advanced Micro Devices, Inc.'; DeviceName = 'AMD I2C Controller'; DriverVersion = '1.2.0.126' }
        )
        $rows = @(Compare-LmOemDrivers -OemFiles $oem -Inventory $inv -Source 'ASUS')
        ($rows | Where-Object Component -eq 'MediaTek WLAN Driver').Status | Should Be 'Update available'
        ($rows | Where-Object Component -eq 'MediaTek WLAN Driver').Latest | Should Be '5.7.0.5115'
        ($rows | Where-Object Component -eq 'MediaTek Bluetooth Driver').Status | Should Be 'Up to date'
        ($rows | Where-Object Component -eq 'Parade Retimer Driver').Status | Should Be 'Not compared'
        ($rows | Where-Object Component -eq 'AMD Chipset').Status | Should Be 'Up to date'
        ($rows | Where-Object Component -eq 'AMD Chipset').Installed | Should Be '1.2.0.126'
        @($rows | Where-Object { $_.Component -match 'NVIDIA|Aura|Codec Console' }).Count | Should Be 0
        @($rows | Where-Object Component -eq 'MediaTek WLAN Driver').Count | Should Be 1
    }
}

Describe 'Get-LmServiceAudit' {
    It 'buckets every running service exactly once' {
        $cfg = @{ cpuPercentThreshold = 3.0; memoryMBThreshold = 150; neverTouch = @('WinDefend'); optionalAutoServices = @() }
        $svcs = @(
            [pscustomobject]@{ Name = 'WinDefend'; State = 'Running'; StartMode = 'Auto'; ProcessId = 1; ExePath = 'C:\x\a.exe'; SharedHost = $false; RunningDependents = @() },
            [pscustomobject]@{ Name = 'Shared'; State = 'Running'; StartMode = 'Auto'; ProcessId = 2; ExePath = 'C:\Windows\System32\svchost.exe'; SharedHost = $true; RunningDependents = @() },
            [pscustomobject]@{ Name = 'Quiet'; State = 'Running'; StartMode = 'Manual'; ProcessId = 3; ExePath = 'C:\Program Files\Q\q.exe'; SharedHost = $false; RunningDependents = @() },
            [pscustomobject]@{ Name = 'HungryAuto'; State = 'Running'; StartMode = 'Auto'; ProcessId = 4; ExePath = 'C:\Program Files\H\h.exe'; SharedHost = $false; RunningDependents = @() },
            [pscustomobject]@{ Name = 'Cand'; State = 'Running'; StartMode = 'Manual'; ProcessId = 5; ExePath = 'C:\Program Files\C\c.exe'; SharedHost = $false; RunningDependents = @() },
            [pscustomobject]@{ Name = 'Off'; State = 'Stopped'; StartMode = 'Manual'; ProcessId = 0; ExePath = 'C:\Program Files\O\o.exe'; SharedHost = $false; RunningDependents = @() }
        )
        $samples = @{ 1 = @{ CpuPercent = 9; WorkingSetMB = 400 }; 2 = @{ CpuPercent = 9; WorkingSetMB = 400 }; 3 = @{ CpuPercent = 0.1; WorkingSetMB = 10 }; 4 = @{ CpuPercent = 9; WorkingSetMB = 400 }; 5 = @{ CpuPercent = 9; WorkingSetMB = 400 } }
        $a = Get-LmServiceAudit -Services $svcs -Samples $samples -Config $cfg
        $a.Running | Should Be 5
        $a.Protected | Should Be 1
        $a.SharedHost | Should Be 1
        $a.BelowThreshold | Should Be 1
        $a.AutoNotOptedIn | Should Be 1
        $a.Candidates | Should Be 1
        ($a.Protected + $a.SharedHost + $a.HasDependents + $a.BelowThreshold + $a.VendorAppOpen + $a.AutoNotOptedIn + $a.Candidates) | Should Be $a.Running
    }
}

Describe 'Test-LmRuleEnabled' {
    $cfg = @{ clean = @{ enabledRules = @('off.but.on'); disabledRules = @('on.but.off', 'both') } }
    It 'uses the rule default when settings say nothing' {
        Test-LmRuleEnabled -Rule @{ id = 'a'; default = $true } -Config $cfg | Should Be $true
        Test-LmRuleEnabled -Rule @{ id = 'b'; default = $false } -Config $cfg | Should Be $false
        Test-LmRuleEnabled -Rule @{ id = 'c' } -Config $cfg | Should Be $true
    }
    It 'lets enabledRules switch a default-off rule on' { Test-LmRuleEnabled -Rule @{ id = 'off.but.on'; default = $false } -Config $cfg | Should Be $true }
    It 'lets disabledRules switch a default-on rule off' { Test-LmRuleEnabled -Rule @{ id = 'on.but.off'; default = $true } -Config $cfg | Should Be $false }
    It 'gives disabledRules the last word' { Test-LmRuleEnabled -Rule @{ id = 'both'; default = $false } -Config @{ clean = @{ enabledRules = @('both'); disabledRules = @('both') } } | Should Be $false }
}

Describe 'Config loading' {
    It 'loads settings.json' {
        $c = Get-LmConfig -Path (Join-Path $root 'config\settings.json')
        $c.services.cpuPercentThreshold | Should Be 3.0
        ($c.services.neverTouch -contains 'WinDefend') | Should Be $true
        $c.report.keepReports | Should Be 20
    }
    It 'loads rules.json with vars and rules' {
        $r = Get-LmRules -Path (Join-Path $root 'config\rules.json')
        ($r.vars.Keys -contains 'EDGE_PROFILES') | Should Be $true
        @($r.rules).Count | Should BeGreaterThan 10
        @($r.rules | Where-Object { -not $_.id }).Count | Should Be 0
    }
}
