# r/PowerShell

Rules that matter: posts about your own scripts are fine if the code is public and you engage; avoid "look at my app" without technical content. This audience wants the engineering.

**Title**

    A CCleaner replacement in pure Windows PowerShell 5.1 + WPF: rules engine, service sampler, vendor driver checks (MIT)

**Body**

I wanted a cleaner/maintenance tool with no runtime to install and code I could read before running elevated, so it is all Windows PowerShell 5.1. A few bits that might be useful to others:

- **Rules engine** (`src/LaptopMaintenance.psm1`): JSON rules modelled on CCleaner's ini grammar. `Expand-LmPath` handles `%ENV%` tokens and `<VAR>` lists with wildcards in the middle of paths (browser profile folders), `Get-LmFileKeyTargets` enumerates with recurse / olderThanDays and refuses reparse points and a protected-file list (`Login Data`, `Web Data`, `key4.db`, `places.sqlite`, etc.).
- **Service sampler**: two `Get-Process` snapshots N seconds apart give per-PID CPU percent; `Win32_Service` maps PIDs to services; shared `svchost` hosts and services with running dependents are excluded; a "vendor app has a window" test keeps you from stopping a service whose app is in use. `Select-LmServiceCandidates` is pure and unit-tested with fake inventories.
- **Driver checks**: `Win32_PnPSignedDriver` inventory; NVIDIA via their `lookupValueSearch` + `DriverManualLookup` endpoints with the `32.0.16.1742 -> 617.42` version conversion; ASUS via the `GetPDDrivers` JSON their support page uses; the Windows Update Agent COM API for `Type='Driver'`. Installed NVIDIA version is read from the display class registry key so it works with the dGPU in Eco mode.
- **UI**: WPF via `XamlReader`, themes as resource dictionaries swapped at runtime, a `-Screenshot` switch that renders the window off-screen to PNG for review, and a `-SelfTest` switch the build runs.
- **Packaging**: two 35 KB exe stubs compiled with `csc.exe` from .NET Framework so users get a double-clickable Setup.exe without a toolchain; per-user installer writes the HKCU Uninstall key.
- Pester 3.4 (the built-in one), 44 tests, PS 5.1 gotchas respected (ASCII-only sources, no ternaries, `ConvertTo-LmHashtable` to get real hashtables out of `ConvertFrom-Json`).

Repo: https://github.com/undercutacademy/PCleaner

Would appreciate eyes on `Select-LmServiceCandidates` and `Get-LmProcessSamples`; I'm sure there are edge cases on machines with many user sessions.
