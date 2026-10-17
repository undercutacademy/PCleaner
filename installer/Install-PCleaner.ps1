<#
.SYNOPSIS
  Installs PCleaner for the current user: copies files, creates Start Menu (and optional desktop) shortcuts,
  registers an Add/Remove Programs entry, and optionally the weekly scheduled task.
.EXAMPLE
  .\Install-PCleaner.ps1                       # small dialog with options
  .\Install-PCleaner.ps1 -Silent -Schedule     # no dialog, also schedule weekly run
#>
[CmdletBinding()]
param(
    [string]$InstallDir = (Join-Path $env:LOCALAPPDATA 'Programs\PCleaner'),
    [switch]$DesktopShortcut,
    [switch]$Schedule,
    [switch]$Launch,
    [switch]$Silent
)
$ErrorActionPreference = 'Stop'
$source = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$version = '1.0.0'; if (Test-Path (Join-Path $source 'VERSION')) { $version = (Get-Content (Join-Path $source 'VERSION') | Select-Object -First 1).Trim() }
$appName = 'PCleaner'

# ----------------------------------------------------------------------------- options dialog
if (-not $Silent) {
    Add-Type -AssemblyName System.Windows.Forms; Add-Type -AssemblyName System.Drawing
    [System.Windows.Forms.Application]::EnableVisualStyles()
    $f = New-Object System.Windows.Forms.Form
    $f.Text = "Install $appName $version"; $f.StartPosition = 'CenterScreen'; $f.FormBorderStyle = 'FixedDialog'; $f.MaximizeBox = $false
    $f.ClientSize = New-Object System.Drawing.Size(460, 250); $f.Font = New-Object System.Drawing.Font('Segoe UI', 9.5)
    $icon = Join-Path $source 'assets\PCleaner.ico'; if (Test-Path $icon) { try { $f.Icon = New-Object System.Drawing.Icon($icon) } catch { } }
    $l = New-Object System.Windows.Forms.Label; $l.Text = "PCleaner will be installed for your user account in:`r`n$InstallDir"; $l.Location = New-Object System.Drawing.Point(16, 14); $l.Size = New-Object System.Drawing.Size(430, 44); $f.Controls.Add($l)
    $cbDesk = New-Object System.Windows.Forms.CheckBox; $cbDesk.Text = 'Create a desktop shortcut'; $cbDesk.Checked = $true; $cbDesk.Location = New-Object System.Drawing.Point(20, 70); $cbDesk.AutoSize = $true; $f.Controls.Add($cbDesk)
    $cbSched = New-Object System.Windows.Forms.CheckBox; $cbSched.Text = 'Run maintenance automatically every week (Sunday 10:00, needs admin approval)'; $cbSched.Checked = $true; $cbSched.Location = New-Object System.Drawing.Point(20, 98); $cbSched.AutoSize = $true; $f.Controls.Add($cbSched)
    $cbLaunch = New-Object System.Windows.Forms.CheckBox; $cbLaunch.Text = 'Open PCleaner when the installation finishes'; $cbLaunch.Checked = $true; $cbLaunch.Location = New-Object System.Drawing.Point(20, 126); $cbLaunch.AutoSize = $true; $f.Controls.Add($cbLaunch)
    $note = New-Object System.Windows.Forms.Label; $note.Text = 'Nothing is cleaned during installation. The first run should be "Analyze" (dry run).'; $note.ForeColor = [System.Drawing.Color]::Gray; $note.Location = New-Object System.Drawing.Point(16, 162); $note.Size = New-Object System.Drawing.Size(430, 20); $f.Controls.Add($note)
    $ok = New-Object System.Windows.Forms.Button; $ok.Text = 'Install'; $ok.Location = New-Object System.Drawing.Point(254, 200); $ok.Size = New-Object System.Drawing.Size(90, 32); $ok.DialogResult = 'OK'; $f.Controls.Add($ok); $f.AcceptButton = $ok
    $cancel = New-Object System.Windows.Forms.Button; $cancel.Text = 'Cancel'; $cancel.Location = New-Object System.Drawing.Point(352, 200); $cancel.Size = New-Object System.Drawing.Size(90, 32); $cancel.DialogResult = 'Cancel'; $f.Controls.Add($cancel); $f.CancelButton = $cancel
    if ($f.ShowDialog() -ne 'OK') { Write-Host 'Installation cancelled.'; exit 1 }
    $DesktopShortcut = $cbDesk.Checked; $Schedule = $cbSched.Checked; $Launch = $cbLaunch.Checked
}

