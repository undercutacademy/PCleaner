# r/opensource

Rules that matter: use the **Promotional** flair; the repo must show an OSI license (MIT, done); disclose that you are the author.

**Title**

    PCleaner: a local, open-source CCleaner replacement for Windows (MIT) that never deletes passwords or autofill

**Body**

I'm the author. I built this after CCleaner wiped my browser passwords one time too many and kept pushing paid upgrades.

What it does

- Cleans the usual junk: temp folders, crash dumps, logs, Windows Error Reporting queues, update caches, browser caches. Rules live in a readable JSON file using the same grammar CCleaner uses (folder, patterns, "older than N days", skip while the app is running).
- Hard never-delete list: browser passwords, autofill, cookies, history and bookmarks cannot be removed by any rule, including ones you add.
- Stops idle resource-hungry services that are safe to stop (Manual start, no dependents, not shared svchost, vendor app not open), with a protected list for Windows and security services and a revert.
- Driver check that compares installed drivers with NVIDIA's lookup service, the ASUS support catalogue and Windows Update. Other laptop makers get a direct link rather than a guess.
- Optional weekly scheduled run, HTML report and JSON summary per run, light and dark themes.

What it is built with: Windows PowerShell 5.1 + WPF, nothing to install. The exes are 37 KB launchers that host the PowerShell engine in-process; source is in the repo. 44 tests.

Limits: Windows only, unsigned exes (SmartScreen warns once), vendor driver comparison automated for NVIDIA and ASUS only.

Repo: https://github.com/undercutacademy/PCleaner
Release zip: https://github.com/undercutacademy/PCleaner/releases/tag/v1.1.0

Feedback I'd value most: the service-selection heuristics, and whether the driver matching behaves on non-ASUS machines.
