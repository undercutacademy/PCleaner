<#
.SYNOPSIS
  Weekly laptop maintenance: clean junk, check drivers, stop idle resource-hungry services.
.EXAMPLE
  .\Invoke-Maintenance.ps1 -DryRun            # show what would happen, change nothing
  .\Invoke-Maintenance.ps1                    # full run (self-elevates)
  .\Invoke-Maintenance.ps1 -Tasks Clean       # only cleaning
  .\Invoke-Maintenance.ps1 -InstallDrivers    # also install driver updates from Windows Update
  .\Invoke-Maintenance.ps1 -Revert            # undo start-type changes made to services
#>
[CmdletBinding()]
param(
    [ValidateSet('Clean', 'Drivers', 'Services')][string[]]$Tasks = @('Clean', 'Drivers', 'Services'),
    [switch]$DryRun,
    [switch]$InstallDrivers,
    [switch]$Revert,
    [switch]$NoElevate,
    [switch]$NoToast,
    [switch]$OpenReport,
    [string]$ConfigPath,
    [string]$RulesPath,
    [string]$RunId
)

$ErrorActionPreference = 'Continue'
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
if (-not $ConfigPath) { $ConfigPath = Join-Path $root 'config\settings.json' }
if (-not $RulesPath) { $RulesPath = Join-Path $root 'config\rules.json' }

Import-Module (Join-Path $here 'LaptopMaintenance.psm1') -Force

