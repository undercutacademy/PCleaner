<#
.SYNOPSIS
  PCleaner desktop window (WPF). Elevates once, runs maintenance in hidden background processes and shows live progress.
.PARAMETER SelfTest
  Load themes and window, verify controls, exit without showing.
.PARAMETER Screenshot
  Render the window to this PNG path and exit (use -Theme and -Page to choose what to capture, -Mock for sample data).
#>
[CmdletBinding()]
param(
    [switch]$SelfTest,
    [string]$Screenshot,
    [ValidateSet('System', 'Light', 'Dark')][string]$Theme,
    [ValidateSet('Health', 'Clean', 'Perf', 'Drivers', 'Reports', 'Settings')][string]$Page = 'Health',
    [switch]$Mock,
    [switch]$NoElevate
)

$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$entry = Join-Path $here 'Invoke-Maintenance.ps1'
$uiDir = Join-Path $here 'ui'
$dataRoot = Join-Path $env:LOCALAPPDATA 'PCleaner'
$settingsPath = Join-Path $root 'config\settings.json'
$rulesPath = Join-Path $root 'config\rules.json'
$version = '1.0.0'; if (Test-Path (Join-Path $root 'VERSION')) { $version = (Get-Content (Join-Path $root 'VERSION') | Select-Object -First 1).Trim() }

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
$needsSta = [Threading.Thread]::CurrentThread.GetApartmentState() -ne 'STA'
if ((-not $isAdmin -and -not $NoElevate -and -not $SelfTest -and -not $Screenshot) -or $needsSta) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-STA', '-WindowStyle', 'Hidden', '-File', "`"$($MyInvocation.MyCommand.Path)`"", '-NoElevate')
    if ($SelfTest) { $argList += '-SelfTest' }
    if ($Screenshot) { $argList += @('-Screenshot', "`"$Screenshot`"", '-Page', $Page); if ($Theme) { $argList += @('-Theme', $Theme) }; if ($Mock) { $argList += '-Mock' } }
    $verb = if ($isAdmin -or $NoElevate -or $SelfTest -or $Screenshot) { 'Open' } else { 'RunAs' }
    try { $p = Start-Process powershell.exe -Verb $verb -ArgumentList $argList -PassThru -Wait:($SelfTest -or [bool]$Screenshot); if ($SelfTest -or $Screenshot) { exit $p.ExitCode }; exit 0 }
    catch { if ($needsSta) { throw 'PCleaner needs an STA thread: run powershell.exe -STA -File PCleaner.ps1' } }
}

Add-Type -AssemblyName PresentationFramework, PresentationCore, WindowsBase, System.Xaml
Import-Module (Join-Path $here 'LaptopMaintenance.psm1') -Force

# ----------------------------------------------------------------------------- state
$script:config = Get-LmConfig -Path $settingsPath
$script:rules = Get-LmRules -Path $rulesPath
$script:runProc = $null
$script:runId = $null
$script:runTasks = @()
$script:runDry = $true
$script:runLabel = ''
$script:lastSummary = $null
$script:themeName = 'Dark'

function Save-Settings { try { $script:config | ConvertTo-Json -Depth 10 | Set-Content -Path $settingsPath -Encoding ASCII } catch { } }

# ----------------------------------------------------------------------------- XAML + themes
function Import-Xaml([string]$Path) {
    $xml = [xml](Get-Content -Path $Path -Raw)
    [Windows.Markup.XamlReader]::Load((New-Object System.Xml.XmlNodeReader $xml))
}
$app = [Windows.Application]::Current
if (-not $app) { $app = New-Object Windows.Application; $app.ShutdownMode = 'OnMainWindowClose' }
$stylesDict = Import-Xaml (Join-Path $uiDir 'Styles.xaml')

function Resolve-ThemeName([string]$Mode) {
    if ($Mode -eq 'Light' -or $Mode -eq 'Dark') { return $Mode }
    try { $v = Get-ItemPropertyValue 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Themes\Personalize' -Name AppsUseLightTheme -ErrorAction Stop; if ($v -eq 1) { return 'Light' } } catch { }
    'Dark'
}
function Set-Theme([string]$Mode) {
    $name = Resolve-ThemeName $Mode
    $dict = Import-Xaml (Join-Path $uiDir "Theme.$name.xaml")
    $app.Resources.MergedDictionaries.Clear()
    [void]$app.Resources.MergedDictionaries.Add($dict)
    [void]$app.Resources.MergedDictionaries.Add($stylesDict)
    $script:themeName = $name
    if ($script:window) {
        $script:window.FindName('BtnTheme').Content = $(if ($name -eq 'Dark') { [char]0xE706 } else { [char]0xE708 })
        $glow = $script:window.FindName('RingGlow'); if ($glow -and $app.Resources['RingGlowColor']) { $glow.Color = $app.Resources['RingGlowColor'] }
    }
}
if (-not $script:config.ContainsKey('ui')) { $script:config.ui = @{} }
if (-not $script:config.ui.ContainsKey('theme')) { $script:config.ui.theme = 'System' }
$themeMode = $script:config.ui.theme; if ($Theme) { $themeMode = $Theme }
Set-Theme $themeMode

$window = Import-Xaml (Join-Path $uiDir 'Main.xaml')
$script:window = $window
$window.MaxHeight = [Windows.SystemParameters]::MaximizedPrimaryScreenHeight
$window.MaxWidth = [Windows.SystemParameters]::MaximizedPrimaryScreenWidth
function C([string]$Name) { $window.FindName($Name) }
$iconPath = Join-Path $root 'assets\PCleaner.ico'; $pngPath = Join-Path $root 'assets\PCleaner.png'
if (Test-Path $iconPath) { try { $window.Icon = New-Object Windows.Media.Imaging.BitmapImage ([Uri]$iconPath) } catch { } }
if (Test-Path $pngPath) { try { (C 'LogoImage').Source = New-Object Windows.Media.Imaging.BitmapImage ([Uri]$pngPath) } catch { } }
Set-Theme $themeMode

# ----------------------------------------------------------------------------- chrome
(C 'BtnMin').Add_Click({ $window.WindowState = 'Minimized' })
(C 'BtnMax').Add_Click({ $window.WindowState = $(if ($window.WindowState -eq 'Maximized') { 'Normal' } else { 'Maximized' }) })
(C 'BtnClose').Add_Click({ $window.Close() })
(C 'BtnTheme').Add_Click({
        $next = if ($script:themeName -eq 'Dark') { 'Light' } else { 'Dark' }
        $script:config.ui.theme = $next; Save-Settings; Set-Theme $next
        (C 'ThemeLight').IsChecked = ($next -eq 'Light'); (C 'ThemeDark').IsChecked = ($next -eq 'Dark'); (C 'ThemeSystem').IsChecked = $false
    })
(C 'VersionText').Text = "Version $version"
(C 'AdminBadgeText').Text = if ($isAdmin) { 'Administrator' } else { 'Limited: no admin rights' }
(C 'AboutText').Text = "PCleaner $version. A local replacement for CCleaner's cleaner, performance optimizer and driver check.`nProgram folder: $root`nData folder: $dataRoot`nMIT License."

# ----------------------------------------------------------------------------- navigation
$pages = @{ Health = 'PageHealth'; Clean = 'PageClean'; Perf = 'PagePerf'; Drivers = 'PageDrivers'; Reports = 'PageReports'; Settings = 'PageSettings' }
function Show-Page([string]$Key) {
    foreach ($k in $pages.Keys) { (C $pages[$k]).Visibility = $(if ($k -eq $Key) { 'Visible' } else { 'Collapsed' }) }
    if ($Key -eq 'Reports') { Update-Reports }
    if ($Key -eq 'Settings') { Update-ScheduleStatus }
}
foreach ($pair in @(@('NavHealth', 'Health'), @('NavClean', 'Clean'), @('NavPerf', 'Perf'), @('NavDrivers', 'Drivers'), @('NavReports', 'Reports'), @('NavSettings', 'Settings'))) {
    $key = $pair[1]
    (C $pair[0]).Add_Checked({ Show-Page $this.Tag2 })
    (C $pair[0]) | Add-Member -NotePropertyName Tag2 -NotePropertyValue $key -Force
}

# ----------------------------------------------------------------------------- health ring
$ringArc = C 'RingArc'; $ringRotate = C 'RingRotate'; $ringGlow = C 'RingGlow'
function Set-Ring([double]$Pct, [string]$BrushKey = 'AccentBrush') {
    if ($Pct -lt 0) { $Pct = 0 }; if ($Pct -gt 0.9999) { $Pct = 0.9999 }
    $cx = 130.0; $cy = 130.0; $r = 114.0
    if ($Pct -le 0.001) { $ringArc.Data = $null; return }
    $a0 = -90.0; $a1 = -90.0 + 360.0 * $Pct
    $p0 = New-Object Windows.Point ($cx + $r * [math]::Cos($a0 * [math]::PI / 180)), ($cy + $r * [math]::Sin($a0 * [math]::PI / 180))
    $p1 = New-Object Windows.Point ($cx + $r * [math]::Cos($a1 * [math]::PI / 180)), ($cy + $r * [math]::Sin($a1 * [math]::PI / 180))
    $fig = New-Object Windows.Media.PathFigure; $fig.StartPoint = $p0; $fig.IsClosed = $false
    $seg = New-Object Windows.Media.ArcSegment; $seg.Point = $p1; $seg.Size = New-Object Windows.Size $r, $r; $seg.SweepDirection = 'Clockwise'; $seg.IsLargeArc = ($Pct -gt 0.5)
    [void]$fig.Segments.Add($seg)
    $geo = New-Object Windows.Media.PathGeometry; [void]$geo.Figures.Add($fig)
    $ringArc.Data = $geo
    $ringArc.SetResourceReference([Windows.Shapes.Shape]::StrokeProperty, $BrushKey)
}
function Start-RingSpin {
    Set-Ring 0.28
    $anim = New-Object Windows.Media.Animation.DoubleAnimation 0, 360, ([TimeSpan]::FromSeconds(1.4))
    $anim.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $ringRotate.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $anim)
    $glow = New-Object Windows.Media.Animation.DoubleAnimation 0.15, 0.7, ([TimeSpan]::FromSeconds(0.9)); $glow.AutoReverse = $true; $glow.RepeatBehavior = [Windows.Media.Animation.RepeatBehavior]::Forever
    $ringGlow.BeginAnimation([Windows.Media.Effects.DropShadowEffect]::OpacityProperty, $glow)
}
function Stop-RingSpin([double]$FinalPct, [string]$BrushKey = 'AccentBrush') {
    $ringRotate.BeginAnimation([Windows.Media.RotateTransform]::AngleProperty, $null); $ringRotate.Angle = 0
    $ringGlow.BeginAnimation([Windows.Media.Effects.DropShadowEffect]::OpacityProperty, $null); $ringGlow.Opacity = 0.35
    Set-Ring $FinalPct $BrushKey
}

# ----------------------------------------------------------------------------- summaries
function Get-LatestSummary {
    $dir = Join-Path $dataRoot 'reports'
    if (-not (Test-Path $dir)) { return $null }
    $f = Get-ChildItem $dir -Filter 'summary_*.json' -File -ErrorAction SilentlyContinue | Sort-Object LastWriteTime -Descending | Select-Object -First 1
    if (-not $f) { return $null }
    try { Get-Content $f.FullName -Raw | ConvertFrom-Json } catch { $null }
}
function Set-Items([string]$TableName, [string]$EmptyName, $Rows) {
    $rows = @($Rows)
    (C $TableName).ItemsSource = $rows
    if ($EmptyName) { (C $EmptyName).Visibility = $(if ($rows.Count -eq 0) { 'Visible' } else { 'Collapsed' }) }
}
function Apply-Summary($s, [bool]$Fresh) {
    if (-not $s) { return }
    $script:lastSummary = $s
    $dry = [bool]$s.dryRun
    $bytes = [double]$s.totals.bytes; $sizeText = Format-LmSize $bytes
    $svcCount = @($s.services).Count; $svcStopped = @($s.services | Where-Object { $_.Action -like 'stopped*' }).Count
    $updCount = 0; if ($s.drivers -and $s.drivers.updates) { $updCount = @($s.drivers.updates).Count }
    $tasks = @($s.tasks)
    # Health page
    if ($tasks -contains 'Clean') {
        (C 'RingValue').Text = $sizeText
        (C 'RingLabel').Text = $(if ($dry) { 'ready to reclaim' } else { 'reclaimed' })
        (C 'CardJunk').Text = $sizeText; (C 'CardJunkSub').Text = "$($s.totals.items) items" + $(if ($dry) { ' found' } else { ' removed' })
    }
    if ($tasks -contains 'Services') { (C 'CardServices').Text = "$svcCount"; (C 'CardServicesSub').Text = $(if ($dry) { 'would be stopped' } elseif ($svcCount) { "$svcStopped stopped" } else { 'none above your limits' }) }
    if ($tasks -contains 'Drivers') { (C 'CardDrivers').Text = "$updCount"; (C 'CardDriversSub').Text = $(if ($s.drivers -and $s.drivers.error) { 'check failed, see report' } elseif ($updCount) { 'offered by Windows Update' } else { 'everything is current' }) }
    $when = $s.started
    (C 'HealthLastRun').Text = "Last run $when" + $(if ($dry) { ' (analysis only)' } else { '' }) + ". Took $($s.durationSeconds)s."
    if ($Fresh) {
        if ($dry) { (C 'HealthStatus').Text = "Analysis complete: $sizeText of junk, $svcCount idle service(s), $updCount driver update(s)."; (C 'HealthHeadline').Text = $(if ($bytes -gt 500MB -or $svcCount -gt 0) { 'Room to improve.' } else { 'Looking good.' }) }
        else { (C 'HealthStatus').Text = "Done: reclaimed $sizeText, stopped $svcStopped service(s)."; (C 'HealthHeadline').Text = 'All tidy.' }
    }
    # Clean page
    $cleanRows = @($s.clean | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Status = $_.Status; Files = $_.Files; SizeText = (Format-LmSize ([double]$_.Bytes)) } })
    if ($tasks -contains 'Clean') { Set-Items 'CleanTable' 'CleanEmpty' $cleanRows; (C 'CleanResultsTitle').Text = $(if ($dry) { "Analysis: $sizeText can go" } else { "Cleaned $sizeText" }) }
    # Perf page
    if ($tasks -contains 'Services') {
        $svcRows = @($s.services | ForEach-Object { [pscustomobject]@{ DisplayName = $_.DisplayName; Reason = $_.Reason; CpuPercent = $_.CpuPercent; MemoryText = ('{0} MB' -f $_.WorkingSetMB); Action = $_.Action } })
        Set-Items 'PerfTable' 'PerfEmpty' $svcRows
        (C 'PerfTitle').Text = $(if ($svcRows.Count -eq 0) { 'No idle services above your limits' } elseif ($dry) { "$($svcRows.Count) service(s) would be stopped" } else { "$svcStopped service(s) stopped" })
        if ($svcRows.Count -eq 0) {
            $au = $s.servicesAudit
            (C 'PerfEmpty').Text = if ($au) { "Looked at $($au.Running) running services: $($au.Protected) protected Windows or security services, $($au.SharedHost) shared hosts, $($au.HasDependents) with dependents, $($au.BelowThreshold) below your CPU and memory limits, $($au.VendorAppOpen) in use, $($au.AutoNotOptedIn) automatic services not opted in. Nothing left to stop." } else { 'Everything running is either in use, protected, or below your CPU and memory limits.' }
        }
        Set-Items 'ProcTable' $null @($s.topProcesses | ForEach-Object { [pscustomobject]@{ Name = $_.Name; Pid = $_.Pid; CpuPercent = $_.CpuPercent; MemoryText = ('{0} MB' -f $_.WorkingSetMB) } })
    }
    # Drivers page
    if ($tasks -contains 'Drivers' -and $s.drivers) {
        $d = $s.drivers
        Set-Items 'DrvTable' 'DrvEmpty' @($d.updates | ForEach-Object { [pscustomobject]@{ Title = $_.Title; Provider = $_.Provider; Class = $_.Class; Version = $_.Version; SizeText = ('{0} MB' -f $_.SizeMB) } })
        (C 'DrvTitle').Text = $(if ($d.error) { 'Windows Update check failed' } elseif ($updCount -eq 0) { 'Drivers are up to date' } else { "$updCount update(s) available" })
        if ($d.error) { (C 'DrvEmpty').Text = "$($d.error)" } elseif ($updCount -eq 0) { (C 'DrvEmpty').Text = 'Windows Update has nothing newer for this hardware.' }
        Set-Items 'DrvProblemsTable' 'DrvProblemsEmpty' @($d.problems | ForEach-Object { [pscustomobject]@{ FriendlyName = $_.FriendlyName; Status = "$($_.Class): $($_.Status)" } })
        Set-Items 'DrvOldTable' 'DrvOldEmpty' @($d.old | ForEach-Object { [pscustomobject]@{ DeviceName = $_.DeviceName; Detail = "$($_.Manufacturer) $($_.DriverVersion)"; AgeText = ('{0} y' -f $_.AgeYears) } })
        (C 'DrvOldTitle').Text = "Vendor drivers older than $($d.maxAgeYears) years"
        if ($d.install) { (C 'DrvTitle').Text = "Installed $(@($d.install.Installed).Count), failed $(@($d.install.Failed).Count)" + $(if ($d.install.RebootRequired) { ' (restart needed)' } else { '' }) }
        $vendorRows = @($d.vendor | ForEach-Object {
                $brushKey = switch ($_.Status) { 'Update available' { 'WarnBrush' } 'Up to date' { 'SuccessBrush' } 'Check failed' { 'DangerBrush' } default { 'TextMutedBrush' } }
                [pscustomobject]@{
                    Component = $_.Component; Source = $_.Source; Installed = $(if ($_.Installed) { $_.Installed } else { '-' }); Latest = $(if ($_.Latest) { $_.Latest } else { '-' })
                    Status = $_.Status; Note = $_.Note; Url = $_.Url; StatusBrush = $app.Resources[$brushKey]
                    ButtonText = $(if ($_.Status -eq 'Update available') { 'Download' } else { 'Open' }); ButtonVisibility = $(if ($_.Url) { 'Visible' } else { 'Collapsed' })
                }
            })
        Set-Items 'VendorTable' 'VendorEmpty' $vendorRows
        $vendorUpd = @($vendorRows | Where-Object Status -eq 'Update available').Count
        (C 'VendorTitle').Text = $(if ($vendorRows.Count -eq 0) { 'Vendor checks' } elseif ($vendorUpd) { "Vendor checks: $vendorUpd newer driver(s) at the source" } else { 'Vendor checks: everything matched is current' })
        $updCount += $vendorUpd
        (C 'CardDrivers').Text = "$updCount"; if ($updCount) { (C 'CardDriversSub').Text = 'from Windows Update and vendors' }
    }
}

