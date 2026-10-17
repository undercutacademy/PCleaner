# LaptopMaintenance.psm1 - weekly cleaner, driver check and service tamer for one Windows laptop.
# Windows PowerShell 5.1. ASCII only. No external modules.

$script:AppName  = 'PCleaner'
$script:DataRoot = Join-Path $env:LOCALAPPDATA 'PCleaner'
$script:LogFile  = $null

# ---------------------------------------------------------------------------------------------
# Infrastructure
# ---------------------------------------------------------------------------------------------

function Get-LmPaths {
    $p = [ordered]@{
        Root    = $script:DataRoot
        Logs    = Join-Path $script:DataRoot 'logs'
        Reports = Join-Path $script:DataRoot 'reports'
        State   = Join-Path $script:DataRoot 'state'
    }
    foreach ($d in $p.Values) { if (-not (Test-Path $d)) { New-Item -ItemType Directory -Path $d -Force | Out-Null } }
    $p['Ledger'] = Join-Path $p.State 'service-ledger.json'
    [pscustomobject]$p
}

function Start-LmLog {
    param([string]$RunId)
    $paths = Get-LmPaths
    if (-not $RunId) { $RunId = Get-Date -Format 'yyyy-MM-dd_HHmmss' }
    $script:LogFile = Join-Path $paths.Logs ("run_{0}.log" -f $RunId)
    Write-LmLog "=== $script:AppName started (user=$env:USERNAME, admin=$(Test-LmAdmin)) ==="
    $script:LogFile
}

function Write-LmLog {
    param([Parameter(Mandatory)][string]$Message, [ValidateSet('INFO', 'WARN', 'ERROR', 'OK')][string]$Level = 'INFO')
    $line = "[{0}] [{1,-5}] {2}" -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    if ($script:LogFile) { Add-Content -Path $script:LogFile -Value $line -Encoding ASCII }
    $color = switch ($Level) { 'WARN' { 'Yellow' } 'ERROR' { 'Red' } 'OK' { 'Green' } default { 'Gray' } }
    Write-Host $line -ForegroundColor $color
}

function Test-LmAdmin {
    $id = [Security.Principal.WindowsIdentity]::GetCurrent()
    (New-Object Security.Principal.WindowsPrincipal $id).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
}

function Format-LmSize {
    param([Parameter(Mandatory)][double]$Bytes)
    if ($Bytes -ge 1GB) { return ('{0:N2} GB' -f ($Bytes / 1GB)) }
    if ($Bytes -ge 1MB) { return ('{0:N1} MB' -f ($Bytes / 1MB)) }
    if ($Bytes -ge 1KB) { return ('{0:N1} KB' -f ($Bytes / 1KB)) }
    return ('{0} B' -f [int64]$Bytes)
}

function ConvertTo-LmHashtable {
    # PSCustomObject (from ConvertFrom-Json) -> nested hashtables/arrays so callers can use @{} style access.
    param($InputObject)
    if ($null -eq $InputObject) { return $null }
    if ($InputObject -is [System.Collections.IDictionary]) { return $InputObject }
    if ($InputObject -is [string]) { return $InputObject }
    if ($InputObject -is [System.Collections.IEnumerable]) {
        $list = @()
        foreach ($i in $InputObject) { $list += , (ConvertTo-LmHashtable $i) }
        return , $list
    }
    if ($InputObject -is [pscustomobject]) {
        $h = @{}
        foreach ($prop in $InputObject.PSObject.Properties) { $h[$prop.Name] = ConvertTo-LmHashtable $prop.Value }
        return $h
    }
    return $InputObject
}

function Get-LmConfig {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { throw "Settings file not found: $Path" }
    $raw = Get-Content -Path $Path -Raw | ConvertFrom-Json
    $cfg = ConvertTo-LmHashtable $raw
    foreach ($k in 'clean', 'drivers', 'services', 'report', 'schedule') { if (-not $cfg.ContainsKey($k)) { $cfg[$k] = @{} } }
    foreach ($k in 'optionalAutoServices', 'alwaysStop', 'neverTouch') { if (-not $cfg.services.ContainsKey($k) -or $null -eq $cfg.services[$k]) { $cfg.services[$k] = @() } }
    if (-not $cfg.clean.ContainsKey('disabledRules') -or $null -eq $cfg.clean.disabledRules) { $cfg.clean.disabledRules = @() }
    if (-not $cfg.clean.ContainsKey('enabledRules') -or $null -eq $cfg.clean.enabledRules) { $cfg.clean.enabledRules = @() }
    if (-not $cfg.ContainsKey('ui')) { $cfg.ui = @{} }
    $cfg
}

function Test-LmRuleEnabled {
    # Rule default, then settings overrides: enabledRules turns a default-off rule on, disabledRules wins over everything.
    param([Parameter(Mandatory)][hashtable]$Rule, [Parameter(Mandatory)][hashtable]$Config)
    $on = $true
    if ($Rule.ContainsKey('default')) { $on = [bool]$Rule.default }
    if (@($Config.clean.enabledRules) -contains $Rule.id) { $on = $true }
    if (@($Config.clean.disabledRules) -contains $Rule.id) { $on = $false }
    $on
}

function Get-LmRules {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { throw "Rules file not found: $Path" }
    $raw = Get-Content -Path $Path -Raw | ConvertFrom-Json
    $r = ConvertTo-LmHashtable $raw
    if (-not $r.ContainsKey('vars') -or $null -eq $r.vars) { $r.vars = @{} }
    if (-not $r.ContainsKey('rules')) { $r.rules = @() }
    $r
}

# ---------------------------------------------------------------------------------------------
# Rules engine (modelled on CCleaner's FileKey / DetectFile / ActiveProcesses grammar)
# ---------------------------------------------------------------------------------------------

function Expand-LmEnvTokens {
    param([string]$Text)
    $out = [regex]::Replace($Text, '%([A-Za-z0-9_()]+)%', {
            param($m)
            $name = $m.Groups[1].Value
            $v = [Environment]::GetEnvironmentVariable($name)
            if ($null -eq $v) {
                switch ($name.ToLowerInvariant()) {
                    'commonappdata' { $v = $env:ProgramData }
                    'systemdirectory' { $v = Join-Path $env:windir 'System32' }
                    default { $v = $m.Value }
                }
            }
            $v
        })
    $out
}

function Expand-LmPath {
    # Returns one or more paths: %ENV% tokens are expanded; <VAR> tokens expand to each comma-separated value.
    param([Parameter(Mandatory)][string]$Path, [hashtable]$Vars = @{})
    $m = [regex]::Match($Path, '<([A-Za-z0-9_]+)>')
    if (-not $m.Success) { return Expand-LmEnvTokens $Path }
    $name = $m.Groups[1].Value
    if (-not $Vars.ContainsKey($name)) { return Expand-LmEnvTokens $Path }
    $results = @()
    foreach ($value in ($Vars[$name] -split ',')) {
        $value = $value.Trim()
        if (-not $value) { continue }
        $replaced = $Path.Replace($m.Value, $value)
        $results += @(Expand-LmPath -Path $replaced -Vars $Vars)
    }
    return $results
}