# Self-elevate for interactive runs so service and system-folder work succeeds. The scheduled task already runs elevated.
if (-not (Test-LmAdmin) -and -not $NoElevate) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$($MyInvocation.MyCommand.Path)`"", '-NoElevate', '-OpenReport')
    $argList += @('-Tasks', ($Tasks -join ','))
    if ($DryRun) { $argList += '-DryRun' }
    if ($InstallDrivers) { $argList += '-InstallDrivers' }
    if ($Revert) { $argList += '-Revert' }
    if ($NoToast) { $argList += '-NoToast' }
    Write-Host 'Relaunching as administrator...' -ForegroundColor Yellow
    try { Start-Process powershell.exe -Verb RunAs -ArgumentList $argList; exit 0 }
    catch { Write-Host 'Elevation declined; continuing without admin (some steps will be skipped).' -ForegroundColor Yellow }
}

$started = Get-Date
if (-not $RunId) { $RunId = $started.ToString('yyyy-MM-dd_HHmmss') }
$logFile = Start-LmLog -RunId $RunId
$paths = Get-LmPaths
$config = Get-LmConfig -Path $ConfigPath
$rules = Get-LmRules -Path $RulesPath
$result = @{ Started = $started.ToString('yyyy-MM-dd HH:mm'); DryRun = [bool]$DryRun; IsAdmin = (Test-LmAdmin); LogFile = $logFile; Clean = @(); Services = @(); ServicesNote = ''; TopProcesses = @(); Drivers = $null }

if ($Revert) {
    $n = Restore-LmServices -LedgerPath $paths.Ledger -DryRun:$DryRun
    Write-LmLog "Reverted $n service start-type change(s)." 'OK'
    return
}

if ($DryRun) { Write-LmLog 'DRY RUN: nothing will be deleted, stopped or installed.' 'WARN' }

# --- Clean -----------------------------------------------------------------------------------
if ($Tasks -contains 'Clean' -and $config.clean.enabled) {
    Write-LmLog '--- Cleaning ---'
    $result.Clean = @(Invoke-LmClean -Rules $rules -Config $config -DryRun:$DryRun)
    $bytes = ($result.Clean | Measure-Object Bytes -Sum).Sum; if (-not $bytes) { $bytes = 0 }
    Write-LmLog ("Cleaning total: {0}" -f (Format-LmSize $bytes)) 'OK'
}

# --- Services --------------------------------------------------------------------------------
if ($Tasks -contains 'Services' -and $config.services.enabled) {
    Write-LmLog "--- Services (sampling $($config.services.sampleSeconds)s) ---"
    $samples = Get-LmProcessSamples -Seconds ([int]$config.services.sampleSeconds)
    $result.TopProcesses = @(Get-LmTopProcesses -Samples $samples -Top 10)
    $visible = @($samples.Values | Where-Object { $_.HasWindow -and $_.Path } | ForEach-Object Path)
    $inventory = @(Get-LmServiceInventory)
    $candidates = @(Select-LmServiceCandidates -Services $inventory -Samples $samples -Config $config.services -VisibleAppPaths $visible)
    $audit = Get-LmServiceAudit -Services $inventory -Samples $samples -Config $config.services -VisibleAppPaths $visible
    $result.ServicesAudit = $audit
    Write-LmLog ("Services examined: {0} running, {1} protected, {2} shared hosts, {3} with dependents, {4} below limits, {5} in use, {6} automatic (not opted in), {7} candidate(s)." -f $audit.Running, $audit.Protected, $audit.SharedHost, $audit.HasDependents, $audit.BelowThreshold, $audit.VendorAppOpen, $audit.AutoNotOptedIn, $audit.Candidates)
    if ($candidates.Count -eq 0) { $result.ServicesNote = 'No idle resource-hungry services found above the configured thresholds.'; Write-LmLog $result.ServicesNote }
    elseif (-not (Test-LmAdmin)) { $result.ServicesNote = "Found $($candidates.Count) candidate(s) but not running as admin; nothing stopped."; Write-LmLog $result.ServicesNote 'WARN'; $result.Services = @($candidates | ForEach-Object { [pscustomobject]@{ Name = $_.Name; DisplayName = $_.DisplayName; CpuPercent = $_.CpuPercent; WorkingSetMB = $_.WorkingSetMB; Reason = $_.Reason; Action = 'skipped'; Result = 'needs admin' } }) }
    else { $result.Services = @(Stop-LmServices -Candidates $candidates -Config $config.services -LedgerPath $paths.Ledger -DryRun:$DryRun) }
}

# --- Drivers ---------------------------------------------------------------------------------
if ($Tasks -contains 'Drivers' -and $config.drivers.enabled) {
    Write-LmLog '--- Drivers ---'
    $inv = @(Get-LmDriverInventory)
    $old = @(Get-LmOldDrivers -Inventory $inv -MaxAgeYears ([double]$config.drivers.maxDriverAgeYears) -Classes @($config.drivers.classesOfInterest))
    $problems = @(Get-LmProblemDevices)
    Write-LmLog "Drivers installed: $($inv.Count). Older than $($config.drivers.maxDriverAgeYears)y in classes of interest: $($old.Count). Devices with problems: $($problems.Count)."
    $updates = [pscustomobject]@{ Error = 'check disabled in settings'; Updates = @() }
    if ($config.drivers.checkWindowsUpdate) { Write-LmLog 'Asking Windows Update for driver updates (this can take a few minutes)...'; $updates = Find-LmDriverUpdates }
    foreach ($u in @($updates.Updates)) { Write-LmLog "Driver update available: $($u.Title)" 'WARN' }
    if (@($updates.Updates).Count -eq 0 -and -not $updates.Error) { Write-LmLog 'No driver updates offered by Windows Update.' 'OK' }
    $install = $null
    if (($InstallDrivers -or $config.drivers.installUpdates) -and @($updates.Updates).Count -gt 0) {
        $install = Install-LmDriverUpdates -Updates $updates.Updates -DryRun:$DryRun -CreateRestorePoint:([bool]$config.drivers.createRestorePointBeforeInstall)
    }
    $vendor = @()
    $doVendor = $true; if ($config.drivers.ContainsKey('vendorChecks')) { $doVendor = [bool]$config.drivers.vendorChecks }
    if ($doVendor) {
        Write-LmLog 'Checking NVIDIA and the laptop maker for newer drivers...'
        $vendor = @(Get-LmVendorDriverChecks -Inventory $inv)
        foreach ($v in $vendor) {
            $lvl = switch ($v.Status) { 'Update available' { 'WARN' } 'Check failed' { 'WARN' } default { 'INFO' } }
            Write-LmLog ("{0}: {1} installed {2}, latest {3} - {4}" -f $v.Source, $v.Component, $(if ($v.Installed) { $v.Installed } else { '?' }), $(if ($v.Latest) { $v.Latest } else { '?' }), $v.Status) $lvl
        }
    }
    $result.Drivers = @{ Updates = @($updates.Updates | Select-Object Title, Provider, Class, Version, SizeMB); Error = $updates.Error; Problems = $problems; Old = $old; MaxAgeYears = $config.drivers.maxDriverAgeYears; Install = $install; Vendor = $vendor }
}

# --- Report ----------------------------------------------------------------------------------
$result.DurationSeconds = [int]((Get-Date) - $started).TotalSeconds
$reportPath = Join-Path $paths.Reports ("report_{0}.html" -f $RunId)
New-LmReport -Result $result -Path $reportPath | Out-Null
# Machine-readable summary for the PCleaner window
$sumBytes = ($result.Clean | Measure-Object Bytes -Sum).Sum; if (-not $sumBytes) { $sumBytes = 0 }
$sumItems = ($result.Clean | Measure-Object Files -Sum).Sum; if (-not $sumItems) { $sumItems = 0 }
$summary = [ordered]@{
    runId = $RunId; started = $result.Started; dryRun = $result.DryRun; isAdmin = $result.IsAdmin; tasks = @($Tasks); durationSeconds = $result.DurationSeconds
    totals = @{ bytes = [double]$sumBytes; items = [int]$sumItems }
    clean = @($result.Clean | Select-Object Id, Name, Group, Status, Files, Bytes, Failed, Note)
    services = @($result.Services | Select-Object Name, DisplayName, CpuPercent, WorkingSetMB, Reason, Action, Result)
    servicesNote = $result.ServicesNote
    servicesAudit = $(if ($result.ContainsKey('ServicesAudit')) { $result.ServicesAudit } else { $null })
    topProcesses = @($result.TopProcesses | Select-Object Name, Pid, CpuPercent, WorkingSetMB)
    drivers = $null; reportPath = $reportPath; logPath = $logFile
}
if ($result.Drivers) {
    $summary.drivers = @{
        updates = @($result.Drivers.Updates); error = $result.Drivers.Error; maxAgeYears = $result.Drivers.MaxAgeYears
        problems = @($result.Drivers.Problems | Select-Object FriendlyName, Class, Status, Problem)
        old = @($result.Drivers.Old | Select-Object DeviceName, DeviceClass, Manufacturer, DriverVersion, AgeYears)
        vendor = @($result.Drivers.Vendor)
        install = $(if ($result.Drivers.Install) { @{ Installed = @($result.Drivers.Install.Installed); Failed = @($result.Drivers.Install.Failed); RebootRequired = [bool]$result.Drivers.Install.RebootRequired } } else { $null })
    }
}
try { $summary | ConvertTo-Json -Depth 6 | Set-Content -Path (Join-Path $paths.Reports "summary_$RunId.json") -Encoding UTF8 } catch { Write-LmLog "Summary not written: $($_.Exception.Message)" 'WARN' }
Remove-LmOldReports -Keep ([int]$config.report.keepReports)
$bytes = ($result.Clean | Measure-Object Bytes -Sum).Sum; if (-not $bytes) { $bytes = 0 }
$updCount = 0; if ($result.Drivers -and $result.Drivers.Updates) { $updCount = @($result.Drivers.Updates).Count }
if ($result.Drivers -and $result.Drivers.Vendor) { $updCount += @($result.Drivers.Vendor | Where-Object { $_.Status -eq 'Update available' }).Count }
$summary = "Reclaimed $(Format-LmSize $bytes), stopped $(@($result.Services | Where-Object { $_.Action -like 'stopped*' }).Count) service(s), $updCount driver update(s) available."
if ($DryRun) { $summary = "DRY RUN. Would reclaim $(Format-LmSize $bytes); $(@($result.Services).Count) service(s) would stop; $updCount driver update(s) available." }
Write-LmLog $summary 'OK'
Write-LmLog "Report: $reportPath"
if (-not $NoToast -and $config.report.toast) { Show-LmToast -Title 'PCleaner finished' -Message $summary }
if ($OpenReport) { Start-Process $reportPath }
