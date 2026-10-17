# Directory and download-site submissions

## AlternativeTo (most important: it owns the "CCleaner alternative" search)

Sign in, user icon > "Suggest new application". Free; the queue takes months unless you use the one-time $5 fast lane. Then go to the CCleaner page and add PCleaner as an alternative with a short reason.

- **Name**: PCleaner
- **Website**: https://github.com/undercutacademy/PCleaner
- **Platforms**: Windows
- **License**: Open Source (MIT), Free
- **Tags**: system cleaner, disk cleanup, driver updater, startup manager, privacy, portable
- **Short description** (max ~200 chars): Local, open-source CCleaner replacement: junk cleaning, idle-service taming and driver checks against NVIDIA, your laptop maker and Windows Update. Never deletes passwords or autofill.
- **Long description**: PCleaner cleans temp folders, crash dumps, logs, Windows Error Reporting queues, update caches and browser caches, shows everything before it removes anything, and keeps browser passwords, autofill, cookies, history and bookmarks on a hard never-delete list. It measures services for 8 seconds and stops idle, resource-hungry ones that are safe to stop, with Windows and security services protected and a one-click revert. Its driver check compares installed drivers with NVIDIA's driver service, the laptop maker's catalogue (ASUS automated, others linked) and Windows Update. Optional weekly schedule, HTML report per run, light and dark themes. Plain Windows PowerShell and WPF, no cloud, no license, no telemetry.
- **Reason it's an alternative to CCleaner**: Same core jobs (clean junk, tame background load, update drivers) without registry cleaning, password/autofill deletion, upsells or telemetry.
- Screenshots: upload the four in `assets/screenshots/`.

## MajorGeeks

Email `tim@majorgeeks.com` (human review, tested in a VM, must be free or fairly priced, must be "4 stars" in their view).

    Subject: Submission: PCleaner 1.1.0, open-source CCleaner replacement (MIT, free)

    Hi Tim,

    I'd like to submit PCleaner for MajorGeeks. It's a free, MIT-licensed Windows maintenance tool that
    covers the three CCleaner jobs people actually use: junk cleaning with an Analyze step, stopping idle
    resource-hungry services (with a protected list and revert), and a driver check that compares against
    NVIDIA, the laptop maker's catalogue and Windows Update. Browser passwords, autofill, cookies, history
    and bookmarks are on a hard never-delete list. No cloud, no license, no telemetry, no upsell.

    Download (zip, Setup.cmd inside; no executables): https://github.com/undercutacademy/PCleaner/releases/download/v1.1.0/PCleaner-1.1.0.zip
    SHA256: 7AEE81B26FA7C9DCB4030BFA093B7242BEC63CAE55605723BA55495337CA0BF6
    Source and README with screenshots: https://github.com/undercutacademy/PCleaner
    VirusTotal: https://www.virustotal.com/gui/file/21011f960d227a67c9fd34fcf7cd4ad2a63c720158347f7b24b4d8703abc25b9 (0/65)

    Requirements: Windows 10/11 with Windows PowerShell 5.1 (built in). Per-user install, listed in Settings > Apps.
    Silent install for your VM: powershell -NoProfile -ExecutionPolicy Bypass -File installer\Install-PCleaner.ps1 -Silent

    Thanks for taking a look,
    [name]

## Softpedia

https://www.softpedia.com/ > "Submit software" (developer account). Review takes about two weeks. Use the same description as AlternativeTo, category "System > System Miscellaneous" or "Tweak > System Tweak", license "MIT". Upload the four screenshots and the icon PNG.

## Neowin / gHacks / MakeUseOf

These are editorial, not directories. Send a two-paragraph tip to news@neowin.net and via gHacks' contact form with the launch-day numbers (stars, downloads) once there are any. MakeUseOf already runs "open-source CCleaner alternative" pieces; pitch the password-protection angle and the vendor driver comparison as the hook.

## winget

On hold until releases are code-signed; see `winget.md`.