# ----------------------------------------------------------------------------- copy files
Write-Host "Installing $appName $version to $InstallDir" -ForegroundColor Cyan
New-Item -ItemType Directory -Path $InstallDir -Force | Out-Null
foreach ($dir in 'src', 'assets', 'installer', 'docs') {
    $from = Join-Path $source $dir
    if (Test-Path $from) { Copy-Item $from -Destination $InstallDir -Recurse -Force }
}
foreach ($file in 'VERSION', 'README.md', 'LICENSE', 'PCleaner.exe') {
    $from = Join-Path $source $file
    if (Test-Path $from) { Copy-Item $from -Destination $InstallDir -Force }
}
# Config: never overwrite a user's edited settings; ship the new defaults next to them.
$cfgDir = Join-Path $InstallDir 'config'; New-Item -ItemType Directory -Path $cfgDir -Force | Out-Null
foreach ($name in 'settings.json', 'rules.json') {
    $from = Join-Path $source "config\$name"; $to = Join-Path $cfgDir $name
    if (Test-Path $to) { Copy-Item $from -Destination (Join-Path $cfgDir ($name -replace '\.json$', '.default.json')) -Force; Write-Host "  kept existing $name (new defaults saved as $($name -replace '\.json$', '.default.json'))" }
    else { Copy-Item $from -Destination $to -Force }
}
# Mark installed files as always-available in case the install dir is under a cloud-synced folder.
try { & attrib.exe +P -U "$InstallDir\*" /S /D | Out-Null } catch { }

# ----------------------------------------------------------------------------- shortcuts
$launcher = Join-Path $InstallDir 'src\PCleaner.ps1'
$iconFile = Join-Path $InstallDir 'assets\PCleaner.ico'
$psExe = Join-Path $env:windir 'System32\WindowsPowerShell\v1.0\powershell.exe'
$shortcutArgs = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File `"$launcher`""
$exe = Join-Path $InstallDir 'PCleaner.exe'
function New-Shortcut([string]$Path) {
    $ws = New-Object -ComObject WScript.Shell
    $sc = $ws.CreateShortcut($Path)
    if (Test-Path $exe) { $sc.TargetPath = $exe; $sc.Arguments = '' } else { $sc.TargetPath = $psExe; $sc.Arguments = $shortcutArgs }
    $sc.WorkingDirectory = $InstallDir
    $sc.Description = 'PCleaner - weekly cleanup, driver check and idle-service stop'
    if (Test-Path $iconFile) { $sc.IconLocation = "$iconFile,0" }
    $sc.Save()
}
$startMenuDir = Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs'
New-Shortcut (Join-Path $startMenuDir 'PCleaner.lnk')
Write-Host '  Start Menu shortcut created'
if ($DesktopShortcut) { New-Shortcut (Join-Path ([Environment]::GetFolderPath('Desktop')) 'PCleaner.lnk'); Write-Host '  Desktop shortcut created' }

# ----------------------------------------------------------------------------- Add/Remove Programs entry (per user, no admin needed)
$uninstaller = Join-Path $InstallDir 'installer\Uninstall-PCleaner.ps1'
$key = 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PCleaner'
New-Item -Path $key -Force | Out-Null
$sizeKB = [int]((Get-ChildItem $InstallDir -Recurse -File | Measure-Object Length -Sum).Sum / 1KB)
$props = @{
    DisplayName = 'PCleaner'; DisplayVersion = $version; Publisher = 'PCleaner authors'; InstallLocation = $InstallDir
    DisplayIcon = $iconFile; EstimatedSize = $sizeKB; NoModify = 1; NoRepair = 1
    InstallDate = (Get-Date -Format 'yyyyMMdd')
    UninstallString = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"$uninstaller`""
    QuietUninstallString = "`"$psExe`" -NoProfile -ExecutionPolicy Bypass -File `"$uninstaller`" -Silent"
}
foreach ($p in $props.GetEnumerator()) {
    $type = if ($p.Value -is [int]) { 'DWord' } else { 'String' }
    New-ItemProperty -Path $key -Name $p.Key -Value $p.Value -PropertyType $type -Force | Out-Null
}
Write-Host '  Registered in Settings > Apps > Installed apps'

# ----------------------------------------------------------------------------- schedule + launch
if ($Schedule) {
    Write-Host '  Registering weekly task (admin approval prompt)...'
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $InstallDir 'src\Install-Schedule.ps1')
}
Write-Host "Installed. Launch from the Start Menu entry 'PCleaner'." -ForegroundColor Green
if ($Launch) { if (Test-Path $exe) { Start-Process $exe -WorkingDirectory $InstallDir } else { Start-Process $psExe -ArgumentList $shortcutArgs -WorkingDirectory (Join-Path $InstallDir 'src') } }
