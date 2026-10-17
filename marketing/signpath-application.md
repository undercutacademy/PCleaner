# Code signing: SignPath Foundation application

SignPath Foundation signs releases of open-source projects for free. Once approved, every release of
PCleaner gets a trusted Authenticode signature, which removes the SmartScreen "unknown publisher" prompt
and the machine-learning antivirus flags on the launcher executables (currently 7/71 on VirusTotal for the
unsigned `PCleaner.exe`, 0 for every script).

Apply here (you, as the project owner; it asks for a contact email and GitHub account):
https://signpath.org/apply

Requirements they check, all already met or easy:
- OSI-approved license: MIT, yes.
- Public source repository with the build process visible: `build/Build-Release.ps1`, yes.
- Builds must be reproducible from the repo by their CI (GitHub Actions). I will add a workflow that runs
  `build/Build-Release.ps1 -WithExe` on a Windows runner and uploads the artifacts, which is also what their
  signing connector consumes.
- A code of conduct / contributing note is a plus: say so if asked, and I'll add CONTRIBUTING.md.

Suggested answers for the form:

- **Project name**: PCleaner
- **Repository**: https://github.com/undercutacademy/PCleaner
- **Description**: Local, open-source CCleaner replacement for Windows: junk cleaning, idle-service taming and
  driver checks against NVIDIA, the laptop maker and Windows Update. Plain PowerShell 5.1 and WPF, no cloud, no
  license, no telemetry. MIT.
- **Why signing matters**: the only compiled part is a 37 KB launcher stub (C#, hosts the PowerShell engine
  in-process). Unsigned, it is flagged by ML heuristics on shape alone even though all logic is readable
  script; signed, users get a normal double-click install without SmartScreen warnings.
- **Artifacts to sign**: `PCleaner.exe`, `Setup.exe` (and the release zip's manifest if they offer it).
- **Build system**: GitHub Actions, Windows runner, `powershell -File build/Build-Release.ps1 -WithExe`.

Alternatives if SignPath declines or takes too long:
- Azure Trusted Signing, about USD 10 per month, individual identity validation, signs with `signtool` or the
  Trusted Signing GitHub Action. Fastest paid route.
- Certum Open Source Code Signing certificate, about EUR 70 per year, delivered on a USB token.

After signing is live: `build\Build-Release.ps1 -WithExe`, put the exes back in the README install steps,
reopen the winget submission (`winget.md`), and rescan on VirusTotal.
