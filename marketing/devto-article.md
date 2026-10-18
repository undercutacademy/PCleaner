---
title: I reverse-engineered CCleaner and rebuilt the three features worth keeping, in a day
published: false
tags: windows, powershell, opensource, ai
cover_image: (upload assets/screenshots/health-dark.png)
---

CCleaner used to be the first thing I installed on a new Windows machine. Lately it is the first thing I uninstall: the upsell banners, the telemetry, and the default that quietly wipes saved browser passwords and autofill. But I still wanted the three jobs it does: clean the junk, stop the background stuff I'm not using, and tell me when a driver is out of date.

So I spent a day finding out what CCleaner 7 actually does under the hood, and rebuilt those three jobs as a free, open-source app. This is what I learned and what came out of it.

## What CCleaner really is

I pointed an AI reverse-engineering toolkit (REA) and Claude at the installed copy. Native decompilation wasn't available on my setup, but the interesting parts turned out to be in plain sight anyway:

**The cleaner is a 769-section ini file.** Every rule is a folder, a file pattern, flags like `RECURSE` or `REMOVESELF`, an optional `FileDeleteIfOlderThan|14days`, a `DetectFile` guard, and an `ActiveProcesses` list that skips the rule while the owning app is running. That grammar is good, and I kept it. The file itself is copyrighted and says it may not be copied, so I wrote my own small set of rules against the same well-known locations.

**The driver updater is a cloud product.** It enumerates your devices with SetupAPI, posts the hardware IDs and installed INF versions to a Gen Digital backend (`UpdateManager::GetLatestDrivers` in its logs), and that backend owns a curated driver catalogue. Offline, it simply fails. That catalogue is the thing you're paying for.

**The "performance optimizer" is a program-sleeper.** It scans the Start Menu, registered executables and AppX packages, maintains a security-software database, explicitly excludes anti-malware protected processes (its logs name WinDefend, MDCoreSvc and WdNisSvc), and supports `scan`, `sleep`, `wake`, `ignore` and `revert_all`.

Also in the logs: a "PC health" engine watching for slow boots, disk errors, Windows Update failures and the like, and a crash-dump folder on my own machine that was 8 GB. More on that later.

## The rebuild

Constraints I set myself: nothing to install, code anyone can read before running it elevated, and conservative defaults.

That pointed at Windows PowerShell 5.1 for the engine and WPF (via `XamlReader`) for the window, both built into Windows. It ships as a standard Inno Setup per-user installer, and as a portable zip whose only "launcher" is a two-line batch file, so no compiled code of mine is in the download. The layout is a straight clone of CCleaner's sidebar-and-page structure; the colours are black and silver with a light and a dark theme.

Three parts:

**Clean.** JSON rules in CCleaner's grammar. An Analyze step enumerates everything first and shows counts and sizes per rule. Temp files only go when older than a day; the Recycle Bin keeps the last week; browser rules skip while the browser is open rather than killing it. And a hard protected-file list in the engine: `Login Data`, `Web Data`, `Cookies`, `History`, `Bookmarks`, Firefox's `key4.db`, `logins.json`, `places.sqlite` and friends can never be returned by any rule, including one you write yourself. That was the whole reason for the project, so it is enforced in code, not in a checkbox.

**Tame services.** Two `Get-Process` snapshots eight seconds apart give per-process CPU; `Win32_Service` maps processes to services. A service is stopped only if it is above your CPU or memory threshold, not on the protected list, not a shared `svchost` host, has no running dependents, has no visible window from the same vendor folder (the app is not in use), and is Manual-start so it comes back on demand. Automatic services need an explicit opt-in, and start-type changes go in a ledger that one click reverts. When it finds nothing, it tells you exactly how the running services were bucketed instead of just saying "nothing to do".

**Check drivers.** Windows Update is the baseline, through the Windows Update Agent COM API. On top of that: NVIDIA's own lookup service (the installed version is read from the display class registry key, so it works with the dGPU switched off in Eco mode), and for ASUS laptops the same JSON endpoint their support page uses, matched to installed drivers by vendor and device class. Other makers get a direct support link rather than a guess, and everything that can't be matched confidently is labelled "Not compared". On my ROG G14 this found a Wi-Fi driver two versions behind and a speaker-amp driver a major version behind, neither of which Windows Update had ever mentioned.

Plus a weekly scheduled task, an HTML report and a JSON summary for every run, and 44 Pester tests around the pure functions (path expansion, rule matching, service selection, version comparison, the protected list).

## Things that surprised me

- The first dry run on my own laptop reported 11 GB of junk. 8.5 GB of it was kernel crash dumps from the last few weeks, which is less a cleaning problem than a "something is crashing" problem. A cleaner that shows you the breakdown is more useful than one that just reports a big number.
- GPU shader caches were 3 GB. CCleaner cleans them by default. Wiping them weekly means shader recompiles in every game, so PCleaner leaves them alone unless you opt in.
- Windows stamps every inbox driver with the date 21 June 2006. Any "your driver is 20 years old" warning you've seen from a driver-updater tool is probably that.
- I first shipped two 37 KB launcher executables compiled with the C# compiler that comes with .NET Framework. They scored 7 of 71 on VirusTotal on shape alone (Elastic, CrowdStrike and SentinelOne machine-learning verdicts), even after moving the PowerShell engine in-process and adding a manifest; the scripts scored 0. Unsigned tiny .NET stubs are guilty until signed, so the launchers wait for code signing and the release uses a plain Inno Setup installer plus a portable zip that scans clean.
- An AI-assisted build is fast at the first 90 percent. The remaining 10 percent (a regex with an unbalanced parenthesis, a closure capturing a validated parameter, a ComboBox that ignored the dark theme) only showed up by rendering the window to PNG and actually looking at it. Build the self-test and the screenshot switch early.

## Get it

MIT licensed, Windows 10/11: https://github.com/undercutacademy/PCleaner

Honest limitations: not code-signed yet (Windows shows an unknown-publisher prompt once), vendor driver comparison automated only for NVIDIA and ASUS so far, and no registry cleaning on purpose. Issues from people with hardware I don't have are the most valuable thing you can send.
