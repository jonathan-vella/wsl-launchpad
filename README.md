# WSL Launchpad

Set up Azure Linux 4 on WSL with native Linux developer tools:
Azure CLI, GitHub CLI, Bicep, Copilot CLI, and Git.

Azure Linux 4 is [generally available](https://techcommunity.microsoft.com/blog/LinuxandOpenSourceBlog/azure-linux-4-is-generally-available/4573381)
as of November 17, 2026. Azure Linux on WSL receives
[best-effort support](https://learn.microsoft.com/azure/azure-linux/windows-subsystem-for-linux-overview).
GA status does not mean every Launchpad path has been tested; see
[validation status](docs/validation.md).

## Get started

You do not need to fork the repository. Clone it or download and extract a ZIP.
Read the [setup guide](docs/setup.md) before running anything.

From a local Windows checkout, in **PowerShell 7.4 or newer**, replace
`devuser` with your chosen non-root Linux username:

```powershell
pwsh -NoProfile -File .\bootstrap.ps1 -LinuxUser devuser
```

Requires native x64 or ARM64 Windows, WSL 2.6.0 or newer, and GnuPG for a
fresh image install. Launchpad does not install WSL or reboot Windows.

The bootstrap installs AzureLinux-4 if missing, otherwise reuses it. It
installs or updates Linux tools, enables weekly RPM updates, and creates the
chosen user if needed. **It makes AzureLinux-4 and that user the WSL defaults.**
It does not delete other distributions, sign you in, or apply dotfiles.

## Documentation

Start with the [documentation index](docs/README.md).

| Task | Guide |
|---|---|
| First-time setup, sign-in, and Linux accounts | [Setup](docs/setup.md) |
| Update WSL, packages, and developer tools | [Maintenance](docs/maintenance.md) |
| Diagnose startup and partial setup failures | [Troubleshooting](docs/troubleshooting.md) |
| Choose project storage and use VS Code | [Performance](docs/performance.md) |
| Apply optional shell and Git configuration | [Dotfiles](docs/dotfiles.md) |
| Configure Microsoft corporate/APEX package feeds | [CFS](docs/cfs.md) |
| Understand Defender and managed-device boundaries | [Defender](docs/defender.md) |
| Review test evidence and run isolated checks | [Validation](docs/validation.md) |
| Review source and license history | [Provenance](docs/provenance.md) |

CFS is a separate Microsoft corporate opt-in, not a general setup requirement
or a replacement for authenticated CI feeds. Personal configuration belongs
in local overrides or your own dotfiles repository. Keep a separate GitHub
copy only if you intend to maintain a customized Launchpad.
