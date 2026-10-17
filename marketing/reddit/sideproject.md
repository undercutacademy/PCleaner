# r/SideProject

Rules that matter: self-promotion is welcome; add a screenshot as the post image; be a person, not a brand.

**Title**

    I rebuilt the only three CCleaner features I used, as a free open-source app, after it deleted my passwords again

**Body** (post as an image post with `assets/screenshots/health-dark.png`, text in the body)

CCleaner's been going downhill for years: upsells, telemetry, and a default that wipes saved passwords and autofill. I use exactly three things from it: junk cleaning, stopping background stuff, checking drivers. So I rebuilt those.

PCleaner is a local Windows app, MIT licensed, no cloud, no license key, no nag screens. The first run on my own laptop freed 10 GB (mostly crash dumps and temp files I did not know were there).

The part I'm most pleased with: the driver check compares what you have against NVIDIA's own driver service and your laptop maker's download list, not just Windows Update. It found a Wi-Fi driver two versions behind on my machine.

Built in Windows PowerShell + WPF so there's nothing to install. The whole thing was reverse-engineered from the installed CCleaner with an AI RE toolkit and Claude in a day, then tested and polished for a couple more.

https://github.com/undercutacademy/PCleaner

Happy to hear what you'd want from a tool like this.
