# Show HN

**Title** (73 chars, no marketing words, says what it is):

    Show HN: PCleaner – open-source CCleaner replacement that never touches passwords

Alternative if that reads too long on the day:

    Show HN: PCleaner – a local, open-source CCleaner replacement for Windows

**URL:** https://github.com/undercutacademy/PCleaner

**First comment** (post this yourself within a minute of submitting; HN expects the author to explain):

---

I got annoyed one too many times by CCleaner wiping my saved passwords and autofill, nagging me to upgrade, and phoning home. So I looked at what it actually does and rebuilt the three features I use.

What's in it:

- Junk cleaning driven by a rules file that uses CCleaner's own grammar (folder, patterns, "older than N days", skip while the owning app is running). Temp folders, crash dumps, logs, WER queues, update caches, browser caches. Browser passwords, autofill, cookies, history and bookmarks are on a hard never-delete list in the engine, so even a rule you write yourself can't remove them.
- Service taming: samples every service for 8 seconds and stops idle, resource-hungry ones that are safe to stop (Manual start, no dependents, not a shared svchost, no visible window from the same vendor). Protected list for Windows and security services. Revertable.
- Driver check that compares installed drivers against NVIDIA's lookup service, the ASUS support catalogue, and Windows Update. On my laptop it found a Wi-Fi driver two versions behind that Windows Update never mentioned.
- Weekly scheduled run, HTML report plus JSON summary per run, light and dark themes.

How it's built: Windows PowerShell 5.1 and WPF, nothing to install. The two .exe files are 35 KB launchers compiled with the C# compiler that ships in .NET Framework; all logic is readable script. 44 Pester tests.

Honest limitations: vendor driver checks are automated for NVIDIA and ASUS only (others get a link), the exes are unsigned so SmartScreen warns once, and it is Windows-only by nature.

How it came about: I reverse-engineered the installed CCleaner 7 with an AI reverse-engineering toolkit and Claude. The interesting findings: cleaning is a 769-section ini file, the driver updater sends your hardware IDs to a Gen Digital backend with a paid catalogue, and the "performance optimizer" is a program-sleeper that excludes antimalware protected processes. I did not copy their rule file (it is copyrighted); the rules here are an independent set. Design notes with the evidence are in docs/.

Happy to answer anything about the service-selection heuristics or the driver matching; those are the parts most likely to be wrong on hardware I don't have.

---

**Replies to have ready**

- *"Why would I run a stranger's elevated script?"* You shouldn't blindly. Everything is readable PowerShell, the launcher exe is 35 KB and its source is in build/New-Launchers.ps1, and here is the VirusTotal result for the zip: [link]. Or skip the exe entirely: `powershell -File src\Invoke-Maintenance.ps1 -DryRun` runs read-only.
- *"BleachBit exists."* It does, and it's good for cleaning. PCleaner adds the service taming and the vendor driver comparison, and keeps a weekly schedule with reports. Use whichever fits.
- *"Registry cleaning?"* Deliberately absent. No measurable benefit, real breakage risk.
- *"Why PowerShell 5.1 and not .NET/Rust?"* Because it is on every Windows machine already. No runtime, no installer dependencies, and anyone can read what it does before running it.
- *"Does stopping services actually help?"* Marginally on most machines, which is why it is conservative by default and tells you exactly why it stopped something. The real win on laptops is usually the vendor tray agents; that is the next feature.
- *"AI-built, so it's slop?"* Fair concern. The tests, the dry-run mode, the protected-file list and the design doc are there so you can check rather than trust. Issues welcome.
