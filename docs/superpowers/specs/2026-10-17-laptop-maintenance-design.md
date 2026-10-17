# PCleaner (originally "Laptop Maintenance") - design

Date: 2026-10-17. Status: built from this design in the same session (user was away; all
open questions were settled by the builder and are marked "builder's call").

## Intent

A local, scheduled, weekly maintenance tool for one Windows 11 laptop that covers the three
CCleaner features the user actually uses: junk cleaning, a driver update check, and stopping
resource-hungry services that are not in use. No cloud, no license, no telemetry.

## What was learned from CCleaner 7 (evidence)

Source: the installed copy under `C:\Program Files\Piriform\CCleaner 7`, inspected with REA
and plain file reads. Ghidra was not configured, so the native binaries were not decompiled;
the findings below come from the rule file, the WebView UI bundle, and the module logs.

- Cleaning is rule-driven. `ccleaner.ini` holds 769 sections, each with `FileKey` (folder,
  file patterns, RECURSE/REMOVESELF), `RegKey`, `DetectFile`, `ActiveProcesses` (skip while
  the app runs), `OnFile` operators such as `FileDeleteIfOlderThan|14days`, and named
  `Action`s (EmptyRecycleBin, CleanDNSCache, DiskCleanup, CleanWindowsEventLogs).
- Default-on Windows rules: Temporary Files, Memory Dumps, Chkdsk fragments, Windows Log
  Files, Thumbnail Cache, Recycle Bin, Run MRU, Clipboard. Default-off (with warnings):
  Prefetch older than 14 days, Event Logs, WER, Delivery Optimization, driver install logs.
- Driver Updater enumerates devices with SetupAPI, flags installed INF versions, then calls
  a Gen Digital backend (`UpdateManager::GetLatestDrivers`) for newer versions. Offline runs
  fail. It takes a restore point before installing.
- Performance Optimizer ("sleep") scans Start Menu, registered executables and AppX, excludes
  anti-malware PPL services (WinDefend, MDCoreSvc, WdNisSvc), keeps a security-software
  database, and supports `scan`, `sleep`, `wake`, `ignore`, `revert_all`.

The rule file is copyrighted and says it may not be copied; this project ships its own
small rule set that targets the same well-known Windows locations.

## Goals

- One command (and one scheduled task) that cleans, checks drivers, and tames services.
- Safe by default: dry-run mode, skip rules whose app is running, never delete user
  documents, never stop core Windows or security services, revertable service changes.
- Readable report after each run, kept locally, plus a toast notification.

## Non-goals / anti-goals

- No registry "cleaning" (CCleaner's registry cleaner has no measurable benefit and real
  breakage risk).
- No cookie, password, history or form-data deletion.
- No third-party driver download. Windows Update is the only driver source.
- No permanent disabling of services without an explicit opt-in list and a revert path.

## Constraints

- Windows PowerShell 5.1 only (PowerShell 7 is not installed). ASCII-only source files.
- No external modules. Pester 3.4 (built in) for tests.
- Must run unattended from Task Scheduler with highest privileges.
- Project lives in OneDrive; the installer pins the folder so files stay on disk.

## Design

```
laptop-maintenance/
  src/LaptopMaintenance.psm1   # all logic: rules engine, cleaner, drivers, services, report
  src/Invoke-Maintenance.ps1   # entry point (-DryRun, -Tasks, -InstallDrivers, -Revert)
  src/Install-Schedule.ps1     # registers the weekly task (self-elevates)
  src/Uninstall-Schedule.ps1
  config/rules.json            # cleaning rules
  config/settings.json         # thresholds, service lists, schedule, report options
  tests/LaptopMaintenance.Tests.ps1
```

Cleaner: JSON rules modelled on CCleaner's grammar (folder + patterns + recurse +
olderThanDays + removeSelf, detectFile, activeProcesses, actions). Variables are `%ENV%`
tokens plus named lists in `<ANGLE>` form that may contain wildcards (browser profiles).

Drivers: `Win32_PnPSignedDriver` inventory with age flags, `Get-PnpDevice` problem
devices, and the Windows Update Agent COM API searched for `Type='Driver'`. Installing
is opt-in (`-InstallDrivers` or settings) and takes a restore point first.

Services: sample CPU and working set per process over N seconds, map to services, then
select running services that exceed thresholds, are not protected, are not shared
`svchost` hosts, have no running dependents, and whose vendor application has no visible
window (the "not being used" test). Manual-start services are stopped (they restart on
demand). Automatic services are only touched if listed in `optionalAutoServices`; those
can also be set to Manual, recorded in a ledger that `-Revert` undoes.

Report: text log plus an HTML report under `%LOCALAPPDATA%\LaptopMaintenance`, last 20 kept.

## Builder's calls

- Schedule: Sundays 10:00, run as the logged-on user, highest privileges, start when
  available if missed. Interactive logon type so the toast can show.
- Temp files older than 1 day only (avoids breaking running installers).
- Recycle Bin: delete items older than 7 days, not everything.
- Browser cache rules skip while the browser is running rather than killing it.
- Default service thresholds: 3 percent CPU or 150 MB working set over an 8 second sample.
