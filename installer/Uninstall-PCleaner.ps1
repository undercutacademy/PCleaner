<#
.SYNOPSIS
  Removes PCleaner: scheduled task, shortcuts, Add/Remove Programs entry, program files and (optionally) reports/logs.
#>
[CmdletBinding()]
param([switch]$Silent, [switch]$KeepData)
$ErrorActionPreference = 'Continue'
$installDir = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$dataRoot = Join-Path $env:LOCALAPPDATA 'PCleaner'

$removeData = -not $KeepData
if (-not $Silent) {
    Add-Type -AssemblyName System.Windows.Forms
    $r = [System.Windows.Forms.MessageBox]::Show("Remove PCleaner from this computer?`r`n`r`nYes = also delete reports and logs in $dataRoot`r`nNo = keep reports and logs`r`nCancel = do nothing", 'Uninstall PCleaner', 'YesNoCancel', 'Question')
    if ($r -eq 'Cancel') { exit 1 }
    $removeData = ($r -eq 'Yes')
}

# Scheduled task (needs admin; the scheduler script self-elevates and prompts)
if (Get-ScheduledTask -TaskName 'PCleaner' -ErrorAction SilentlyContinue) {
    & powershell.exe -NoProfile -ExecutionPolicy Bypass -File (Join-Path $installDir 'src\Uninstall-Schedule.ps1')
}

# Shortcuts and registry
Remove-Item (Join-Path $env:APPDATA 'Microsoft\Windows\Start Menu\Programs\PCleaner.lnk') -Force -ErrorAction SilentlyContinue
Remove-Item (Join-Path ([Environment]::GetFolderPath('Desktop')) 'PCleaner.lnk') -Force -ErrorAction SilentlyContinue
Remove-Item 'HKCU:\Software\Microsoft\Windows\CurrentVersion\Uninstall\PCleaner' -Recurse -Force -ErrorAction SilentlyContinue

if ($removeData -and (Test-Path $dataRoot)) { Remove-Item $dataRoot -Recurse -Force -ErrorAction SilentlyContinue }

# Program files: this script lives inside the folder, so hand the final delete to a detached cmd.
Write-Host "Removing $installDir"
Start-Process cmd.exe -ArgumentList "/c ping -n 3 127.0.0.1 > nul & rd /s /q `"$installDir`"" -WindowStyle Hidden
Write-Host 'PCleaner removed.' -ForegroundColor Green
