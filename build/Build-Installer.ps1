<#
.SYNOPSIS
  Compiles dist\PCleaner-<version>-Setup.exe with Inno Setup 6 (installer\PCleaner.iss).
#>
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$version = (Get-Content (Join-Path $root 'VERSION') | Select-Object -First 1).Trim()
$iscc = @(
    (Get-Command ISCC.exe -ErrorAction SilentlyContinue | Select-Object -ExpandProperty Source),
    (Join-Path $env:LOCALAPPDATA 'Programs\Inno Setup 6\ISCC.exe'),
    (Join-Path ${env:ProgramFiles(x86)} 'Inno Setup 6\ISCC.exe'),
    (Join-Path $env:ProgramFiles 'Inno Setup 6\ISCC.exe')
) | Where-Object { $_ -and (Test-Path $_) } | Select-Object -First 1
if (-not $iscc) { throw 'Inno Setup 6 not found (winget install JRSoftware.InnoSetup).' }
New-Item -ItemType Directory -Path (Join-Path $root 'dist') -Force | Out-Null
if (-not (Test-Path (Join-Path $root 'assets\PCleaner.ico'))) { & (Join-Path $root 'build\New-Icon.ps1') | Out-Null }

& $iscc /Q "/DAppVersion=$version" "/DSourceDir=$root" (Join-Path $root 'installer\PCleaner.iss')
if ($LASTEXITCODE -ne 0) { throw "ISCC failed ($LASTEXITCODE)" }
$exe = Join-Path $root "dist\PCleaner-$version-Setup.exe"
$hash = (Get-FileHash $exe -Algorithm SHA256).Hash
Set-Content -Path "$exe.sha256" -Value "$hash  $(Split-Path $exe -Leaf)" -Encoding ASCII
Write-Host "Installer: $exe ($((Get-Item $exe).Length) bytes)" -ForegroundColor Green
Write-Host "SHA256:    $hash"
