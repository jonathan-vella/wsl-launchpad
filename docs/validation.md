# Validation status

Azure Linux 4 became [generally available on November 17, 2026](https://techcommunity.microsoft.com/blog/LinuxandOpenSourceBlog/azure-linux-4-is-generally-available/4573381).
Azure Linux on WSL receives [best-effort support](https://learn.microsoft.com/azure/azure-linux/windows-subsystem-for-linux-overview).
GA describes the upstream release, not Launchpad test coverage. Mocked tests,
metadata checks, and an existing-distro run do not prove that fresh installs
or all architectures work.

## Evidence from the source implementation

The bootstrap and tests came from
[`the-ultimate-csa-toolkit`](https://github.com/jonathan-vella/the-ultimate-csa-toolkit)
revision
[`3906eba2dc13180afbd757ccfd3c46255478b8a7`](https://github.com/jonathan-vella/the-ultimate-csa-toolkit/commit/3906eba2dc13180afbd757ccfd3c46255478b8a7).
Its WSL README records a successful core setup and rerun with the latest stable
tools on **an existing native x64 AzureLinux-4** on 2026-10-26. It reports
native paths and versions, timer state, preserved configuration across reruns,
and Ubuntu and Docker distributions that remained registered and running. The
source repository records this result; Launchpad did not reproduce it.

The source README also records checks of official release metadata and
Microsoft's image-checksum signatures for x64 and ARM64 from Windows. These
checks cover the metadata and signature process, not package installation or
native ARM64 compatibility.

The migrated tests use mocks and temporary fixtures. They cover release
selection and digests, signed-image validation, WSL command transport and
orchestration, failure handling, reruns, configuration preservation, and
checksum rejection. They do not run WSL or install packages.
GA-target regression tests cover side-by-side installation when the older
`AzureLinux-4` exists, WSL-version checking against `AzureLinux-4-GA`, and
unchanged defaults after a rejected target. Linux fixtures check GA identity,
production feeds, and rejection of beta branding, beta URLs, duplicate sections,
disabled feeds, and missing repository files. These are not live GA install evidence.

The optional [CFS device setup](cfs.md) has isolated PowerShell tests for
feed values, bidirectional WSL forwarding, existing user/machine entry
preservation, reruns, `-WhatIf`, and persistence/verification failures.
Native-client coverage uses temporary NuGet/Cargo files and mocked repository
and WSL operations; it checks source preservation, backups, conflicts, and
explicit distribution targeting without changing the host.
These tests mock all persistent environment access. They do not prove that a
real Windows sign-out, WSL restart, devcontainer rebuild, or CFS download succeeds.

## Evidence matrix

| Path | Status | What the evidence means |
|---|---|---|
| Existing native x64 Azure Linux 4 core setup and rerun | **Recorded successful** | The source README describes the live run; Launchpad did not reproduce it. |
| x64/ARM64 release metadata and Microsoft checksum signatures | **Recorded checked** | Windows metadata/signature check only, not installation or native execution. |
| Isolated PowerShell/Bash tests | **Automated, mocked** | Safe logic/regression coverage; no real WSL, network install, or sign-in. |
| Optional CFS settings, native client configuration, and WSL forwarding | **Automated, mocked** | Temporary client files only; no real user settings are written. Activation and package restores remain unvalidated. |
| Fresh x64 `.wsl` installation | **Unvalidated** | No live fresh installation evidence. |
| Native ARM64 core provisioning | **Unvalidated** | No native ARM64 execution evidence. |
| Optional dotfiles onboarding/reruns | **Not included** | Core setup does not clone or install dotfiles. |
| Interactive GitHub/Azure/Copilot sign-in | **Unvalidated** | Users sign in themselves; tests do not exercise sign-in. |
| VS Code WSL connection on Azure Linux 4 | **Unvalidated** | The documented Microsoft workflow, server, and extensions have not been tested here. |
| Azure deployment or application build | **Out of scope** | No cloud resources or app deployment are performed. |
| Future unattended DNF timer firing | **Unvalidated** | Timer configuration/state was checked in the recorded x64 run; a future firing was not observed. |

Do not call the first-time setup tested until a fresh x64 install and
verification succeed. Keep ARM64 and optional paths marked unvalidated until
they are tested on their target environments.

## Upstream references

- [Azure Linux 4 GA announcement](https://techcommunity.microsoft.com/blog/LinuxandOpenSourceBlog/azure-linux-4-is-generally-available/4573381): release status.
- [Azure Linux on WSL](https://learn.microsoft.com/azure/azure-linux/windows-subsystem-for-linux-overview): downloads and support scope.
- [Azure Linux 4 upstream README](https://github.com/microsoft/azurelinux/blob/4.0/README.md): source and WSL package links.
- [Azure Linux production base feed](https://github.com/microsoft/azurelinux/blob/4.0/base/comps/azurelinux-repos/azurelinux.repo) and [Microsoft feed](https://github.com/microsoft/azurelinux/blob/4.0/base/comps/azurelinux-repos/microsoft.repo): GA repository templates checked by Launchpad.
- [Microsoft WSL image signature and checksum procedure](https://github.com/microsoft/azurelinux/blob/4.0/docs/verify-wsl-signature-and-checksum.md).

## Download verification

For a fresh install, the signed checksum must come from Microsoft's trusted
key with fingerprint
`2BC9 4FFF 7015 A5F2 8F15 37AD 0CD9 FED3 3135 CE90`. The image must match
the architecture-specific checksum in that manifest. The fingerprint is a
trust anchor, not a version pin. If the key changes, verification stops
until the new key is reviewed independently.

Bicep and Copilot CLI downloads require official release URLs and SHA-256
digests from the official release API. The bootstrap does not use a GitHub
token or authenticated download header. Never bypass signature or checksum
verification to get past a setup failure.

## Safe local checks

Run commands from the repository root, not the `docs` directory. These tests
use temporary fixtures and mock WSL, network, GPG, release responses, and
device settings. They do not provision WSL, install packages, sign in, or
apply dotfiles to your actual user.

In Windows PowerShell 7.4 or newer:

```powershell
pwsh -NoProfile -File .\tests\test-bootstrap.ps1
pwsh -NoProfile -File .\tests\test-cfs.ps1
pwsh -NoProfile -File .\dotfiles\tests\Install.Tests.ps1
```

Inside Linux:

```bash
bash -n provision.sh tests/test-provision.sh
bash tests/test-provision.sh
bash -n dotfiles/install.sh dotfiles/tests/install.sh
bash dotfiles/tests/install.sh
```

The Bash dotfiles tests need symlink support and run on Linux and macOS.
On Git Bash, the suite skips if it cannot create symlinks.
