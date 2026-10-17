# r/Windows11 (also usable for r/Windows10 with the title tweaked)

Rules that matter: check the sidebar the morning you post; many Windows subs remove link-only posts and require an account with history. Post as a screenshot with the text in the body, disclose authorship, do not link the exe directly.

**Title**

    I made a free, open-source CCleaner replacement that never deletes your passwords (and actually checks drivers against NVIDIA/ASUS)

**Body** (image: `assets/screenshots/clean-light.png`)

Author here. Short version: CCleaner cleaned my saved passwords and autofill once too often, so I built the parts I actually use into a small free app.

- Cleans temp files, crash dumps, logs, error reports, update caches and browser caches. Shows you what it will remove before it does (Analyze), then you click Clean.
- Browser passwords, autofill, cookies, history and bookmarks can never be deleted by it. That is enforced in the code, not a checkbox.
- Stops background services that are hogging CPU or memory while their app is not open. Windows and security services are protected. One click to undo.
- Driver check compares your drivers with NVIDIA and your laptop maker's download page (ASUS automated, others linked) plus Windows Update. On my ROG it found a Wi-Fi driver Windows Update never offered.
- Optional weekly schedule, report after every run, light and dark theme.

No ads, no account, no cloud, no "Pro" button. MIT licensed, source on GitHub, and it is plain PowerShell underneath so anyone can read what it does.

Heads-up: there is no installer exe. You double-click Setup.cmd, Windows asks once whether to run a file from the internet, and that's it. The whole zip is readable script and scans clean on VirusTotal.

GitHub: https://github.com/undercutacademy/PCleaner

If something looks wrong on your machine, open an issue with the report it generates and I'll fix it.
