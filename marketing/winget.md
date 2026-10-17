# winget submission

**On hold.** winget needs a real installer binary inside the zip (`NestedInstallerType: exe`), and the unsigned
launcher scores 7/71 on VirusTotal, so pull request microsoft/winget-pkgs#454966 was closed. Reopen this once
releases are code-signed (see `signpath-application.md`): rebuild with `build\Build-Release.ps1 -WithExe`, refresh the
hash below, and submit again.

Manifests for 1.1.0 are in `marketing/winget/manifests/u/undercutacademy/PCleaner/1.1.0/`.
Package id: `undercutacademy.PCleaner`. Once merged, users run:

    winget install undercutacademy.PCleaner

## Validate locally

    winget validate --manifest marketing\winget\manifests\u\undercutacademy\PCleaner\1.1.0
    winget install --manifest marketing\winget\manifests\u\undercutacademy\PCleaner\1.1.0   # needs "Local manifest files" enabled in winget settings

## Submit

1. Fork https://github.com/microsoft/winget-pkgs (once).
2. Branch `undercutacademy.PCleaner-1.1.0`, copy the three yaml files to the same path inside the fork, commit, push.
3. Open a PR titled `New package: undercutacademy.PCleaner version 1.1.0`. Tick the checklist boxes in the PR template (manifest validated, tested install, no duplicate package).
4. Microsoft's bot validates the install in a VM; the installer must finish silently with `-Silent` and register the Apps & Features entry whose ProductCode is `PCleaner` (it does). Expect labels like `Validation-Completed`, then a human merge within a few days. Fix anything the bot flags by pushing to the same branch.

For every future release: bump `PackageVersion`, the `InstallerUrl`, the `InstallerSha256` and the `DisplayVersion`, and open a new PR. `wingetcreate update undercutacademy.PCleaner -u <zip url> -v <version> --submit` automates that once the first package exists.