# ----------------------------------------------------------------------------- running
$actionButtons = 'BtnAnalyze', 'BtnFix', 'BtnCleanAnalyze', 'BtnCleanRun', 'BtnPerfScan', 'BtnPerfRun', 'BtnPerfRevert', 'BtnDrvScan', 'BtnDrvInstall', 'BtnSchedApply'
function Set-Busy([bool]$Busy) { foreach ($b in $actionButtons) { (C $b).IsEnabled = -not $Busy } }
function Start-Run([string[]]$Tasks, [bool]$DryRun, [string]$Label, [string]$Extra = '') {
    if ($script:runProc -and -not $script:runProc.HasExited) { return }
    $script:runId = Get-Date -Format 'yyyy-MM-dd_HHmmss'
    $script:runTasks = $Tasks; $script:runDry = $DryRun; $script:runLabel = $Label
    $flags = "-RunId $($script:runId) -Tasks $($Tasks -join ',')"
    if ($DryRun) { $flags += ' -DryRun' }
    if ($Extra) { $flags += " $Extra" }
    if (-not $script:config.report.toast) { $flags += ' -NoToast' }
    $psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$entry`" -NoElevate $flags"
    $script:runProc = Start-Process powershell.exe -ArgumentList $psArgs -WorkingDirectory $here -WindowStyle Hidden -PassThru
    Set-Busy $true
    (C 'RunStrip').Visibility = 'Visible'; (C 'BtnRunClose').Visibility = 'Collapsed'
    (C 'RunStatus').Text = "$Label started..."; (C 'RunProgress').Value = 3; (C 'RunLog').Text = ''
    (C 'HealthStatus').Text = "$Label in progress."
    (C 'RingValue').Text = ''; (C 'RingLabel').Text = $Label.ToLower()
    Start-RingSpin
}
function Read-RunLog {
    $log = Join-Path $dataRoot "logs\run_$($script:runId).log"
    if (-not (Test-Path $log)) { return @() }
    try { @(Get-Content $log -ErrorAction Stop) } catch { @() }
}
function Update-RunProgress {
    $lines = Read-RunLog
    if ($lines.Count -eq 0) { return }
    $clean = $lines -replace '^\[[^\]]+\] \[(\w+)\s*\] ', '$1  '
    (C 'RunLog').Text = ($clean | Select-Object -Last 300) -join "`r`n"; (C 'RunLog').ScrollToEnd()
    $last = ($lines | Select-Object -Last 1) -replace '^\[[^\]]+\] \[\w+\s*\] ', ''
    (C 'RunStatus').Text = $last
    $markers = @('--- Cleaning', '--- Services', '--- Drivers', 'Report:')
    $seen = 0; foreach ($m in $markers) { if ($lines | Where-Object { $_ -like "*$m*" }) { $seen++ } }
    $total = $script:runTasks.Count + 1
    (C 'RunProgress').Value = [math]::Min(96, 5 + 91.0 * $seen / $total)
}
function Complete-Run {
    Update-RunProgress
    (C 'RunProgress').Value = 100
    $summaryPath = Join-Path $dataRoot "reports\summary_$($script:runId).json"
    $s = $null; if (Test-Path $summaryPath) { try { $s = Get-Content $summaryPath -Raw | ConvertFrom-Json } catch { } }
    if ($s) {
        Apply-Summary $s $true
        $brush = if ($script:runDry) { 'AccentBrush' } else { 'SuccessBrush' }
        Stop-RingSpin 1.0 $brush
        (C 'RunStatus').Text = "$($script:runLabel) finished. " + $(if ($script:runDry) { 'Nothing was changed.' } else { 'Report saved.' })
    } else {
        Stop-RingSpin 0 'AccentBrush'; (C 'RingValue').Text = '--'; (C 'RingLabel').Text = 'run did not finish'
        (C 'RunStatus').Text = "$($script:runLabel) ended without a summary. Open details for the log."
        (C 'HealthStatus').Text = ''
    }
    (C 'BtnRunClose').Visibility = 'Visible'
    Set-Busy $false
    $script:runProc = $null
}
$timer = New-Object Windows.Threading.DispatcherTimer
$timer.Interval = [TimeSpan]::FromMilliseconds(700)
$timer.Add_Tick({
        if (-not $script:runProc) { return }
        if ($script:runProc.HasExited) { Complete-Run } else { Update-RunProgress }
    })
$timer.Start()
(C 'BtnRunDetails').Add_Click({ $w = C 'RunLogWrap'; $w.Visibility = $(if ($w.Visibility -eq 'Visible') { 'Collapsed' } else { 'Visible' }); (C 'BtnRunDetails').Content = $(if ($w.Visibility -eq 'Visible') { 'Hide details' } else { 'Show details' }) })
(C 'BtnRunClose').Add_Click({ (C 'RunStrip').Visibility = 'Collapsed' })

function Confirm([string]$Text) { [Windows.MessageBox]::Show($window, $Text, 'PCleaner', 'YesNo', 'Question') -eq 'Yes' }
(C 'BtnAnalyze').Add_Click({ Start-Run @('Clean', 'Services', 'Drivers') $true 'Analysis' })
(C 'BtnFix').Add_Click({ if (Confirm "Clean junk, stop idle services and check drivers now?`n`nA report opens when it finishes.") { Start-Run @('Clean', 'Services', 'Drivers') $false 'Clean and optimize' } })
(C 'BtnCleanAnalyze').Add_Click({ Start-Run @('Clean') $true 'Clean analysis' })
(C 'BtnCleanRun').Add_Click({ if (Confirm 'Delete the files matched by the ticked rules?') { Start-Run @('Clean') $false 'Cleaning' } })
(C 'BtnPerfScan').Add_Click({ Start-Run @('Services') $true 'Service scan' })
(C 'BtnPerfRun').Add_Click({ Start-Run @('Services') $false 'Optimization' })
(C 'BtnPerfRevert').Add_Click({ if (Confirm 'Restore the start type of every service PCleaner changed?') { Start-Run @('Services') $false 'Revert' '-Revert' } })
(C 'BtnDrvScan').Add_Click({ Start-Run @('Drivers') $true 'Driver scan' })
(C 'BtnDrvInstall').Add_Click({ if (Confirm "Install every driver update Windows Update offers?`n`nA system restore point is created first.") { Start-Run @('Drivers') $false 'Driver install' '-InstallDrivers' } })

# ----------------------------------------------------------------------------- custom clean rules
function Test-RuleOn($rule) {
    $on = $true; if ($rule.ContainsKey('default')) { $on = [bool]$rule.default }
    if (@($script:config.clean.enabledRules) -contains $rule.id) { $on = $true }
    if (@($script:config.clean.disabledRules) -contains $rule.id) { $on = $false }
    $on
}
function Set-RuleOn([string]$Id, [bool]$On, [bool]$Default) {
    $en = @($script:config.clean.enabledRules | Where-Object { $_ -ne $Id }); $dis = @($script:config.clean.disabledRules | Where-Object { $_ -ne $Id })
    if ($On -and -not $Default) { $en += $Id }
    if (-not $On -and $Default) { $dis += $Id }
    $script:config.clean.enabledRules = @($en); $script:config.clean.disabledRules = @($dis)
    Save-Settings
}
$rulesPanel = C 'RulesPanel'
$groups = @($script:rules.rules | ForEach-Object { $_.group } | Select-Object -Unique)
foreach ($g in $groups) {
    $hdr = New-Object Windows.Controls.TextBlock; $hdr.Text = $g; $hdr.Margin = '10,10,0,4'
    $hdr.SetResourceReference([Windows.Controls.TextBlock]::StyleProperty, 'TableHeader'); [void]$rulesPanel.Children.Add($hdr)
    foreach ($rule in @($script:rules.rules | Where-Object { $_.group -eq $g })) {
        $cb = New-Object Windows.Controls.CheckBox
        $cb.SetResourceReference([Windows.Controls.CheckBox]::StyleProperty, 'RuleCheck')
        $label = New-Object Windows.Controls.TextBlock; $label.Text = $rule.name; $label.TextWrapping = 'Wrap'
        $cb.Content = $label; $cb.IsChecked = (Test-RuleOn $rule); $cb.Tag = $rule.id
        $def = $true; if ($rule.ContainsKey('default')) { $def = [bool]$rule.default }
        $cb | Add-Member -NotePropertyName RuleDefault -NotePropertyValue $def -Force
        $cb.Add_Click({ Set-RuleOn $this.Tag ([bool]$this.IsChecked) $this.RuleDefault })
        [void]$rulesPanel.Children.Add($cb)
    }
}

# ----------------------------------------------------------------------------- reports
function Update-Reports {
    $dir = Join-Path $dataRoot 'reports'
    $rows = @()
    if (Test-Path $dir) {
        foreach ($f in (Get-ChildItem $dir -Filter 'report_*.html' -File | Sort-Object LastWriteTime -Descending)) {
            $summary = ''
            $sj = Join-Path $dir ($f.BaseName -replace '^report_', 'summary_') ; $sj += '.json'
            if (Test-Path $sj) { try { $s = Get-Content $sj -Raw | ConvertFrom-Json; $summary = $(if ($s.dryRun) { 'Analysis: ' } else { 'Run: ' }) + (Format-LmSize ([double]$s.totals.bytes)) + ", $(@($s.services).Count) service(s), tasks $($s.tasks -join '/')" } catch { } }
            $rows += [pscustomobject]@{ When = $f.LastWriteTime.ToString('ddd dd MMM yyyy  HH:mm'); Summary = $summary; Path = $f.FullName }
        }
    }
    Set-Items 'ReportsTable' 'ReportsEmpty' $rows
}
(C 'ReportsTable').AddHandler([Windows.Controls.Button]::ClickEvent, [Windows.RoutedEventHandler] { param($s, $e) if ($e.OriginalSource.Tag) { Start-Process $e.OriginalSource.Tag } })
(C 'VendorTable').AddHandler([Windows.Controls.Button]::ClickEvent, [Windows.RoutedEventHandler] { param($s, $e) if ($e.OriginalSource.Tag) { Start-Process $e.OriginalSource.Tag } })
(C 'BtnReportsFolder').Add_Click({ $d = Join-Path $dataRoot 'reports'; if (-not (Test-Path $d)) { New-Item -ItemType Directory $d -Force | Out-Null }; Start-Process explorer.exe $d })

# ----------------------------------------------------------------------------- settings
switch ($script:config.ui.theme) { 'Light' { (C 'ThemeLight').IsChecked = $true } 'Dark' { (C 'ThemeDark').IsChecked = $true } default { (C 'ThemeSystem').IsChecked = $true } }
foreach ($pair in @(@('ThemeSystem', 'System'), @('ThemeLight', 'Light'), @('ThemeDark', 'Dark'))) {
    $mode = $pair[1]
    (C $pair[0]) | Add-Member -NotePropertyName Mode -NotePropertyValue $mode -Force
    (C $pair[0]).Add_Checked({ if ($script:config.ui.theme -ne $this.Mode) { $script:config.ui.theme = $this.Mode; Save-Settings }; Set-Theme $this.Mode })
}
$days = 'Sunday', 'Monday', 'Tuesday', 'Wednesday', 'Thursday', 'Friday', 'Saturday'   # index = Day0..Day6 control names
function Get-SelectedDay { for ($i = 0; $i -lt 7; $i++) { if ((C "Day$i").IsChecked) { return $days[$i] } }; 'Sunday' }
$cfgDayIdx = [array]::IndexOf($days, [string]$script:config.schedule.day); if ($cfgDayIdx -lt 0) { $cfgDayIdx = 0 }
(C "Day$cfgDayIdx").IsChecked = $true
(C 'SchedTime').Text = $(if ($script:config.schedule.time) { $script:config.schedule.time } else { '10:00' })
function Get-ScheduledTaskInfoSafe { try { $t = Get-ScheduledTask -TaskName 'PCleaner' -ErrorAction Stop; $i = $t | Get-ScheduledTaskInfo; [pscustomobject]@{ Exists = $true; Next = $i.NextRunTime; Last = $i.LastRunTime; Result = $i.LastTaskResult } } catch { [pscustomobject]@{ Exists = $false } } }
function Update-ScheduleStatus {
    $t = Get-ScheduledTaskInfoSafe
    (C 'SchedSwitch').IsChecked = $t.Exists
    (C 'SchedStatus').Text = if ($t.Exists) { "On. Next run $($t.Next)." + $(if ($t.Last -and $t.Last.Year -gt 2000) { " Last run $($t.Last)." } else { '' }) } else { 'Off. Turn on to run a full maintenance every week.' }
}
(C 'BtnSchedApply').Add_Click({
        $day = Get-SelectedDay; $time = (C 'SchedTime').Text.Trim()
        if ($time -notmatch '^\d{1,2}:\d{2}$') { [Windows.MessageBox]::Show($window, 'Time must look like 10:00', 'PCleaner') | Out-Null; return }
        $script:config.schedule.day = "$day"; $script:config.schedule.time = $time; Save-Settings
        $script = if ((C 'SchedSwitch').IsChecked) { Join-Path $here 'Install-Schedule.ps1' } else { Join-Path $here 'Uninstall-Schedule.ps1' }
        $flags = if ((C 'SchedSwitch').IsChecked) { "-Day $day -Time $time" } else { '' }
        $verb = if ($isAdmin) { 'Open' } else { 'RunAs' }
        try { Start-Process powershell.exe -Verb $verb -ArgumentList "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$script`" -NoElevate $flags" -Wait } catch { }
        Update-ScheduleStatus
    })
