# Compiles PCleaner.exe and Setup.exe with the C# compiler that ships inside the .NET Framework on every Windows.
# Each exe is a tiny windowless stub that starts the matching PowerShell script next to it, with the icon embedded.
[CmdletBinding()]
param()
$ErrorActionPreference = 'Stop'
$root = Split-Path -Parent (Split-Path -Parent $MyInvocation.MyCommand.Path)
$version = (Get-Content (Join-Path $root 'VERSION') | Select-Object -First 1).Trim()
$icon = Join-Path $root 'assets\PCleaner.ico'
if (-not (Test-Path $icon)) { & (Join-Path $root 'build\New-Icon.ps1') }
$csc = Join-Path $env:windir 'Microsoft.NET\Framework64\v4.0.30319\csc.exe'
if (-not (Test-Path $csc)) { $csc = Join-Path $env:windir 'Microsoft.NET\Framework\v4.0.30319\csc.exe' }
if (-not (Test-Path $csc)) { throw 'csc.exe (.NET Framework 4) not found.' }

$template = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Reflection;
using System.Windows.Forms;

[assembly: AssemblyTitle("__TITLE__")]
[assembly: AssemblyProduct("PCleaner")]
[assembly: AssemblyDescription("__DESC__")]
[assembly: AssemblyCompany("PCleaner authors")]
[assembly: AssemblyCopyright("MIT License")]
[assembly: AssemblyVersion("__VERSION__.0")]
[assembly: AssemblyFileVersion("__VERSION__.0")]

static class Program
{
    [STAThread]
    static int Main(string[] args)
    {
        string exeDir = Path.GetDirectoryName(Assembly.GetExecutingAssembly().Location);
        string script = Path.Combine(exeDir, @"__SCRIPT__");
        if (!File.Exists(script))
        {
            MessageBox.Show("Missing file:\n" + script + "\n\nKeep this exe inside the PCleaner folder.", "PCleaner", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }
        string ps = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.Windows), @"System32\WindowsPowerShell\v1.0\powershell.exe");
        var psi = new ProcessStartInfo(ps);
        psi.Arguments = "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File \"" + script + "\" " + string.Join(" ", args);
        psi.WorkingDirectory = Path.GetDirectoryName(script);
        psi.UseShellExecute = false;
        psi.CreateNoWindow = true;
        try
        {
            using (var p = Process.Start(psi)) { if (__WAIT__) { p.WaitForExit(); return p.ExitCode; } }
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show("Could not start PowerShell:\n" + ex.Message, "PCleaner", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }
}
'@

function Build-Stub([string]$Name, [string]$Script, [string]$Title, [string]$Desc, [bool]$Wait) {
    $src = Join-Path $env:TEMP "pcleaner_$Name.cs"
    $code = $template.Replace('__SCRIPT__', $Script).Replace('__TITLE__', $Title).Replace('__DESC__', $Desc).Replace('__VERSION__', $version).Replace('__WAIT__', $(if ($Wait) { 'true' } else { 'false' }))
    Set-Content -Path $src -Value $code -Encoding ASCII
    $out = Join-Path $root "$Name.exe"
    & $csc /nologo /target:winexe /platform:anycpu /optimize+ /nowarn:0162 "/win32icon:$icon" "/out:$out" /reference:System.Windows.Forms.dll $src
    if ($LASTEXITCODE -ne 0) { throw "csc failed for $Name" }
    Remove-Item $src -Force
    Write-Host "Built $out ($((Get-Item $out).Length) bytes)"
}

Build-Stub -Name 'PCleaner' -Script 'src\PCleaner.ps1' -Title 'PCleaner' -Desc 'PCleaner launcher' -Wait $false
Build-Stub -Name 'Setup' -Script 'installer\Install-PCleaner.ps1' -Title 'PCleaner Setup' -Desc 'PCleaner installer' -Wait $true
