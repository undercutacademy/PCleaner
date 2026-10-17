<#
.SYNOPSIS
  Registers the weekly "PCleaner" scheduled task (runs elevated as the current user).
.EXAMPLE
  .\Install-Schedule.ps1                 # Sunday 10:00 from config\settings.json
  .\Install-Schedule.ps1 -Day Saturday -Time 09:30
#>
[CmdletBinding()]
param(
    [string]$Day,
    [string]$Time,
    [switch]$NoElevate
)
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$root = Split-Path -Parent $here
$entry = Join-Path $here 'Invoke-Maintenance.ps1'
$taskName = 'PCleaner'

$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate) {
    $argList = @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$($MyInvocation.MyCommand.Path)`"", '-NoElevate')
    if ($Day) { $argList += @('-Day', $Day) }
    if ($Time) { $argList += @('-Time', $Time) }
    Start-Process powershell.exe -Verb RunAs -ArgumentList $argList
    exit 0
}

$cfg = Get-Content (Join-Path $root 'config\settings.json') -Raw | ConvertFrom-Json
if (-not $Day) { $Day = $cfg.schedule.day }
if (-not $Time) { $Time = $cfg.schedule.time }

# Keep the OneDrive copy on disk so the task never hits an online-only placeholder.
try { & attrib.exe +P -U "$root\*" /S /D | Out-Null } catch { }

$psArgs = "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File `"$entry`" -NoElevate"
$action = New-ScheduledTaskAction -Execute 'powershell.exe' -Argument $psArgs -WorkingDirectory $here
$trigger = New-ScheduledTaskTrigger -Weekly -DaysOfWeek $Day -At $Time
$settings = New-ScheduledTaskSettingsSet -StartWhenAvailable -AllowStartIfOnBatteries -DontStopIfGoingOnBatteries -RunOnlyIfNetworkAvailable:$false -ExecutionTimeLimit (New-TimeSpan -Hours 2) -MultipleInstances IgnoreNew
$user = "$env:USERDOMAIN\$env:USERNAME"
$principal = New-ScheduledTaskPrincipal -UserId $user -LogonType Interactive -RunLevel Highest

Unregister-ScheduledTask -TaskName $taskName -Confirm:$false -ErrorAction SilentlyContinue
Register-ScheduledTask -TaskName $taskName -Action $action -Trigger $trigger -Settings $settings -Principal $principal -Description 'PCleaner weekly maintenance: cleanup, driver check, idle-service stop.' | Out-Null

$t = Get-ScheduledTask -TaskName $taskName
$info = $t | Get-ScheduledTaskInfo
Write-Host "Task '$taskName' registered: every $Day at $Time, runs as $user with highest privileges." -ForegroundColor Green
Write-Host "Next run: $($info.NextRunTime)"
Write-Host "Run it now with:  Start-ScheduledTask -TaskName $taskName"