(C 'SchedSwitch').Add_Click({ (C 'BtnSchedApply').RaiseEvent((New-Object Windows.RoutedEventArgs ([Windows.Controls.Button]::ClickEvent))) })
(C 'ToastSwitch').IsChecked = [bool]$script:config.report.toast
(C 'ToastSwitch').Add_Click({ $script:config.report.toast = [bool]$this.IsChecked; Save-Settings })
(C 'BtnEditSettings').Add_Click({ Start-Process notepad.exe $settingsPath })
(C 'BtnEditRules').Add_Click({ Start-Process notepad.exe $rulesPath })
(C 'BtnOpenData').Add_Click({ if (-not (Test-Path $dataRoot)) { New-Item -ItemType Directory $dataRoot -Force | Out-Null }; Start-Process explorer.exe $dataRoot })

# ----------------------------------------------------------------------------- initial state
$initial = Get-LatestSummary
if ($Mock) {
    $initial = [pscustomobject]@{
        started = '2026-10-17 14:08'; dryRun = $true; durationSeconds = 95; tasks = @('Clean', 'Services', 'Drivers')
        totals = @{ bytes = 6130000000; items = 18295 }
        clean = @(
            @{ Name = 'Temporary files'; Status = 'would clean'; Files = 16850; Bytes = 1510000000 }, @{ Name = 'Memory dumps and crash dumps'; Status = 'would clean'; Files = 11; Bytes = 4580000000 },
            @{ Name = 'Windows log files'; Status = 'would clean'; Files = 313; Bytes = 26900000 }, @{ Name = 'Windows Error Reporting queues'; Status = 'would clean'; Files = 99; Bytes = 10400000 },
            @{ Name = 'Microsoft Edge cache'; Status = 'skipped: msedge is running'; Files = 0; Bytes = 0 }, @{ Name = 'Google Chrome cache'; Status = 'skipped: chrome is running'; Files = 0; Bytes = 0 },
            @{ Name = 'Recycle Bin (items older than 7 days)'; Status = 'would clean'; Files = 0; Bytes = 0 }, @{ Name = 'DNS resolver cache'; Status = 'would clean'; Files = 1; Bytes = 0 })
        services = @(@{ DisplayName = 'Adobe Genuine Monitor Service'; Reason = '4.2% CPU, 160 MB, start=Manual, vendor app not open'; CpuPercent = 4.2; WorkingSetMB = 160; Action = 'would stop' })
        topProcesses = @(@{ Name = 'OAT-Setup-1.7.7'; Pid = 3488; CpuPercent = 4.39; WorkingSetMB = 40.2 }, @{ Name = 'claude'; Pid = 21488; CpuPercent = 0.5; WorkingSetMB = 915.9 }, @{ Name = 'explorer'; Pid = 5716; CpuPercent = 0.28; WorkingSetMB = 600.3 }, @{ Name = 'Code'; Pid = 17492; CpuPercent = 0.2; WorkingSetMB = 206.6 })
        servicesAudit = @{ Running = 212; Protected = 96; SharedHost = 88; HasDependents = 4; BelowThreshold = 20; VendorAppOpen = 2; AutoNotOptedIn = 1; Candidates = 1 }
        drivers = @{ error = $null; maxAgeYears = 3; vendor = @(
                @{ Source = 'NVIDIA'; Component = 'NVIDIA GeForce RTX 5070 Ti Laptop GPU'; Installed = '617.42'; Latest = '617.42'; Status = 'Up to date'; Url = 'https://www.nvidia.com/drivers'; Note = 'GeForce Game Ready Driver' },
                @{ Source = 'ASUS'; Component = 'MediaTek WLAN Driver'; Installed = '5.5.0.3548'; Latest = '5.7.0.5115'; Status = 'Update available'; Url = 'https://www.asus.com'; Note = 'MediaTek Wi-Fi 7 MT7925 Wireless LAN Card' },
                @{ Source = 'ASUS'; Component = 'Cirrus SmartAMP Driver'; Installed = '21.51.46.157'; Latest = '23.26.47.823'; Status = 'Update available'; Url = 'https://www.asus.com'; Note = 'Cirrus Logic Awesome Speaker Amps' },
                @{ Source = 'ASUS'; Component = 'MediaTek Bluetooth Driver'; Installed = '1.1045.0.566'; Latest = '1.1045.0.566'; Status = 'Up to date'; Url = 'https://www.asus.com'; Note = 'MediaTek Bluetooth Adapter' },
                @{ Source = 'ASUS'; Component = 'Parade Retimer Driver'; Installed = ''; Latest = '1.0.017.00'; Status = 'Not compared'; Url = 'https://www.asus.com'; Note = 'USB: no matching installed driver found' }
            ); updates = @(@{ Title = 'Alcor Micro USB 3.0 Card Reader'; Provider = 'Alcor Micro, Corp.'; Class = 'OtherHardware'; Version = '2015-07-09'; SizeMB = 0.7 }, @{ Title = 'ASUSTeK COMPUTER INC. Driver Update (10.1.2.2)'; Provider = 'ASUSTeK COMPUTER INC.'; Class = 'Firmware'; Version = '2025-07-23'; SizeMB = 0.2 }); problems = @(); old = @(@{ DeviceName = 'Realtek USB GbE Family Controller'; Manufacturer = 'Realtek'; DriverVersion = '10.38.1117.2019'; AgeYears = 6.9 }) }
    }
}
if ($initial) { Apply-Summary $initial $false; Set-Ring 1.0 $(if ($initial.dryRun) { 'AccentBrush' } else { 'SuccessBrush' }); $ringGlow.Opacity = 0.3 }
else { Set-Ring 0 }
Update-ScheduleStatus
Show-Page $Page
switch ($Page) { 'Clean' { (C 'NavClean').IsChecked = $true } 'Perf' { (C 'NavPerf').IsChecked = $true } 'Drivers' { (C 'NavDrivers').IsChecked = $true } 'Reports' { (C 'NavReports').IsChecked = $true } 'Settings' { (C 'NavSettings').IsChecked = $true } default { } }