function Resolve-LmWildcardPath {
    # Resolve a directory path that may contain wildcards in any segment to the list of existing directories.
    param([Parameter(Mandatory)][string]$Path)
    $Path = $Path.TrimEnd('\')
    if ($Path -notmatch '[\*\?]') {
        if (Test-Path -LiteralPath $Path -PathType Container) { return @($Path) }
        return @()
    }
    $segments = $Path -split '\\'
    $current = @($segments[0] + '\')
    for ($i = 1; $i -lt $segments.Count; $i++) {
        $seg = $segments[$i]
        if (-not $seg) { continue }
        $next = @()
        foreach ($dir in $current) {
            if ($seg -match '[\*\?]') {
                $next += @(Get-ChildItem -LiteralPath $dir -Directory -Filter $seg -Force -ErrorAction SilentlyContinue | ForEach-Object FullName)
            } else {
                $cand = Join-Path $dir $seg
                if (Test-Path -LiteralPath $cand -PathType Container) { $next += $cand }
            }
        }
        $current = $next
        if ($current.Count -eq 0) { break }
    }
    return @($current)
}

# Files no rule may ever delete: browser password stores, autofill, cookies, history, bookmarks, profile state.
$script:ProtectedFileNames = @(
    'Login Data', 'Login Data-journal', 'Login Data For Account', 'Login Data For Account-journal',
    'Web Data', 'Web Data-journal', 'Cookies', 'Cookies-journal', 'Network\Cookies', 'History', 'History-journal',
    'Bookmarks', 'Bookmarks.bak', 'Preferences', 'Secure Preferences', 'Local State', 'Top Sites', 'Top Sites-journal',
    'Favicons', 'Favicons-journal', 'Affiliation Database', 'Extension Cookies', 'Shortcuts', 'Shortcuts-journal',
    'logins.json', 'logins-backup.json', 'key4.db', 'key3.db', 'cert9.db', 'cert8.db', 'formhistory.sqlite',
    'places.sqlite', 'places.sqlite-wal', 'cookies.sqlite', 'cookies.sqlite-wal', 'signons.sqlite', 'permissions.sqlite',
    'prefs.js', 'user.js', 'sessionstore.jsonlz4', 'extensions.json', 'addons.json'
)
function Test-LmProtectedFile {
    param([Parameter(Mandatory)][string]$Name)
    [bool]($script:ProtectedFileNames -contains $Name)
}

function Get-LmFileKeyTargets {
    # Enumerate files matched by one fileKey entry. Never follows reparse points, never returns protected browser files.
    param([Parameter(Mandatory)][hashtable]$FileKey, [hashtable]$Vars = @{})
    $patterns = @($FileKey.patterns); if ($patterns.Count -eq 0) { $patterns = @('*') }
    $recurse = [bool]$FileKey.recurse
    $cutoff = $null
    if ($FileKey.ContainsKey('olderThanDays') -and $FileKey.olderThanDays) { $cutoff = (Get-Date).AddDays(-1 * [double]$FileKey.olderThanDays) }
    $dirs = @()
    foreach ($p in @(Expand-LmPath -Path $FileKey.path -Vars $Vars)) { $dirs += @(Resolve-LmWildcardPath -Path $p) }
    $files = @()
    foreach ($dir in $dirs) {
        foreach ($pat in $patterns) {
            $items = @(Get-ChildItem -LiteralPath $dir -Filter $pat -File -Force -Recurse:$recurse -ErrorAction SilentlyContinue |
                    Where-Object { -not ($_.Attributes -band [IO.FileAttributes]::ReparsePoint) })
            if ($cutoff) { $items = @($items | Where-Object { $_.LastWriteTime -lt $cutoff -and $_.CreationTime -lt $cutoff }) }
            $files += $items
        }
    }
    # De-duplicate (two patterns can match the same file) and keep only files under the resolved directories.
    $seen = @{}
    $out = @()
    foreach ($f in $files) {
        if ($seen.ContainsKey($f.FullName)) { continue }
        $seen[$f.FullName] = $true
        if (Test-LmProtectedFile -Name $f.Name) { continue }
        $inside = $false
        foreach ($dir in $dirs) { if ($f.FullName.StartsWith($dir.TrimEnd('\') + '\', [StringComparison]::OrdinalIgnoreCase)) { $inside = $true; break } }
        if ($inside) { $out += $f }
    }
    return $out
}

function Test-LmRuleApplicable {
    param([Parameter(Mandatory)][hashtable]$Rule, [hashtable]$Vars = @{}, [string[]]$RunningProcessNames = @())
    if ($Rule.ContainsKey('activeProcesses') -and $Rule.activeProcesses) {
        foreach ($proc in @($Rule.activeProcesses)) {
            if ($RunningProcessNames -contains $proc) {
                return [pscustomobject]@{ Applicable = $false; Reason = "skipped: $proc is running" }
            }
        }
    }
    if ($Rule.ContainsKey('detectFile') -and $Rule.detectFile) {
        $found = $false
        foreach ($p in @(Expand-LmPath -Path $Rule.detectFile -Vars $Vars)) {
            if ((Resolve-LmWildcardPath -Path $p).Count -gt 0 -or (Test-Path -LiteralPath $p)) { $found = $true; break }
        }
        if (-not $found) { return [pscustomobject]@{ Applicable = $false; Reason = 'not installed' } }
    }
    [pscustomobject]@{ Applicable = $true; Reason = '' }
}

function Remove-LmFiles {
    param([System.IO.FileInfo[]]$Files, [switch]$DryRun)
    $deleted = 0; $bytes = 0; $failed = 0
    foreach ($f in @($Files)) {
        try {
            $len = $f.Length
            if (-not $DryRun) {
                if ($f.IsReadOnly) { $f.IsReadOnly = $false }
                Remove-Item -LiteralPath $f.FullName -Force -ErrorAction Stop
            }
            $deleted++; $bytes += $len
        } catch { $failed++ }
    }
    [pscustomobject]@{ Deleted = $deleted; Bytes = $bytes; Failed = $failed }
}

function Remove-LmEmptyDirectories {
    param([string[]]$Roots, [switch]$DryRun, [switch]$RemoveRoot)
    $removed = 0
    foreach ($root in @($Roots)) {
        if (-not (Test-Path -LiteralPath $root)) { continue }
        $dirs = @(Get-ChildItem -LiteralPath $root -Directory -Recurse -Force -ErrorAction SilentlyContinue | Sort-Object { $_.FullName.Length } -Descending)
        if ($RemoveRoot) { $dirs += Get-Item -LiteralPath $root }
        foreach ($d in $dirs) {
            if ($d.Attributes -band [IO.FileAttributes]::ReparsePoint) { continue }
            if (@(Get-ChildItem -LiteralPath $d.FullName -Force -ErrorAction SilentlyContinue).Count -eq 0) {
                try { if (-not $DryRun) { Remove-Item -LiteralPath $d.FullName -Force -ErrorAction Stop }; $removed++ } catch { }
            }
        }
    }
    $removed
}

function Clear-LmRecycleBin {
    # Permanently deletes Recycle Bin items older than N days by removing their $R/$I pairs. Silent, no shell prompts.
    param([int]$OlderThanDays = 7, [switch]$DryRun)
    $deleted = 0; $bytes = 0; $failed = 0
    $cutoff = (Get-Date).AddDays(-1 * $OlderThanDays)
    try {
        $shell = New-Object -ComObject Shell.Application
        $bin = $shell.NameSpace(0xA)
        foreach ($item in @($bin.Items())) {
            $when = $null
            try { $when = $item.ExtendedProperty('System.Recycle.DateDeleted') } catch { }
            if ($when -is [datetime] -and $when -gt $cutoff) { continue }
            $rPath = $item.Path
            $dir = Split-Path $rPath -Parent
            $leaf = Split-Path $rPath -Leaf
            $iPath = $null
            if ($leaf -like '$R*') { $iPath = Join-Path $dir ('$I' + $leaf.Substring(2)) }
            try {
                $size = 0
                if (Test-Path -LiteralPath $rPath -PathType Container) {
                    $size = (Get-ChildItem -LiteralPath $rPath -Recurse -Force -File -ErrorAction SilentlyContinue | Measure-Object Length -Sum).Sum
                } elseif (Test-Path -LiteralPath $rPath) { $size = (Get-Item -LiteralPath $rPath -Force).Length }
                if (-not $DryRun) {
                    Remove-Item -LiteralPath $rPath -Recurse -Force -ErrorAction Stop
                    if ($iPath -and (Test-Path -LiteralPath $iPath)) { Remove-Item -LiteralPath $iPath -Force -ErrorAction SilentlyContinue }
                }
                $deleted++; $bytes += [double]$size
            } catch { $failed++ }
        }
    } catch { Write-LmLog "Recycle Bin: $($_.Exception.Message)" 'WARN' }
    [pscustomobject]@{ Deleted = $deleted; Bytes = $bytes; Failed = $failed }
}

function Invoke-LmAction {
    param([Parameter(Mandatory)][string]$Action, [hashtable]$Config, [switch]$DryRun)
    $note = ''
    switch ($Action) {
        'EmptyRecycleBin' {
            $days = 7; if ($Config.clean.ContainsKey('recycleBinOlderThanDays')) { $days = [int]$Config.clean.recycleBinOlderThanDays }
            $r = Clear-LmRecycleBin -OlderThanDays $days -DryRun:$DryRun
            return [pscustomobject]@{ Deleted = $r.Deleted; Bytes = $r.Bytes; Failed = $r.Failed; Note = "items older than $days days" }
        }
        'CleanDNSCache' {
            if (-not $DryRun) { try { Clear-DnsClientCache -ErrorAction Stop } catch { & ipconfig /flushdns | Out-Null } }
            return [pscustomobject]@{ Deleted = 1; Bytes = 0; Failed = 0; Note = 'flushed' }
        }
        'DeliveryOptimizationCache' {
            if (-not (Test-LmAdmin)) { return [pscustomobject]@{ Deleted = 0; Bytes = 0; Failed = 0; Note = 'needs admin' } }
            $before = 0
            try { $before = [double](Get-DeliveryOptimizationStatus -ErrorAction Stop | Measure-Object FileSize -Sum).Sum } catch { }
            if (-not $DryRun) { try { Delete-DeliveryOptimizationCache -Force -ErrorAction Stop } catch { $note = $_.Exception.Message } }
            return [pscustomobject]@{ Deleted = 1; Bytes = $before; Failed = 0; Note = $note }
        }
        'ComponentCleanup' {
            if (-not (Test-LmAdmin)) { return [pscustomobject]@{ Deleted = 0; Bytes = 0; Failed = 0; Note = 'needs admin' } }
            if (-not $DryRun) { & dism.exe /Online /Cleanup-Image /StartComponentCleanup /Quiet /NoRestart | Out-Null; $note = "dism exit $LASTEXITCODE" }
            return [pscustomobject]@{ Deleted = 1; Bytes = 0; Failed = 0; Note = $note }
        }
        default { return [pscustomobject]@{ Deleted = 0; Bytes = 0; Failed = 1; Note = "unknown action $Action" } }
    }
}

function Invoke-LmClean {
    param([Parameter(Mandatory)][hashtable]$Rules, [Parameter(Mandatory)][hashtable]$Config, [switch]$DryRun)
    $running = @(Get-Process | Select-Object -ExpandProperty ProcessName -Unique)
    $results = @()
    foreach ($rule in @($Rules.rules)) {
        $enabled = Test-LmRuleEnabled -Rule $rule -Config $Config
        $row = [ordered]@{ Id = $rule.id; Name = $rule.name; Group = $rule.group; Enabled = $enabled; Status = ''; Files = 0; Bytes = 0; Failed = 0; Note = '' }
        if (-not $enabled) { $row.Status = 'disabled'; $results += [pscustomobject]$row; continue }
        $check = Test-LmRuleApplicable -Rule $rule -Vars $Rules.vars -RunningProcessNames $running
        if (-not $check.Applicable) { $row.Status = $check.Reason; $results += [pscustomobject]$row; Write-LmLog "$($rule.name): $($check.Reason)"; continue }
        try {
            foreach ($fk in @($rule.fileKeys)) {
                if ($null -eq $fk) { continue }
                $targets = @(Get-LmFileKeyTargets -FileKey $fk -Vars $Rules.vars)
                $r = Remove-LmFiles -Files $targets -DryRun:$DryRun
                $row.Files += $r.Deleted; $row.Bytes += $r.Bytes; $row.Failed += $r.Failed
                if ($fk.ContainsKey('removeSelf') -and $fk.removeSelf) {
                    $roots = @(); foreach ($p in @(Expand-LmPath -Path $fk.path -Vars $Rules.vars)) { $roots += @(Resolve-LmWildcardPath -Path $p) }
                    [void](Remove-LmEmptyDirectories -Roots $roots -DryRun:$DryRun -RemoveRoot)
                } elseif ($fk.recurse -and -not $fk.ContainsKey('olderThanDays')) {
                    $roots = @(); foreach ($p in @(Expand-LmPath -Path $fk.path -Vars $Rules.vars)) { $roots += @(Resolve-LmWildcardPath -Path $p) }
                    [void](Remove-LmEmptyDirectories -Roots $roots -DryRun:$DryRun)
                }
            }
            foreach ($action in @($rule.actions)) {
                if (-not $action) { continue }
                $r = Invoke-LmAction -Action $action -Config $Config -DryRun:$DryRun
                $row.Files += $r.Deleted; $row.Bytes += $r.Bytes; $row.Failed += $r.Failed
                if ($r.Note) { $row.Note = $r.Note }
            }
            $row.Status = if ($DryRun) { 'would clean' } else { 'cleaned' }
            Write-LmLog ("{0}: {1} items, {2}{3}" -f $rule.name, $row.Files, (Format-LmSize $row.Bytes), $(if ($row.Failed) { ", $($row.Failed) locked/failed" } else { '' })) 'OK'
        } catch {
            $row.Status = 'error'; $row.Note = $_.Exception.Message
            Write-LmLog "$($rule.name): $($_.Exception.Message)" 'ERROR'
        }
        $results += [pscustomobject]$row
    }
    $results
}

# ---------------------------------------------------------------------------------------------
# Drivers
# ---------------------------------------------------------------------------------------------

function Get-LmDriverInventory {
    $now = Get-Date
    Get-CimInstance Win32_PnPSignedDriver -ErrorAction SilentlyContinue |
        Where-Object { $_.DeviceName -and $_.DriverVersion } |
        ForEach-Object {
            $age = $null; if ($_.DriverDate) { $age = [math]::Round((New-TimeSpan -Start $_.DriverDate -End $now).TotalDays / 365.25, 1) }
            [pscustomobject]@{
                DeviceName = $_.DeviceName; DeviceClass = $_.DeviceClass; Manufacturer = $_.Manufacturer
                DriverVersion = $_.DriverVersion; DriverDate = $_.DriverDate; AgeYears = $age; IsSigned = $_.IsSigned; InfName = $_.InfName
            }
        } | Sort-Object DeviceClass, DeviceName
}

function Get-LmOldDrivers {
    param([Parameter(Mandatory)]$Inventory, [double]$MaxAgeYears = 3, [string[]]$Classes = @())
    $inboxCutoff = Get-Date '2006-06-22'   # Windows stamps every inbox driver 2006-06-21; that is not a real age
    $Inventory | Where-Object {
        $_.AgeYears -ne $null -and $_.AgeYears -gt $MaxAgeYears -and
        -not ($_.PSObject.Properties['DriverDate'] -and $_.DriverDate -and $_.DriverDate -lt $inboxCutoff) -and
        $_.Manufacturer -notmatch '^(Microsoft|\(Standard)' -and
        ($Classes.Count -eq 0 -or $Classes -contains $_.DeviceClass)
    } | Sort-Object AgeYears -Descending
}

function Get-LmProblemDevices {
    try {
        Get-PnpDevice -PresentOnly -ErrorAction Stop | Where-Object { $_.Status -ne 'OK' -and $_.Status -ne 'Unknown' } |
            Select-Object FriendlyName, Class, Status, Problem, InstanceId
    } catch { @() }
}

function Find-LmDriverUpdates {
    # Asks the Windows Update Agent for not-yet-installed driver updates. Needs network; can take a few minutes.
    $out = @()
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $searcher = $session.CreateUpdateSearcher()
        $searcher.Online = $true
        $searcher.ServerSelection = 2   # ssWindowsUpdate (not WSUS)
        $result = $searcher.Search("IsInstalled=0 and Type='Driver' and IsHidden=0")
        foreach ($u in $result.Updates) {
            $out += [pscustomobject]@{
                Title = $u.Title; Provider = $u.DriverProvider; Model = $u.DriverModel; Version = $u.DriverVerDate
                Class = $u.DriverClass; SizeMB = [math]::Round($u.MaxDownloadSize / 1MB, 1); UpdateId = $u.Identity.UpdateID; Update = $u
            }
        }
    } catch {
        Write-LmLog "Windows Update driver search failed: $($_.Exception.Message)" 'WARN'
        return [pscustomobject]@{ Error = $_.Exception.Message; Updates = @() }
    }
    [pscustomobject]@{ Error = $null; Updates = $out }
}

function Install-LmDriverUpdates {
    param([Parameter(Mandatory)]$Updates, [switch]$DryRun, [switch]$CreateRestorePoint)
    $installed = @(); $failed = @(); $rebootNeeded = $false
    if (@($Updates).Count -eq 0) { return [pscustomobject]@{ Installed = @(); Failed = @(); RebootRequired = $false } }
    if (-not (Test-LmAdmin)) { Write-LmLog 'Driver install needs admin; skipping.' 'WARN'; return [pscustomobject]@{ Installed = @(); Failed = @($Updates | ForEach-Object Title); RebootRequired = $false } }
    if ($DryRun) { Write-LmLog "Dry run: would install $(@($Updates).Count) driver update(s)"; return [pscustomobject]@{ Installed = @(); Failed = @(); RebootRequired = $false } }
    if ($CreateRestorePoint) {
        try { Checkpoint-Computer -Description "PCleaner before driver update" -RestorePointType 'DEVICE_DRIVER_INSTALL' -ErrorAction Stop; Write-LmLog 'Restore point created' 'OK' }
        catch { Write-LmLog "Restore point failed (continuing): $($_.Exception.Message)" 'WARN' }
    }
    try {
        $session = New-Object -ComObject Microsoft.Update.Session
        $coll = New-Object -ComObject Microsoft.Update.UpdateColl
        foreach ($u in $Updates) { if (-not $u.Update.EulaAccepted) { $u.Update.AcceptEula() }; [void]$coll.Add($u.Update) }
        $dl = $session.CreateUpdateDownloader(); $dl.Updates = $coll; [void]$dl.Download()
        $inst = $session.CreateUpdateInstaller(); $inst.Updates = $coll
        $res = $inst.Install()
        $rebootNeeded = [bool]$res.RebootRequired
        for ($i = 0; $i -lt $coll.Count; $i++) {
            $code = $res.GetUpdateResult($i).ResultCode   # 2 = succeeded, 3 = succeeded with errors
            if ($code -eq 2 -or $code -eq 3) { $installed += $coll.Item($i).Title } else { $failed += $coll.Item($i).Title }
        }
    } catch { Write-LmLog "Driver install failed: $($_.Exception.Message)" 'ERROR'; $failed += 'install batch' }
    [pscustomobject]@{ Installed = $installed; Failed = $failed; RebootRequired = $rebootNeeded }
}

# ---------------------------------------------------------------------------------------------
# Vendor driver checks (NVIDIA lookup API, ASUS support API, links for the rest)
# ---------------------------------------------------------------------------------------------

function ConvertTo-LmNvidiaVersion {
    # Windows driver version 32.0.16.1742 -> NVIDIA marketing version 617.42
    param([Parameter(Mandatory)][string]$DriverVersion)
    $parts = $DriverVersion -split '\.'
    if ($parts.Count -lt 4) { return $DriverVersion }
    $digits = ($parts[2] + $parts[3])
    if ($digits.Length -lt 5) { return $DriverVersion }
    $five = $digits.Substring($digits.Length - 5)
    '{0}.{1}' -f $five.Substring(0, 3).TrimStart('0'), $five.Substring(3)
}

function Compare-LmVersion {
    # -1 when A < B, 0 equal, 1 when A > B. Tolerates 'V' prefixes, zero padding and 2-5 part versions. $null when unparsable.
    param([string]$A, [string]$B)
    $norm = { param($v) $v = ([string]$v).Trim() -replace '^[Vv]', ''; $v = ($v -replace '[^0-9.]', '').Trim('.'); if (-not $v) { return $null }
        $p = @($v -split '\.' | Where-Object { $_ -ne '' } | ForEach-Object { [int64]$_ }); while ($p.Count -lt 4) { $p += 0 }; , $p }
    $pa = & $norm $A; $pb = & $norm $B
    if (-not $pa -or -not $pb) { return $null }
    $n = [math]::Max($pa.Count, $pb.Count)
    for ($i = 0; $i -lt $n; $i++) {
        $x = if ($i -lt $pa.Count) { $pa[$i] } else { 0 }; $y = if ($i -lt $pb.Count) { $pb[$i] } else { 0 }
        if ($x -lt $y) { return -1 }; if ($x -gt $y) { return 1 }
    }
    0
}

function New-LmVendorRow {
    param([string]$Source, [string]$Component, [string]$Installed, [string]$Latest, [string]$Status, [string]$Url, [string]$Date, [string]$Note)
    [pscustomobject]@{ Source = $Source; Component = $Component; Installed = $Installed; Latest = $Latest; Status = $Status; Url = $Url; Date = $Date; Note = $Note }
}

function Get-LmDisplayClassDrivers {
    # Display drivers from the class registry: works even when a GPU is switched off (Eco / MUX mode).
    $key = 'HKLM:\SYSTEM\CurrentControlSet\Control\Class\{4d36e968-e325-11ce-bfc1-08002be10318}'
    Get-ChildItem $key -ErrorAction SilentlyContinue | ForEach-Object {
        $p = Get-ItemProperty $_.PSPath -ErrorAction SilentlyContinue
        if ($p.ProviderName) { [pscustomobject]@{ Provider = $p.ProviderName; Name = $p.DriverDesc; Version = $p.DriverVersion; Date = $p.DriverDate } }
    }
}

function Get-LmNvidiaStatus {
    $gpu = Get-LmDisplayClassDrivers | Where-Object { $_.Provider -match 'NVIDIA' -and $_.Name -match 'GeForce|RTX|GTX|Quadro' } | Select-Object -First 1
    if (-not $gpu) { return @() }
    $installed = ConvertTo-LmNvidiaVersion $gpu.Version
    $notebook = $gpu.Name -match 'Laptop|Notebook|Mobile'
    try {
        $series = ([xml](Invoke-WebRequest -UseBasicParsing 'https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=2&ParentID=1' -TimeoutSec 20).Content).LookupValueSearch.LookupValues.LookupValue
        $product = $null; $psid = $null
        foreach ($s in $series) {
            $isNb = $s.Name -match 'Notebook'
            if ($notebook -ne $isNb) { continue }
            $m = [regex]::Match($gpu.Name, '(RTX|GTX|MX)\s*(\d{2})')
            if ($m.Success -and $s.Name -notmatch ("$($m.Groups[1].Value)\s*$($m.Groups[2].Value)")) { continue }
            $products = ([xml](Invoke-WebRequest -UseBasicParsing "https://www.nvidia.com/Download/API/lookupValueSearch.aspx?TypeID=3&ParentID=$($s.Value)" -TimeoutSec 20).Content).LookupValueSearch.LookupValues.LookupValue
            $product = $products | Where-Object { $_.Name -eq $gpu.Name -or $_.Name -eq "NVIDIA $($gpu.Name)" -or $gpu.Name -eq "NVIDIA $($_.Name)" } | Select-Object -First 1
            if ($product) { $psid = $s.Value; break }
        }
        if (-not $product) { return @(New-LmVendorRow 'NVIDIA' $gpu.Name $installed '' 'Not compared' 'https://www.nvidia.com/drivers' '' 'GPU not found in the NVIDIA product list') }
        $osId = if ([Environment]::OSVersion.Version.Build -ge 22000) { 135 } else { 57 }
        $u = "https://gfwsl.geforce.com/services_toolkit/services/com/nvidia/services/AjaxDriverService.php?func=DriverManualLookup&psid=$psid&pfid=$($product.Value)&osID=$osId&languageCode=1033&beta=0&isWHQL=1&dltype=-1&dch=1&upCRD=0&qnf=0&sort1=0&numberOfResults=1"
        $j = Invoke-RestMethod -UseBasicParsing $u -TimeoutSec 20
        $d = $j.IDS[0].downloadInfo
        $latest = [string]$d.Version
        $cmp = Compare-LmVersion $installed $latest
        $status = if ($null -eq $cmp) { 'Not compared' } elseif ($cmp -lt 0) { 'Update available' } else { 'Up to date' }
        return @(New-LmVendorRow 'NVIDIA' $gpu.Name $installed $latest $status ([string]$d.DownloadURL) ([string]$d.ReleaseDateTime) ([Uri]::UnescapeDataString([string]$d.Name)))
    } catch { return @(New-LmVendorRow 'NVIDIA' $gpu.Name $installed '' 'Check failed' 'https://www.nvidia.com/drivers' '' $_.Exception.Message) }
}

$script:OemMatchers = @(
    @{ Title = 'MediaTek WLAN|MediaTek Wi-?Fi'; Class = 'NET'; Maker = 'MediaTek' },
    @{ Title = 'Intel.*(WLAN|Wi-?Fi|Wireless)'; Class = 'NET'; Maker = 'Intel' },
    @{ Title = 'Realtek.*(WLAN|Wi-?Fi|Wireless)'; Class = 'NET'; Maker = 'Realtek' },
    @{ Title = 'Realtek.*(Ethernet|LAN|GbE)'; Class = 'NET'; Maker = 'Realtek'; Device = 'Ethernet|GbE|PCIe' },
    @{ Title = 'MediaTek Bluetooth'; Class = 'BLUETOOTH'; Maker = 'MediaTek' },
    @{ Title = 'Intel.*Bluetooth'; Class = 'BLUETOOTH'; Maker = 'Intel' },
    @{ Title = '^Realtek Audio$|Realtek.*Audio Driver|Realtek High Definition Audio'; Class = 'MEDIA'; Maker = 'Realtek'; Device = 'Audio' },
    @{ Title = 'Cirrus'; Class = 'MEDIA'; Maker = 'Cirrus' },
    @{ Title = 'AMD Graphics|AMD VGA|Radeon.*Driver'; Class = 'DISPLAY'; Maker = 'Advanced Micro Devices|AMD' },
    @{ Title = 'Intel.*Graphics'; Class = 'DISPLAY'; Maker = 'Intel' },
    @{ Title = 'AMD Chipset'; Class = 'SYSTEM'; Maker = 'Advanced Micro Devices|AMD'; Device = 'I2C|GPIO|SMBUS|AMD PCI$'; ExactOnly = $true },
    @{ Title = 'Intel Chipset|Intel.*Serial IO'; Class = 'SYSTEM'; Maker = 'Intel'; Device = 'Serial IO|I2C|GPIO|SMBus'; ExactOnly = $true },
    @{ Title = 'Touch ?Pad'; Class = 'HIDCLASS'; Maker = 'ASUS|ELAN|Synaptics' },
    @{ Title = 'Card Reader'; Class = '.*'; Maker = 'Realtek|Alcor|Genesys'; Device = 'Card Reader|USB 3.0 Reader|RTS5' },
    @{ Title = 'System Control Interface'; Class = 'SYSTEM'; Maker = 'ASUS'; Device = 'System Control Interface' },
    @{ Title = 'Armoury Crate Control Interface'; Class = 'SYSTEM'; Maker = 'ASUS'; Device = 'Armoury Crate' },
    @{ Title = 'Camera'; Class = 'CAMERA|IMAGE'; Maker = 'Realtek|Sonix|Azurewave|Chicony|IMC' }
)

function Compare-LmOemDrivers {
    # Pure matcher: OEM download entries (Title, Version, Category, Url, Date) vs the installed inventory -> vendor rows.
    param([Parameter(Mandatory)]$OemFiles, [Parameter(Mandatory)]$Inventory, [string]$Source = 'OEM')
    $rows = @()
    $skipCategories = 'Software and Utility', 'Utilities', 'BIOS'
    $byTitle = @{}
    foreach ($f in @($OemFiles)) {
        if (-not $f.Title) { continue }
        if ($f.Version -match 'MS store|Microsoft Store') { continue }
        if ($skipCategories -contains $f.Category -and $f.Title -notmatch 'Control Interface') { continue }
        if ($f.Title -match 'NVIDIA') { continue }   # NVIDIA is checked directly against NVIDIA
        if (-not $byTitle.ContainsKey($f.Title) -or (Compare-LmVersion $f.Version $byTitle[$f.Title].Version) -gt 0) { $byTitle[$f.Title] = $f }
    }
    foreach ($f in ($byTitle.Values | Sort-Object Category, Title)) {
        $matcher = $script:OemMatchers | Where-Object { $f.Title -match $_.Title } | Select-Object -First 1
        $installed = $null
        if ($matcher) {
            $cands = @($Inventory | Where-Object { $_.DeviceClass -match "^($($matcher.Class))$" -and $_.Manufacturer -match $matcher.Maker -and (-not $matcher.Device -or $_.DeviceName -match $matcher.Device) })
            if ($cands.Count) { $installed = ($cands | Sort-Object { $v = $_.DriverVersion; $parts = @($v -split '\.' | ForEach-Object { try { [int64]$_ } catch { 0 } }); while ($parts.Count -lt 4) { $parts += 0 }; '{0:D6}.{1:D6}.{2:D6}.{3:D6}' -f $parts[0], $parts[1], $parts[2], $parts[3] } -Descending | Select-Object -First 1) }
        }
        $latest = ([string]$f.Version) -replace '^[Vv]', ''
        if ($installed -and $matcher.ExactOnly) {
            # Chipset packages bundle many small drivers; only an exact version hit is meaningful.
            $hit = $cands | Where-Object { (Compare-LmVersion $_.DriverVersion $latest) -eq 0 } | Select-Object -First 1
            if ($hit) { $rows += New-LmVendorRow $Source $f.Title $hit.DriverVersion $latest 'Up to date' $f.Url $f.Date $hit.DeviceName }
            else { $rows += New-LmVendorRow $Source $f.Title $installed.DriverVersion $latest 'Not compared' $f.Url $f.Date "package bundles several drivers; newest installed part is $($installed.DeviceName)" }
        } elseif ($installed) {
            $cmp = Compare-LmVersion $installed.DriverVersion $latest
            $status = if ($null -eq $cmp) { 'Not compared' } elseif ($cmp -lt 0) { 'Update available' } else { 'Up to date' }
            $rows += New-LmVendorRow $Source $f.Title $installed.DriverVersion $latest $status $f.Url $f.Date $installed.DeviceName
        } else {
            $rows += New-LmVendorRow $Source $f.Title '' $latest 'Not compared' $f.Url $f.Date "$($f.Category): no matching installed driver found"
        }
    }
    $rows
}

function Get-LmAsusDriverStatus {
    param([Parameter(Mandatory)][string]$Model, [Parameter(Mandatory)]$Inventory)
    $m = [regex]::Match($Model, '([A-Z]{1,3}\d{3,4}[A-Z]{0,3})'); if (-not $m.Success) { return @() }
    $code = $m.Groups[1].Value
    try {
        $osid = if ([Environment]::OSVersion.Version.Build -ge 22000) { 52 } else { 45 }
        $j = Invoke-RestMethod -UseBasicParsing "https://www.asus.com/support/api/product.asmx/GetPDDrivers?website=global&model=$code&pdhashedid=&cpu=&osid=$osid" -TimeoutSec 30 -Headers @{ 'User-Agent' = 'Mozilla/5.0'; 'Accept' = 'application/json' }
        if (-not $j.Result -or -not $j.Result.Obj) { return @(New-LmVendorRow 'ASUS' $Model '' '' 'Check failed' "https://www.asus.com/supportonly/$code/helpdesk_download/" '' 'ASUS returned no driver list for this model') }
        $files = @()
        foreach ($cat in $j.Result.Obj) { foreach ($f in $cat.Files) { $url = ''; if ($f.DownloadUrl) { $url = [string]$f.DownloadUrl.Global }; $files += [pscustomobject]@{ Title = $f.Title; Version = $f.Version; Category = $cat.Name; Url = $url; Date = $f.ReleaseDate } } }
        return @(Compare-LmOemDrivers -OemFiles $files -Inventory $Inventory -Source 'ASUS')
    } catch { return @(New-LmVendorRow 'ASUS' $Model '' '' 'Check failed' "https://www.asus.com/supportonly/$code/helpdesk_download/" '' $_.Exception.Message) }
}

function Get-LmVendorDriverChecks {
    param([Parameter(Mandatory)]$Inventory)
    $rows = @()
    $rows += @(Get-LmNvidiaStatus)
    $cs = Get-CimInstance Win32_ComputerSystem -ErrorAction SilentlyContinue
    $maker = [string]$cs.Manufacturer; $model = [string]$cs.Model
    if ($maker -match 'ASUS') { $rows += @(Get-LmAsusDriverStatus -Model $model -Inventory $Inventory) }
    elseif ($maker) {
        $link = switch -Regex ($maker) {
            'Dell' { 'https://www.dell.com/support/home/?app=drivers' } 'HP|Hewlett' { 'https://support.hp.com/drivers' } 'Lenovo' { 'https://support.lenovo.com/' }
            'Acer' { 'https://www.acer.com/support' } 'MSI|Micro-Star' { 'https://www.msi.com/support' } 'Razer' { 'https://mysupport.razer.com/' } 'Samsung' { 'https://www.samsung.com/support/' } default { '' } }
        $rows += New-LmVendorRow $maker $model '' '' 'Not compared' $link '' 'OEM catalogue check is only automated for ASUS; use the link to compare by hand'
    }
    $covered = @($rows | Where-Object { $_.Status -ne 'Not compared' } | ForEach-Object Component)
    $amdGpu = $Inventory | Where-Object { $_.DeviceClass -eq 'DISPLAY' -and $_.Manufacturer -match 'Advanced Micro|AMD' } | Select-Object -First 1
    if ($amdGpu -and -not ($rows | Where-Object { $_.Status -ne 'Not compared' -and $_.Component -match 'AMD Graphics' })) { $rows += New-LmVendorRow 'AMD' $amdGpu.DeviceName $amdGpu.DriverVersion '' 'Not compared' 'https://www.amd.com/en/support/download/drivers.html' '' 'AMD has no public lookup; Adrenalin checks itself' }
    $intel = $Inventory | Where-Object { $_.DeviceClass -in 'NET', 'DISPLAY', 'BLUETOOTH' -and $_.Manufacturer -match 'Intel' } | Select-Object -First 1
    if ($intel -and -not ($rows | Where-Object { $_.Status -ne 'Not compared' -and $_.Component -match 'Intel' })) { $rows += New-LmVendorRow 'Intel' $intel.DeviceName $intel.DriverVersion '' 'Not compared' 'https://www.intel.com/content/www/us/en/support/detect.html' '' 'Use the Intel Driver and Support Assistant link' }
    $rows
}

# ---------------------------------------------------------------------------------------------
# Services
# ---------------------------------------------------------------------------------------------

function Get-LmServiceAudit {
    # Explains an empty candidate list: how many running services fell into each exclusion bucket.
    param([Parameter(Mandatory)]$Services, [Parameter(Mandatory)][hashtable]$Samples, [Parameter(Mandatory)][hashtable]$Config, [string[]]$VisibleAppPaths = @())
    $cpuT = [double]$Config.cpuPercentThreshold; $memT = [double]$Config.memoryMBThreshold
    $never = @($Config.neverTouch); $optional = @($Config.optionalAutoServices)
    $a = [ordered]@{ Running = 0; Protected = 0; SharedHost = 0; HasDependents = 0; BelowThreshold = 0; VendorAppOpen = 0; AutoNotOptedIn = 0; Candidates = 0 }
    foreach ($s in @($Services)) {
        if ($s.State -ne 'Running') { continue }
        $a.Running++
        if ($never -contains $s.Name) { $a.Protected++; continue }
        if ($s.SharedHost) { $a.SharedHost++; continue }
        if (@($s.RunningDependents).Count -gt 0) { $a.HasDependents++; continue }
        $cpu = 0.0; $mem = 0.0
        if ($s.ProcessId -and $Samples.ContainsKey([int]$s.ProcessId)) { $cpu = [double]$Samples[[int]$s.ProcessId].CpuPercent; $mem = [double]$Samples[[int]$s.ProcessId].WorkingSetMB }
        if ($cpu -lt $cpuT -and $mem -lt $memT) { $a.BelowThreshold++; continue }
        if (Test-LmVendorAppVisible -ServiceExePath $s.ExePath -VisibleAppPaths $VisibleAppPaths) { $a.VendorAppOpen++; continue }
        if ($s.StartMode -ne 'Manual' -and -not ($optional -contains $s.Name)) { $a.AutoNotOptedIn++; continue }
        $a.Candidates++
    }
    [pscustomobject]$a
}

function Get-LmProcessSamples {
    # Two snapshots N seconds apart -> per-PID CPU percent (all cores = 100) and working set MB.
    param([int]$Seconds = 8)
    $cores = [Environment]::ProcessorCount
    $first = @{}
    foreach ($p in Get-Process) { try { $first[$p.Id] = $p.TotalProcessorTime.TotalMilliseconds } catch { } }
    Start-Sleep -Seconds $Seconds
    $samples = @{}
    foreach ($p in Get-Process) {
        $cpu = 0.0
        try {
            if ($first.ContainsKey($p.Id) -and $null -ne $p.TotalProcessorTime) {
                $delta = $p.TotalProcessorTime.TotalMilliseconds - $first[$p.Id]
                $cpu = [math]::Round(100.0 * $delta / ($Seconds * 1000.0 * $cores), 2)
            }
        } catch { }
        $path = $null; try { $path = $p.Path } catch { }
        $samples[$p.Id] = @{ Name = $p.ProcessName; CpuPercent = $cpu; WorkingSetMB = [math]::Round($p.WorkingSet64 / 1MB, 1); Path = $path; HasWindow = ($p.MainWindowHandle -ne 0) }
    }
    $samples
}

function ConvertFrom-LmServicePath {
    param([string]$PathName)
    if (-not $PathName) { return $null }
    $s = $PathName.Trim()
    if ($s.StartsWith('"')) { $end = $s.IndexOf('"', 1); if ($end -gt 0) { return $s.Substring(1, $end - 1) } }
    $m = [regex]::Match($s, '^(.*?\.exe)(\s|$)', 'IgnoreCase')
    if ($m.Success) { return $m.Groups[1].Value }
    return ($s -split '\s+')[0]
}

function Get-LmServiceInventory {
    $svcs = @(Get-CimInstance Win32_Service -ErrorAction SilentlyContinue)
    $byPid = @{}
    foreach ($s in $svcs) { if ($s.ProcessId) { if (-not $byPid.ContainsKey($s.ProcessId)) { $byPid[$s.ProcessId] = 0 }; $byPid[$s.ProcessId]++ } }
    foreach ($s in $svcs) {
        $exe = ConvertFrom-LmServicePath $s.PathName
        $shared = ($exe -like '*\svchost.exe') -or ($s.ProcessId -and $byPid[$s.ProcessId] -gt 1)
        $deps = @()
        try { $deps = @((Get-Service -Name $s.Name -ErrorAction Stop).DependentServices | Where-Object { $_.Status -eq 'Running' } | ForEach-Object Name) } catch { }
        [pscustomobject]@{
            Name = $s.Name; DisplayName = $s.DisplayName; State = $s.State; StartMode = $s.StartMode; ProcessId = $s.ProcessId
            ExePath = $exe; SharedHost = $shared; RunningDependents = $deps; Description = $s.Description
        }
    }
}

function Get-LmVendorRoot {
    # "Vendor folder" = first directory level under Program Files / Program Files (x86) / ProgramData / LocalAppData\Programs.
    param([string]$ExePath)
    if (-not $ExePath) { return $null }
    $roots = @($env:ProgramFiles, ${env:ProgramFiles(x86)}, $env:ProgramData, (Join-Path $env:LOCALAPPDATA 'Programs')) | Where-Object { $_ }
    foreach ($root in $roots) {
        $prefix = $root.TrimEnd('\') + '\'
        if ($ExePath.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) {
            $rest = $ExePath.Substring($prefix.Length)
            $parts = $rest -split '\\'
            if ($parts.Count -ge 2) { return (Join-Path $root $parts[0]) }
            return $null   # exe directly in Program Files: too broad to call a vendor folder
        }
    }
    return $null
}

function Test-LmVendorAppVisible {
    param([string]$ServiceExePath, [string[]]$VisibleAppPaths = @())
    $vendor = Get-LmVendorRoot $ServiceExePath
    if (-not $vendor) { return $false }
    $prefix = $vendor.TrimEnd('\') + '\'
    foreach ($p in @($VisibleAppPaths)) {
        if ($p -and $p.StartsWith($prefix, [StringComparison]::OrdinalIgnoreCase)) { return $true }
    }
    return $false
}

function Select-LmServiceCandidates {
    # Pure selection logic. $Samples: hashtable PID -> @{CpuPercent; WorkingSetMB}. $VisibleAppPaths: exe paths of processes with a window.
    param([Parameter(Mandatory)]$Services, [Parameter(Mandatory)][hashtable]$Samples, [Parameter(Mandatory)][hashtable]$Config, [string[]]$VisibleAppPaths = @())
    $cpuT = [double]$Config.cpuPercentThreshold
    $memT = [double]$Config.memoryMBThreshold
    $never = @($Config.neverTouch); $always = @($Config.alwaysStop); $optional = @($Config.optionalAutoServices)
    $stopManual = $true; if ($Config.ContainsKey('stopIdleManualServices')) { $stopManual = [bool]$Config.stopIdleManualServices }
    $out = @()
    foreach ($s in @($Services)) {
        if ($s.State -ne 'Running') { continue }
        if ($never -contains $s.Name) { continue }
        $sample = $null; if ($s.ProcessId -and $Samples.ContainsKey([int]$s.ProcessId)) { $sample = $Samples[[int]$s.ProcessId] }
        $cpu = 0.0; $mem = 0.0
        if ($sample) { $cpu = [double]$sample.CpuPercent; $mem = [double]$sample.WorkingSetMB }
        $reason = $null
        if ($always -contains $s.Name) {
            $reason = 'on alwaysStop list'
        } else {
            if ($s.SharedHost) { continue }
            if (@($s.RunningDependents).Count -gt 0) { continue }
            $hungry = ($cpu -ge $cpuT) -or ($mem -ge $memT)
            if (-not $hungry) { continue }
            if (Test-LmVendorAppVisible -ServiceExePath $s.ExePath -VisibleAppPaths $VisibleAppPaths) { continue }
            $isOptional = $optional -contains $s.Name
            if ($s.StartMode -eq 'Manual' -and -not $stopManual -and -not $isOptional) { continue }
            if ($s.StartMode -ne 'Manual' -and -not $isOptional) { continue }
            $reason = ('{0}% CPU, {1} MB, start={2}, vendor app not open' -f $cpu, $mem, $s.StartMode)
        }
        $out += [pscustomobject]@{ Name = $s.Name; DisplayName = $s.DisplayName; StartMode = $s.StartMode; ProcessId = $s.ProcessId; ExePath = $s.ExePath; CpuPercent = $cpu; WorkingSetMB = $mem; Reason = $reason }
    }
    $out
}

function Get-LmLedger {
    param([Parameter(Mandatory)][string]$Path)
    if (-not (Test-Path $Path)) { return @() }
    try { $d = Get-Content $Path -Raw | ConvertFrom-Json; return @($d) } catch { return @() }
}

function Add-LmLedgerEntry {
    param([Parameter(Mandatory)][string]$Path, [Parameter(Mandatory)][string]$ServiceName, [string]$OldStartMode, [string]$NewStartMode)
    $entries = @(Get-LmLedger -Path $Path)
    if ($entries | Where-Object { $_.ServiceName -eq $ServiceName }) { return }
    $entries += [pscustomobject]@{ ServiceName = $ServiceName; OldStartMode = $OldStartMode; NewStartMode = $NewStartMode; When = (Get-Date).ToString('s') }
    ConvertTo-Json @($entries) | Set-Content -Path $Path -Encoding ASCII
}

function Stop-LmServices {
    param([Parameter(Mandatory)]$Candidates, [Parameter(Mandatory)][hashtable]$Config, [string]$LedgerPath, [switch]$DryRun)
    $rows = @()
    $toManual = $false; if ($Config.ContainsKey('setOptionalAutoToManual')) { $toManual = [bool]$Config.setOptionalAutoToManual }
    foreach ($c in @($Candidates)) {
        $row = [ordered]@{ Name = $c.Name; DisplayName = $c.DisplayName; CpuPercent = $c.CpuPercent; WorkingSetMB = $c.WorkingSetMB; Reason = $c.Reason; Action = ''; Result = '' }
        try {
            if ($DryRun) { $row.Action = 'would stop'; $row.Result = 'dry run' }
            else {
                Stop-Service -Name $c.Name -Force -ErrorAction Stop
                $row.Action = 'stopped'; $row.Result = 'ok'
                if ($toManual -and $c.StartMode -ne 'Manual' -and (@($Config.optionalAutoServices) -contains $c.Name)) {
                    Set-Service -Name $c.Name -StartupType Manual -ErrorAction Stop
                    if ($LedgerPath) { Add-LmLedgerEntry -Path $LedgerPath -ServiceName $c.Name -OldStartMode $c.StartMode -NewStartMode 'Manual' }
                    $row.Action = 'stopped, set to Manual'
                }
            }
            Write-LmLog ("Service {0}: {1} ({2})" -f $c.Name, $row.Action, $c.Reason) 'OK'
        } catch { $row.Action = 'stop failed'; $row.Result = $_.Exception.Message; Write-LmLog "Service $($c.Name): $($_.Exception.Message)" 'WARN' }
        $rows += [pscustomobject]$row
    }
    $rows
}

function Restore-LmServices {
    param([Parameter(Mandatory)][string]$LedgerPath, [switch]$DryRun)
    $entries = @(Get-LmLedger -Path $LedgerPath)
    foreach ($e in $entries) {
        try {
            $mode = switch ($e.OldStartMode) { 'Auto' { 'Automatic' } 'Disabled' { 'Disabled' } default { 'Manual' } }
            if (-not $DryRun) { Set-Service -Name $e.ServiceName -StartupType $mode -ErrorAction Stop }
            Write-LmLog "Reverted $($e.ServiceName) to $mode" 'OK'
        } catch { Write-LmLog "Revert $($e.ServiceName) failed: $($_.Exception.Message)" 'WARN' }
    }
    if (-not $DryRun -and (Test-Path $LedgerPath)) { Remove-Item $LedgerPath -Force }
    $entries.Count
}

function Get-LmTopProcesses {
    param([Parameter(Mandatory)][hashtable]$Samples, [int]$Top = 10)
    $Samples.GetEnumerator() | ForEach-Object { [pscustomobject]@{ Pid = $_.Key; Name = $_.Value.Name; CpuPercent = $_.Value.CpuPercent; WorkingSetMB = $_.Value.WorkingSetMB } } |
        Sort-Object CpuPercent, WorkingSetMB -Descending | Select-Object -First $Top
}

# ---------------------------------------------------------------------------------------------
# Report + notification
# ---------------------------------------------------------------------------------------------

function ConvertTo-LmHtmlTable {
    param($Rows, [string[]]$Columns)
    if (-not $Rows -or @($Rows).Count -eq 0) { return '<p class="muted">Nothing to show.</p>' }
    $sb = New-Object Text.StringBuilder
    [void]$sb.Append('<table><thead><tr>')
    foreach ($c in $Columns) { [void]$sb.Append("<th>$([Net.WebUtility]::HtmlEncode($c))</th>") }
    [void]$sb.Append('</tr></thead><tbody>')
    foreach ($r in @($Rows)) {
        [void]$sb.Append('<tr>')
        foreach ($c in $Columns) {
            $v = $r.$c
            if ($v -is [datetime]) { $v = $v.ToString('yyyy-MM-dd') }
            elseif ($v -is [array]) { $v = ($v -join ', ') }
            [void]$sb.Append("<td>$([Net.WebUtility]::HtmlEncode([string]$v))</td>")
        }
        [void]$sb.Append('</tr>')
    }
    [void]$sb.Append('</tbody></table>')
    $sb.ToString()
}

function New-LmReport {
    param([Parameter(Mandatory)][hashtable]$Result, [Parameter(Mandatory)][string]$Path)
    $css = @'
body{font-family:Segoe UI,Arial,sans-serif;margin:24px;color:#1b1b1b;background:#f6f7f9}
h1{font-size:22px;margin:0 0 4px}h2{font-size:16px;margin:28px 0 8px;border-bottom:1px solid #d9dce1;padding-bottom:4px}
.muted{color:#6b7280}.cards{display:flex;gap:12px;flex-wrap:wrap;margin:16px 0}
.card{background:#fff;border:1px solid #e3e6ea;border-radius:8px;padding:12px 16px;min-width:160px}
.card b{display:block;font-size:20px}.card span{color:#6b7280;font-size:12px}
table{border-collapse:collapse;width:100%;background:#fff;font-size:13px}th,td{border:1px solid #e3e6ea;padding:5px 8px;text-align:left;vertical-align:top}
th{background:#eef1f5}tr:nth-child(even) td{background:#fafbfc}.warn{color:#b45309}.ok{color:#15803d}
'@
    $clean = @($Result.Clean); $cleanBytes = ($clean | Measure-Object Bytes -Sum).Sum; if (-not $cleanBytes) { $cleanBytes = 0 }
    $cleanFiles = ($clean | Measure-Object Files -Sum).Sum; if (-not $cleanFiles) { $cleanFiles = 0 }
    $svc = @($Result.Services); $drv = $Result.Drivers
    $updCount = 0; if ($drv -and $drv.Updates) { $updCount = @($drv.Updates).Count }
    $mode = if ($Result.DryRun) { '<span class="warn">DRY RUN - nothing was changed</span>' } else { '<span class="ok">live run</span>' }
    $html = New-Object Text.StringBuilder
    [void]$html.Append("<!DOCTYPE html><html><head><meta charset='utf-8'><title>PCleaner report</title><style>$css</style></head><body>")
    [void]$html.Append("<h1>PCleaner report</h1><p class='muted'>$($Result.Started) on $env:COMPUTERNAME, $mode, took $($Result.DurationSeconds)s. Admin: $($Result.IsAdmin).</p>")
    [void]$html.Append("<div class='cards'><div class='card'><b>$(Format-LmSize $cleanBytes)</b><span>space reclaimed</span></div><div class='card'><b>$cleanFiles</b><span>items removed</span></div><div class='card'><b>$(@($svc).Count)</b><span>services stopped</span></div><div class='card'><b>$updCount</b><span>driver updates found</span></div></div>")
    [void]$html.Append('<h2>Cleaning</h2>'); [void]$html.Append((ConvertTo-LmHtmlTable -Rows ($clean | ForEach-Object { [pscustomobject]@{ Rule = $_.Name; Group = $_.Group; Status = $_.Status; Items = $_.Files; Size = (Format-LmSize $_.Bytes); Locked = $_.Failed; Note = $_.Note } }) -Columns 'Rule', 'Group', 'Status', 'Items', 'Size', 'Locked', 'Note'))
    [void]$html.Append('<h2>Services</h2>')
    if ($Result.ServicesNote) { [void]$html.Append("<p class='muted'>$([Net.WebUtility]::HtmlEncode($Result.ServicesNote))</p>") }
    [void]$html.Append((ConvertTo-LmHtmlTable -Rows $svc -Columns 'Name', 'DisplayName', 'CpuPercent', 'WorkingSetMB', 'Reason', 'Action', 'Result'))
    [void]$html.Append('<h3>Top processes during sampling</h3>'); [void]$html.Append((ConvertTo-LmHtmlTable -Rows $Result.TopProcesses -Columns 'Name', 'Pid', 'CpuPercent', 'WorkingSetMB'))
    [void]$html.Append('<h2>Drivers</h2>')
    if ($drv) {
        if ($drv.Error) { [void]$html.Append("<p class='warn'>Windows Update check failed: $([Net.WebUtility]::HtmlEncode($drv.Error))</p>") }
        [void]$html.Append('<h3>Updates available from Windows Update</h3>'); [void]$html.Append((ConvertTo-LmHtmlTable -Rows $drv.Updates -Columns 'Title', 'Provider', 'Class', 'Version', 'SizeMB'))
        if ($drv.Install) { [void]$html.Append("<p>Installed: $(@($drv.Install.Installed).Count). Failed: $(@($drv.Install.Failed).Count). Reboot required: $($drv.Install.RebootRequired)</p>") }
        [void]$html.Append('<h3>Vendor checks (NVIDIA, laptop maker)</h3>'); [void]$html.Append((ConvertTo-LmHtmlTable -Rows $drv.Vendor -Columns 'Source', 'Component', 'Installed', 'Latest', 'Status', 'Date', 'Note'))
        [void]$html.Append('<h3>Devices with problems</h3>'); [void]$html.Append((ConvertTo-LmHtmlTable -Rows $drv.Problems -Columns 'FriendlyName', 'Class', 'Status', 'Problem'))
        [void]$html.Append("<h3>Drivers older than $($drv.MaxAgeYears) years (informational)</h3>"); [void]$html.Append((ConvertTo-LmHtmlTable -Rows $drv.Old -Columns 'DeviceName', 'DeviceClass', 'Manufacturer', 'DriverVersion', 'DriverDate', 'AgeYears'))
    } else { [void]$html.Append('<p class="muted">Driver check skipped.</p>') }
    [void]$html.Append("<p class='muted'>Log: $($Result.LogFile)</p></body></html>")
    Set-Content -Path $Path -Value $html.ToString() -Encoding UTF8
    $Path
}

function Remove-LmOldReports {
    param([int]$Keep = 20)
    $paths = Get-LmPaths
    foreach ($dir in @($paths.Reports, $paths.Logs)) {
        Get-ChildItem $dir -File | Sort-Object LastWriteTime -Descending | Select-Object -Skip $Keep | Remove-Item -Force -ErrorAction SilentlyContinue
    }
}

function Show-LmToast {
    param([string]$Title, [string]$Message)
    try {
        [void][Windows.UI.Notifications.ToastNotificationManager, Windows.UI.Notifications, ContentType = WindowsRuntime]
        [void][Windows.Data.Xml.Dom.XmlDocument, Windows.Data.Xml.Dom.XmlDocument, ContentType = WindowsRuntime]
        $appId = '{1AC14E77-02E7-4E5D-B744-2EB1AE5198B7}\WindowsPowerShell\v1.0\powershell.exe'
        $xml = "<toast><visual><binding template='ToastGeneric'><text>$([Net.WebUtility]::HtmlEncode($Title))</text><text>$([Net.WebUtility]::HtmlEncode($Message))</text></binding></visual></toast>"
        $doc = New-Object Windows.Data.Xml.Dom.XmlDocument
        $doc.LoadXml($xml)
        [Windows.UI.Notifications.ToastNotificationManager]::CreateToastNotifier($appId).Show((New-Object Windows.UI.Notifications.ToastNotification $doc))
    } catch { Write-LmLog "Toast not shown: $($_.Exception.Message)" 'WARN' }
}

Export-ModuleMember -Function *-Lm*
