# Validation status

Azure Linux 4 is a preview. The upstream `4.0` branch describes it as in
development. Mocked tests, metadata checks, and an existing-distro run do not
prove that fresh installs or all architectures work.

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

## Evidence matrix

| Path | Status | What the evidence means |
|---|---|---|
| Existing native x64 Azure Linux 4 core setup and rerun | **Recorded successful** | The source README describes the live run; Launchpad did not reproduce it. |
| x64/ARM64 release metadata and Microsoft checksum signatures | **Recorded checked** | Windows metadata/signature check only, not installation or native execution. |
| Isolated PowerShell/Bash tests | **Automated, mocked** | Safe logic/regression coverage; no real WSL, network install, or sign-in. |
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

- [Azure Linux 4 upstream README](https://github.com/microsoft/azurelinux/blob/4.0/README.md): status and WSL package links.
- [Microsoft WSL image signature and checksum procedure](https://github.com/microsoft/azurelinux/blob/4.0/docs/verify-wsl-signature-and-checksum.md).
