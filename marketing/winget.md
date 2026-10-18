# winget submission

Manifests for 1.1.0 are in `marketing/winget/manifests/u/undercutacademy/PCleaner/1.1.0/`.
Package id: `undercutacademy.PCleaner`, installer type `inno` (the per-user `PCleaner-<version>-Setup.exe`).
Once merged, users run:

    winget install undercutacademy.PCleaner

History: the first PR (microsoft/winget-pkgs#454966) shipped a zip with a hand-compiled launcher exe and was
closed when that exe drew antivirus heuristics. The Inno Setup installer replaces it; winget knows Inno's silent
switches natively, so no `InstallerSwitches` are needed.

## Validate locally

    winget validate --manifest marketing\winget\manifests\u\undercutacademy\PCleaner\1.1.0

## Submit

1. The fork https://github.com/undercutacademy/winget-pkgs already exists (local clone in `/tmp/winget-pkgs` on the dev box).
2. Branch `undercutacademy.PCleaner-1.1.0-inno` from `upstream/master`, copy the three yaml files to the same path, commit, push.
3. Open a PR titled `New package: undercutacademy.PCleaner version 1.1.0` and tick the checklist in the template.
4. Sign the Microsoft CLA when the bot asks (one click with your GitHub login). The bot then installs the package
   silently in a VM and checks that the Apps & Features entry matches the `ProductCode`
   (`{6C2D1F4B-9E3A-4B7C-8D05-1A2B3C4D5E6F}_is1`, Inno's standard form).

For every future release: bump `PackageVersion`, `InstallerUrl`, `InstallerSha256` and `DisplayVersion`, or run
`wingetcreate update undercutacademy.PCleaner -u <setup exe url> -v <version> --submit` once the first package exists.
