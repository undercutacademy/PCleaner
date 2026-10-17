; Inno Setup script for PCleaner.
;
; Build with:   .\build\Build-Installer.ps1      (passes /DAppVersion from VERSION)
; Output:       dist\PCleaner-<version>-Setup.exe
;
; DESIGN NOTES
;
; Per-user install (PrivilegesRequired=lowest, {localappdata}\Programs\PCleaner).
;   No admin needed to install or upgrade. The app itself asks for admin once when it opens,
;   because cleaning system folders and stopping services needs it.
;
; AppId is a fixed GUID and MUST NEVER CHANGE: it is how Windows upgrades an existing install
;   in place instead of creating a second entry in Apps & Features.
;
; User state is not touched by install or uninstall.
;   Reports, logs and the service ledger live in %LOCALAPPDATA%\PCleaner (outside {app}).
;   settings.json and rules.json inside {app}\config are installed only if missing
;   (onlyifdoesntexist) and the shipped defaults are placed next to them as *.default.json,
;   so an upgrade never overwrites edits. Uninstall removes {app} entirely, including config.
;
; No executables are installed. Shortcuts start Windows PowerShell with src\PCleaner.ps1.
;
; SIGNING: not enabled yet. When a certificate exists (see marketing/signpath-application.md),
;   add SignTool= to [Setup] and the compiled launchers can come back.

