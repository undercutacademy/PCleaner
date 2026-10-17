# r/software

Rules that matter: r/software allows developers to post their own software with the "Software" or "Release" flair and clear disclosure; no affiliate links; expect blunt comparisons to BleachBit, so address it up front.

**Title**

    [Release] PCleaner 1.1 – free open-source CCleaner alternative: junk cleaning, idle-service taming, vendor driver checks. Never touches passwords.

**Body**

Developer post. PCleaner is a local, MIT-licensed Windows maintenance tool. It is not trying to be a Swiss army knife; it does three things:

1. **Clean** temp folders, dumps, logs, WER queues, update caches and browser caches, with an Analyze step that shows every file count and size before anything is removed. Passwords, autofill, cookies, history and bookmarks are on a hard never-delete list.
2. **Tame services**: measures every service for 8 seconds, stops idle resource-hungry ones that are safe to stop, explains why for each, protects Windows and security services, and can revert.
3. **Check drivers** against NVIDIA's driver service, your laptop maker's catalogue (ASUS automated; Dell, HP, Lenovo and others get a link) and Windows Update.

vs BleachBit: BleachBit is a great cleaner and cleans more app-specific locations. PCleaner cleans less aggressively by default (temp files older than a day, Recycle Bin older than a week), adds the service and driver parts, schedules weekly, and writes an HTML report each run.

vs CCleaner: no registry cleaner on purpose, no cookie/history/password cleaning on purpose, no upsell, no telemetry, no cloud.

Tech: Windows PowerShell 5.1 + WPF, nothing to install. The download has no executables, just scripts and two .cmd starters; the zip scans 0/65 on VirusTotal (https://www.virustotal.com/gui/file/21011f960d227a67c9fd34fcf7cd4ad2a63c720158347f7b24b4d8703abc25b9).

Download: https://github.com/undercutacademy/PCleaner/releases/tag/v1.1.0
Source: https://github.com/undercutacademy/PCleaner
