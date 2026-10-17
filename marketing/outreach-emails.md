# YouTube outreach

Find each channel's business email on its YouTube "About" page (click "View email address"). Send from your own Gmail. One email, no follow-up for two weeks, then one polite nudge. Attach nothing; link everything.

## Chris Titus Tech (WinUtil author, PowerShell-friendly audience)

    Subject: Open-source CCleaner replacement in pure PowerShell (your audience's kind of tool)

    Hi Chris,

    Long-time WinUtil user. I built something adjacent that your viewers might like: PCleaner, a free,
    MIT-licensed CCleaner replacement in plain Windows PowerShell 5.1 + WPF, nothing to install.

    Three jobs: junk cleaning with an Analyze step, stopping idle resource-hungry services with a protected
    list and revert, and a driver check that compares against NVIDIA's driver service and the laptop maker's
    catalogue (ASUS automated), not just Windows Update. Browser passwords, autofill, cookies and history are
    on a hard never-delete list in the engine.

    It came out of reverse-engineering CCleaner 7 (its cleaner is a 769-rule ini file, its driver updater
    posts hardware IDs to a paid backend). Write-up and screenshots: https://github.com/undercutacademy/PCleaner

    If it is useful to you, great. If you tear it apart on stream, also great; I'll fix what you find.

    [name]

## ThioJoe (mainstream Windows tips, large audience)

    Subject: Free CCleaner alternative that can't delete your passwords (open source)

    Hi Joe,

    You've covered why CCleaner isn't what it used to be. I built a free, open-source replacement that
    keeps the useful parts and drops the rest: PCleaner. It cleans junk (with a preview first), stops
    background services that are hogging CPU or memory while their app isn't open, and checks drivers
    against NVIDIA and the laptop maker directly. Passwords, autofill, cookies and history physically
    cannot be deleted by it.

    No account, no cloud, no upsell, MIT licensed, 10 GB freed on my own laptop on the first run.
    https://github.com/undercutacademy/PCleaner (screenshots in the README)

    Happy to answer any questions or provide a build with anything you'd want to test.

    [name]

## Britec09 (repair-shop audience, trusts tools that explain themselves)

    Subject: Open-source maintenance tool with full reports: PCleaner

    Hi Brian,

    For your kind of audience: PCleaner is a free, MIT-licensed Windows maintenance tool that writes an
    HTML report for every run, so you can see exactly what it removed, which services it stopped and why,
    and which drivers are behind according to NVIDIA, the laptop maker and Windows Update.

    It is conservative by default (temp files older than a day, Recycle Bin older than a week, shader
    caches left alone, Windows and security services protected) and it never touches browser passwords,
    autofill, cookies or history. Plain PowerShell underneath so you can read every line.

    https://github.com/undercutacademy/PCleaner

    Would love your honest take.

    [name]
