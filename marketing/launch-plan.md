# PCleaner launch plan

Goal: let people clean their PC for free, and get PCleaner recommended wherever "CCleaner alternative" comes up.

The two things every post repeats (pick the order per audience):
1. **Trust.** Passwords, autofill, cookies, history and bookmarks are on a hard never-delete list. Everything that runs is readable PowerShell; the download contains no executables, only scripts and two .cmd starters, and the zip scans clean on VirusTotal. No cloud, no license, no upsell, no telemetry.
2. **It does the CCleaner jobs that matter.** Junk cleaning, idle-service taming, and driver checks that actually compare against NVIDIA and your laptop maker, not just Windows Update.

Secondary story, use it where people like it (HN, X, dev.to): it was built by reverse-engineering CCleaner 7 with an AI reverse-engineering toolkit and Claude, in a day, after getting annoyed that CCleaner wiped saved passwords.

## Before the first post (checklist)

- [x] Screenshots in the README (both themes)
- [x] winget manifest written (`marketing/winget`); submission on hold until releases are code-signed, see `winget.md`
- [ ] Apply to SignPath Foundation for free open-source code signing (`signpath-application.md`)
- [x] VirusTotal scan of `PCleaner-1.1.0.zip`: 0/65, https://www.virustotal.com/gui/file/21011f960d227a67c9fd34fcf7cd4ad2a63c720158347f7b24b4d8703abc25b9 (in README and release notes)
- [ ] GitHub repo: add topics `windows`, `powershell`, `wpf`, `ccleaner-alternative`, `system-cleaner`, `driver-updater`; add the one-line description; enable Discussions
- [ ] Pin the v1.1.0 release and make sure the zip downloads without a sign-in
- [ ] Decide whose name goes on the MIT license line (currently "PCleaner authors")
- [ ] Build some comment history on r/Windows11 and r/software (a week of normal, helpful comments is enough)

## Calendar (US Eastern)

| When | Where | File | Who clicks |
|---|---|---|---|
| Day 1 (Tue-Thu), 9:00-10:00 am | Hacker News, Show HN | `show-hn.md` | you (then reply for 3 hours) |
| Day 1, 10:15 am | X | `x-post.md` | you or Claude via your browser |
| Day 1, 11:00 am | r/opensource, r/SideProject, r/PowerShell | `reddit/*.md` | you or Claude via your browser |
| Day 2 | AlternativeTo listing, MajorGeeks email, Softpedia form | `directories.md` | Claude via your browser; emails from your Gmail drafts |
| Day 3 | r/Windows11, r/software, r/pcmasterrace (check rules the same morning) | `reddit/*.md` | you (needs your account history) |
| Day 4 | dev.to article, cross-posted to Hashnode and Medium | `devto-article.md` | Claude drafts, you publish |
| Day 5 | Lemmy: !opensource@lemmy.ml, !windows@lemmy.world | reuse `reddit/opensource.md` | either |
| Week 2 | YouTube outreach: Chris Titus Tech, ThioJoe, Britec | `outreach-emails.md` | you send from Gmail drafts |
| Ongoing | answer GitHub issues within a day; ship 1.1.x fixes fast | | you + Claude |

## Rules of engagement

- Never ask anyone to upvote, never post the same link from two accounts, never vote on your own posts from another device. HN and Reddit detect it and bury the project.
- Reply to every comment on launch day in your own words. Criticism about "running an elevated script from a stranger" is fair: answer with the VirusTotal link, the readable source, and the no-binaries fact.
- One honest limitation in every post: vendor driver checks cover NVIDIA and ASUS automatically; other makers get a link.
- Do not call it "CCleaner" anywhere in a title in a way that implies affiliation. "CCleaner replacement" or "CCleaner alternative" is fine.
- If a post is removed, do not repost the same day. Message the mods once, politely, with the open-source license and a screenshot.

## What success looks like in week 1

- Show HN stays on the front page for a couple of hours and the thread has 50+ comments with real questions
- 500+ stars, 1,000+ zip downloads (GitHub shows asset download counts on the release)
- At least one issue from a stranger that turns into a 1.1.1 release
- PCleaner appears on AlternativeTo under CCleaner