if ($SelfTest) {
    $missing = @('BtnAnalyze', 'RingArc', 'RulesPanel', 'PerfTable', 'DrvTable', 'ReportsTable', 'SchedSwitch', 'RunStrip' | Where-Object { -not (C $_) })
    foreach ($t in 'Light', 'Dark') { Set-Theme $t }
    Write-Output ("SelfTest OK: {0} rule checkboxes, {1} missing controls, themes load" -f @($rulesPanel.Children | Where-Object { $_ -is [Windows.Controls.CheckBox] }).Count, $missing.Count)
    exit $(if ($missing.Count) { 1 } else { 0 })
}
if ($Screenshot) {
    $window.Add_ContentRendered({
            $window.Dispatcher.BeginInvoke([Windows.Threading.DispatcherPriority]::ApplicationIdle, [Action] {
                    Start-Sleep -Milliseconds 400
                    $w = [int]$window.ActualWidth; $h = [int]$window.ActualHeight
                    $rtb = New-Object Windows.Media.Imaging.RenderTargetBitmap $w, $h, 96, 96, ([Windows.Media.PixelFormats]::Pbgra32)
                    $rtb.Render($window)
                    $enc = New-Object Windows.Media.Imaging.PngBitmapEncoder; $enc.Frames.Add([Windows.Media.Imaging.BitmapFrame]::Create($rtb))
                    $fs = [IO.File]::Create($Screenshot); $enc.Save($fs); $fs.Close()
                    $window.Close()
                }) | Out-Null
        })
    $window.Left = -4000   # render off-screen
}
[void]$app.Run($window)
