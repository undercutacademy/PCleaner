# X / Twitter

Attach `assets/screenshots/health-dark.png` (or a 10-second screen recording of Analyze filling the ring, if you make one).

**Main post**

    I got tired of CCleaner deleting my saved passwords and nagging me to pay, so I rebuilt the parts worth keeping as a free, open-source Windows app.

    PCleaner: junk cleaning, idle-service taming, driver checks against NVIDIA + your laptop maker. No cloud, no license, no upsell. Passwords are never touched, by design.

    First run on my own laptop freed 10 GB.

    https://github.com/undercutacademy/PCleaner

**Reply thread (post as replies to your own tweet, one each)**

1.  How it was made: I reverse-engineered the installed CCleaner 7 with an AI RE toolkit + Claude. Turns out the cleaner is a 769-rule ini file, the driver updater ships your hardware IDs to a paid backend, and the "optimizer" is a program-sleeper. Rebuilt the good parts in a day.

2.  What it will not do: registry "cleaning", cookies, history, autofill, passwords. Those are on a hard never-delete list in the engine. Everything it does run is readable PowerShell; the portable zip has not a single binary in it, just scripts, and scans 0/65 on VirusTotal: https://www.virustotal.com/gui/file/21011f960d227a67c9fd34fcf7cd4ad2a63c720158347f7b24b4d8703abc25b9

3.  Driver check found a Wi-Fi driver two versions behind on my ASUS that Windows Update never mentioned. NVIDIA and ASUS are compared automatically, other makers get a link. Honest limit.

4.  MIT licensed. Issues and PRs welcome, especially from people with hardware I don't have.

**Hashtags**: none in the main post. If you must, put `#opensource #windows11` in the last reply only.
