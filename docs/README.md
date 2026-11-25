# Launchpad documentation

Azure Linux 4 became [generally available on November 17, 2026](https://techcommunity.microsoft.com/blog/LinuxandOpenSourceBlog/azure-linux-4-is-generally-available/4573381).
Its [WSL edition receives best-effort support](https://learn.microsoft.com/azure/azure-linux/windows-subsystem-for-linux-overview).
Launchpad's own evidence and remaining gaps are listed in [validation status](validation.md).

## Start here

Follow [setup](setup.md) to prepare Windows, install or reuse AzureLinux-4,
verify the tools, and sign in from Linux. Commands are labeled by the
environment where they run. You do not need an existing Linux account or
a fork of Launchpad.

| Task | Guide |
|---|---|
| Install and verify the core environment | [Setup](setup.md) |
| Maintain an existing installation and take backups | [Maintenance](maintenance.md) |
| Diagnose prerequisites, startup, and recovery | [Troubleshooting](troubleshooting.md) |
| Keep projects and tools in the right filesystem | [Performance and VS Code](performance.md) |
| Apply the neutral starter or your own configuration | [Optional dotfiles](dotfiles.md) |
| Review Windows/WSL security guidance | [Defender](defender.md) |
| Inspect evidence, download verification, and local tests | [Validation](validation.md) |
| Check where the code came from | [Provenance](provenance.md) |

## Microsoft corporate and APEX users

[CFS setup](cfs.md) is a separate device opt-in for Microsoft corporate package
feeds. It retains APEX settings and can also configure native Windows and WSL
clients. Skip it unless your environment requires these feeds; keep your
organization's approved sources instead. The core bootstrap and dotfiles
installers do not run it.

APEX devcontainers are not the native WSL environment. Container settings,
host settings, and Linux client settings have different scopes. CFS proxy
defaults are for interactive laptops and dev boxes, not automated builds or CI.
