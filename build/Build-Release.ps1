<#
.SYNOPSIS
  Builds a GitHub release package: regenerates the icon, runs the tests, self-tests the launcher, zips dist\PCleaner-<version>.zip
#>
[CmdletBinding()]
param([switch]$SkipTests, [switch]$WithExe)
# -WithExe also compiles and packages Setup.exe / PCleaner.exe. Off by default: unsigned tiny .NET launchers draw
# machine-learning antivirus flags (7/71 on VirusTotal) while the scripts and .cmd starters scan clean. Turn it on
# once releases are code-signed (see marketing/signpath-application.md).
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$version = (Get-Content (Join-Path $root 'VERSION') | Select-Object -First 1).Trim()
$dist = Join-Path $root 'dist'
$stage = Join-Path $dist "PCleaner-$version"
$zip = Join-Path $dist "PCleaner-$version.zip"

Write-Host "Building PCleaner $version" -ForegroundColor Cyan
& (Join-Path $root 'build\New-Icon.ps1')
if ($WithExe) { & (Join-Path $root 'build\New-Launchers.ps1') }

if (-not $SkipTests) {
    Import-Module Pester -MinimumVersion 3.4
    $r = Invoke-Pester -Path (Join-Path $root 'tests') -PassThru -Quiet
    Write-Host "Tests: $($r.PassedCount)/$($r.TotalCount) passed"
    if ($r.FailedCount -gt 0) { $r.TestResult | Where-Object { -not $_.Passed } | ForEach-Object { Write-Host "  FAIL $($_.Describe) / $($_.Name)" -ForegroundColor Red }; throw 'Tests failed; release not built.' }
    $self = & powershell.exe -NoProfile -ExecutionPolicy Bypass -STA -File (Join-Path $root 'src\PCleaner.ps1') -SelfTest
    Write-Host "Launcher: $self"
    if ($self -notmatch '^SelfTest OK') { throw 'Launcher self-test failed.' }
}

# Syntax check every script
foreach ($f in Get-ChildItem $root -Recurse -Include *.ps1, *.psm1 | Where-Object { $_.FullName -notlike "$dist*" }) {
    $errors = $null; $tokens = $null
    [void][System.Management.Automation.Language.Parser]::ParseFile($f.FullName, [ref]$tokens, [ref]$errors)
    if ($errors.Count) { throw "Parse errors in $($f.Name): $($errors[0].Message)" }
}

if (Test-Path $stage) { Remove-Item $stage -Recurse -Force }
if (Test-Path $zip) { Remove-Item $zip -Force }
New-Item -ItemType Directory -Path $stage -Force | Out-Null
$items = @('src', 'config', 'installer', 'assets', 'docs', 'tests', 'build', 'Setup.cmd', 'PCleaner.cmd', 'README.md', 'LICENSE', 'VERSION')
if ($WithExe) { $items += 'Setup.exe', 'PCleaner.exe' }
foreach ($item in $items) {
    $from = Join-Path $root $item
    if (Test-Path $from) { Copy-Item $from -Destination $stage -Recurse -Force }
}
Remove-Item (Join-Path $stage 'assets\screenshots') -Recurse -Force -ErrorAction SilentlyContinue   # README images, not needed at runtime
Compress-Archive -Path (Join-Path $stage '*') -DestinationPath $zip -CompressionLevel Optimal
Remove-Item $stage -Recurse -Force   # the zip is the artifact; keep dist\ tidy
$hash = (Get-FileHash $zip -Algorithm SHA256).Hash
Set-Content -Path "$zip.sha256" -Value "$hash  $(Split-Path $zip -Leaf)" -Encoding ASCII
Write-Host "Release: $zip" -ForegroundColor Green
Write-Host "SHA256:  $hash"