#define AppName       "PCleaner"
#define AppPublisher  "PCleaner authors"
#define AppURL        "https://github.com/undercutacademy/PCleaner"
#define PsExe         "{sys}\WindowsPowerShell\v1.0\powershell.exe"
; Quadruple quotes: ISPP turns """" into "" so the section line keeps a literal quote around the path.
#define PsArgs        "-NoProfile -ExecutionPolicy Bypass -STA -WindowStyle Hidden -File """"{app}\src\PCleaner.ps1"""""

#ifndef AppVersion
  #error AppVersion not defined - build via build\Build-Installer.ps1, not ISCC directly
#endif
#ifndef SourceDir
  #define SourceDir ".."
#endif

[Setup]
; NEVER change AppId
AppId={{6C2D1F4B-9E3A-4B7C-8D05-1A2B3C4D5E6F}
AppName={#AppName}
AppVersion={#AppVersion}
AppVerName={#AppName} {#AppVersion}
AppPublisher={#AppPublisher}
AppPublisherURL={#AppURL}
AppSupportURL={#AppURL}/issues
AppUpdatesURL={#AppURL}/releases
VersionInfoVersion={#AppVersion}
VersionInfoCompany={#AppPublisher}
VersionInfoDescription={#AppName} Setup
VersionInfoProductName={#AppName}
VersionInfoCopyright=MIT License
DefaultDirName={localappdata}\Programs\PCleaner
DisableDirPage=yes
DefaultGroupName={#AppName}
DisableProgramGroupPage=yes
PrivilegesRequired=lowest
PrivilegesRequiredOverridesAllowed=dialog
OutputDir={#SourceDir}\dist
OutputBaseFilename=PCleaner-{#AppVersion}-Setup
SetupIconFile={#SourceDir}\assets\PCleaner.ico
UninstallDisplayIcon={app}\assets\PCleaner.ico
UninstallDisplayName={#AppName}
Compression=lzma2/max
SolidCompression=yes
WizardStyle=modern
WizardSizePercent=110
ShowLanguageDialog=no
LicenseFile={#SourceDir}\LICENSE
MinVersion=10.0
ArchitecturesAllowed=x64compatible arm64
CloseApplications=no
ChangesAssociations=no

[Languages]
Name: "english"; MessagesFile: "compiler:Default.isl"

[Tasks]
Name: "desktopicon"; Description: "Create a &desktop shortcut"; GroupDescription: "Shortcuts:"

[Files]
Source: "{#SourceDir}\src\*.ps1";               DestDir: "{app}\src";       Flags: ignoreversion
Source: "{#SourceDir}\src\*.psm1";              DestDir: "{app}\src";       Flags: ignoreversion
Source: "{#SourceDir}\src\ui\*.xaml";           DestDir: "{app}\src\ui";    Flags: ignoreversion
Source: "{#SourceDir}\config\settings.json";    DestDir: "{app}\config";    Flags: onlyifdoesntexist uninsneveruninstall
Source: "{#SourceDir}\config\rules.json";       DestDir: "{app}\config";    Flags: onlyifdoesntexist uninsneveruninstall
Source: "{#SourceDir}\config\settings.json";    DestDir: "{app}\config";    DestName: "settings.default.json"; Flags: ignoreversion
Source: "{#SourceDir}\config\rules.json";       DestDir: "{app}\config";    DestName: "rules.default.json";    Flags: ignoreversion
Source: "{#SourceDir}\assets\PCleaner.ico";     DestDir: "{app}\assets";    Flags: ignoreversion
Source: "{#SourceDir}\assets\PCleaner.png";     DestDir: "{app}\assets";    Flags: ignoreversion
Source: "{#SourceDir}\installer\Uninstall-PCleaner.ps1"; DestDir: "{app}\installer"; Flags: ignoreversion
Source: "{#SourceDir}\PCleaner.cmd";            DestDir: "{app}";           Flags: ignoreversion
Source: "{#SourceDir}\VERSION";                 DestDir: "{app}";           Flags: ignoreversion
Source: "{#SourceDir}\README.md";               DestDir: "{app}";           Flags: ignoreversion
Source: "{#SourceDir}\LICENSE";                 DestDir: "{app}";           Flags: ignoreversion

[Icons]
Name: "{autoprograms}\{#AppName}"; Filename: "{#PsExe}"; Parameters: "{#PsArgs}"; WorkingDir: "{app}"; IconFilename: "{app}\assets\PCleaner.ico"; Comment: "Clean junk, tame idle services and check drivers"
Name: "{autodesktop}\{#AppName}";  Filename: "{#PsExe}"; Parameters: "{#PsArgs}"; WorkingDir: "{app}"; IconFilename: "{app}\assets\PCleaner.ico"; Comment: "Clean junk, tame idle services and check drivers"; Tasks: desktopicon

[Run]
Filename: "{#PsExe}"; Parameters: "{#PsArgs}"; WorkingDir: "{app}"; Description: "Open {#AppName} now"; Flags: postinstall nowait skipifsilent

[UninstallRun]
; Remove the weekly scheduled task if the user created one (needs admin; the script asks once). Only runs when the task exists.
Filename: "{#PsExe}"; Parameters: "-NoProfile -ExecutionPolicy Bypass -WindowStyle Hidden -File ""{app}\src\Uninstall-Schedule.ps1"""; RunOnceId: "RemoveScheduledTask"; Flags: runhidden; Check: ScheduledTaskExists

[UninstallDelete]
Type: filesandordirs; Name: "{app}\config"
Type: dirifempty;     Name: "{app}"

[Code]
function ScheduledTaskExists: Boolean;
var
  ResultCode: Integer;
begin
  Result := Exec(ExpandConstant('{sys}\schtasks.exe'), '/Query /TN PCleaner', '', SW_HIDE, ewWaitUntilTerminated, ResultCode) and (ResultCode = 0);
end;

{ Early 1.1.0 builds were installed by a PowerShell script that wrote its own Apps & Features entry and left a
  compiled launcher in the install folder. Fold that install into this one so Windows shows a single PCleaner. }
procedure CurStepChanged(CurStep: TSetupStep);
begin
  if CurStep = ssPostInstall then
  begin
    RegDeleteKeyIncludingSubkeys(HKCU, 'Software\Microsoft\Windows\CurrentVersion\Uninstall\PCleaner');
    DeleteFile(ExpandConstant('{app}\PCleaner.exe'));
    DeleteFile(ExpandConstant('{app}\Setup.exe'));
  end;
end;
