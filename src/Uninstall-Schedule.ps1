[CmdletBinding()]
param([switch]$NoElevate)
$isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
if (-not $isAdmin -and -not $NoElevate) {
    Start-Process powershell.exe -Verb RunAs -ArgumentList @('-NoProfile', '-ExecutionPolicy', 'Bypass', '-NoExit', '-File', "`"$($MyInvocation.MyCommand.Path)`"", '-NoElevate')
    exit 0
}
Unregister-ScheduledTask -TaskName 'PCleaner' -Confirm:$false -ErrorAction SilentlyContinue
Write-Host "Scheduled task 'PCleaner' removed." -ForegroundColor Green
