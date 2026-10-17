# Compiles PCleaner.exe and Setup.exe with the C# compiler that ships inside the .NET Framework on every Windows.
# Each exe hosts the PowerShell engine in-process (System.Management.Automation) and runs the matching script next to it.
# No child powershell.exe, no "-ExecutionPolicy Bypass -WindowStyle Hidden" command line: that dropper-like pattern is what
# machine-learning antivirus heuristics flag, and it is unnecessary.
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
$sma = [psobject].Assembly.Location   # System.Management.Automation.dll of the Windows PowerShell 5.1 engine (GAC)

$template = @'
using System;
using System.Diagnostics;
using System.IO;
using System.Management.Automation;
using System.Management.Automation.Runspaces;
using System.Reflection;
using System.Security.Principal;
using System.Threading;
using System.Windows.Forms;

[assembly: AssemblyTitle("__TITLE__")]
[assembly: AssemblyProduct("PCleaner")]
[assembly: AssemblyDescription("__DESC__")]
[assembly: AssemblyCompany("PCleaner authors")]
[assembly: AssemblyCopyright("MIT License - https://github.com/undercutacademy/PCleaner")]
[assembly: AssemblyVersion("__VERSION__.0")]
[assembly: AssemblyFileVersion("__VERSION__.0")]

static class Program
{
    static bool IsAdmin()
    {
        using (var id = WindowsIdentity.GetCurrent()) { return new WindowsPrincipal(id).IsInRole(WindowsBuiltInRole.Administrator); }
    }

    [STAThread]
    static int Main(string[] args)
    {
        string exePath = Assembly.GetExecutingAssembly().Location;
        string exeDir = Path.GetDirectoryName(exePath);
        string script = Path.Combine(exeDir, @"__SCRIPT__");
        if (!File.Exists(script))
        {
            MessageBox.Show("Missing file:\n" + script + "\n\nKeep this exe inside the PCleaner folder.", "PCleaner", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 2;
        }

        // __ELEVATE_COMMENT__
        bool wantsElevation = __ELEVATE__;
        bool noElevate = Array.Exists(args, a => string.Equals(a, "-NoElevate", StringComparison.OrdinalIgnoreCase) || string.Equals(a, "-SelfTest", StringComparison.OrdinalIgnoreCase) || string.Equals(a, "-Screenshot", StringComparison.OrdinalIgnoreCase));
        if (wantsElevation && !noElevate && !IsAdmin())
        {
            try
            {
                var psi = new ProcessStartInfo(exePath) { UseShellExecute = true, Verb = "runas", WorkingDirectory = exeDir, Arguments = Quote(args) };
                Process.Start(psi);
                return 0;
            }
            catch (System.ComponentModel.Win32Exception) { /* UAC declined: continue without admin */ }
        }

        try
        {
            var iss = InitialSessionState.CreateDefault();
            iss.ExecutionPolicy = Microsoft.PowerShell.ExecutionPolicy.Unrestricted;   // only for this in-process engine; the machine policy is untouched
            iss.ApartmentState = ApartmentState.STA;
            iss.ThreadOptions = PSThreadOptions.UseCurrentThread;
            using (var rs = RunspaceFactory.CreateRunspace(iss))
            {
                rs.Open();
                using (var ps = PowerShell.Create())
                {
                    ps.Runspace = rs;
                    ps.AddCommand(script, false);
                    for (int i = 0; i < args.Length; i++)
                    {
                        string a = args[i];
                        if (a.StartsWith("-") && a.Length > 1 && !IsNumber(a))
                        {
                            bool hasValue = i + 1 < args.Length && !(args[i + 1].StartsWith("-") && !IsNumber(args[i + 1]));
                            if (hasValue) { ps.AddParameter(a.Substring(1), args[++i]); } else { ps.AddParameter(a.Substring(1)); }
                        }
                        else { ps.AddArgument(a); }
                    }
                    ps.Invoke();
                    if (ps.HadErrors && ps.Streams.Error.Count > 0)
                    {
                        var first = ps.Streams.Error[0];
                        string where = first.InvocationInfo != null ? first.InvocationInfo.PositionMessage : "";
                        MessageBox.Show("PCleaner hit an error:\n\n" + first.Exception.Message + "\n" + where, "PCleaner", MessageBoxButtons.OK, MessageBoxIcon.Warning);
                        return 1;
                    }
                }
            }
            return 0;
        }
        catch (Exception ex)
        {
            MessageBox.Show("PCleaner could not start:\n\n" + ex.Message, "PCleaner", MessageBoxButtons.OK, MessageBoxIcon.Error);
            return 1;
        }
    }

    static bool IsNumber(string s) { double d; return double.TryParse(s, out d); }

    static string Quote(string[] args)
    {
        var sb = new System.Text.StringBuilder();
        foreach (var a in args) { if (sb.Length > 0) sb.Append(' '); sb.Append(a.IndexOf(' ') >= 0 ? "\"" + a + "\"" : a); }
        return sb.ToString();
    }
}
'@

function Build-Stub([string]$Name, [string]$Script, [string]$Title, [string]$Desc, [bool]$Elevate) {
    $src = Join-Path $env:TEMP "pcleaner_$Name.cs"
    $code = $template.Replace('__SCRIPT__', $Script).Replace('__TITLE__', $Title).Replace('__DESC__', $Desc).Replace('__VERSION__', $version)
    $code = $code.Replace('__ELEVATE__', $(if ($Elevate) { 'true' } else { 'false' }))
    $code = $code.Replace('__ELEVATE_COMMENT__', $(if ($Elevate) { 'The window needs admin rights for services and system folders: relaunch this exe elevated once.' } else { 'Per-user installer: no elevation needed.' }))
    Set-Content -Path $src -Value $code -Encoding ASCII
    $out = Join-Path $root "$Name.exe"
    & $csc /nologo /target:winexe /platform:anycpu /optimize+ /nowarn:0162 "/win32icon:$icon" "/out:$out" /reference:System.Windows.Forms.dll "/reference:$sma" $src
    if ($LASTEXITCODE -ne 0) { throw "csc failed for $Name" }
    Remove-Item $src -Force
    Write-Host "Built $out ($((Get-Item $out).Length) bytes)"
}

Build-Stub -Name 'PCleaner' -Script 'src\PCleaner.ps1' -Title 'PCleaner' -Desc 'PCleaner desktop window' -Elevate $true
Build-Stub -Name 'Setup' -Script 'installer\Install-PCleaner.ps1' -Title 'PCleaner Setup' -Desc 'PCleaner installer' -Elevate $false
