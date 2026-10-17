Import-Module Pester -MinimumVersion 3.4 -ErrorAction Stop
$here = Split-Path -Parent $MyInvocation.MyCommand.Path
$result = Invoke-Pester -Path $here -PassThru
if ($result.FailedCount -gt 0) { exit 1 } else { exit 0 }
