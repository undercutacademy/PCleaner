# r/pcmasterrace

Rules that matter: this sub is picky about self-promotion; use the "Tech Support" or "Discussion" flair only if the mods allow dev posts that week, otherwise skip it and let others post it. Gamers care about one thing here: does it make games stutter or help.

**Title**

    Made a free open-source CCleaner replacement for my gaming laptop. It leaves shader caches alone by default and checks GPU drivers against NVIDIA directly.

**Body** (image: `assets/screenshots/drivers-dark.png`)

Built this for my own ROG G14 after CCleaner wiped my saved passwords. Things that matter for a gaming PC:

- It does **not** wipe your GPU shader caches by default. Those are 3 GB on my machine and cleaning them weekly would mean shader recompiles in every game. It is an opt-in rule.
- Driver check talks to NVIDIA's own driver service and compares with what is installed, even when the dGPU is in Eco mode. It also pulls your laptop maker's driver list (ASUS automated, others linked). Found a Wi-Fi driver two versions behind on mine that Windows Update never showed.
- Stops background services that are eating CPU or RAM while their app is not open (think vendor update agents), never Windows or security services, and you can undo it.
- Standard junk cleanup: temp files, crash dumps (8 GB of kernel dumps on my machine, which was its own warning sign), logs, update caches, browser caches. Passwords, autofill, cookies and history are never touched.

Free, MIT licensed, no account, no cloud, plain PowerShell underneath. No executables in the download, so no SmartScreen drama: scripts and a Setup.cmd, zip scans 0/65 on VirusTotal (https://www.virustotal.com/gui/file/21011f960d227a67c9fd34fcf7cd4ad2a63c720158347f7b24b4d8703abc25b9).

https://github.com/undercutacademy/PCleaner
