# WSL Launchpad

Set up a Windows development environment with **Azure Linux 4 on WSL** and
native Linux developer tools. Azure Linux 4 is **in preview** and is not
recommended for production.

The bootstrap installs a verified distribution only when `AzureLinux-4` is
absent. It does not remove, stop, convert, or recreate existing distributions.
After setup, it makes `AzureLinux-4` and your chosen Linux user the WSL defaults.
Review this change before running the bootstrap, especially if you already use
other WSL distributions.

## Before you start

- Windows on native **x64 or ARM64**, hardware virtualization, and WSL 2.
- Windows PowerShell **7.4 or newer**.
- WSL **2.6.0 or newer**. The bootstrap checks this and does not install or
  update WSL for you.
- For a fresh distribution only: GnuPG (`gpg.exe` on `PATH` or the copy included
  with Git for Windows) to verify Microsoft's signed image checksum.
- Internet access to Microsoft's Azure Linux/WSL services, GitHub's
  unauthenticated release API and official release assets, GitHub CLI packages,
  and Azure Linux package repositories.
- Enough disk space for the distribution and packages.

If WSL is not installed, open an elevated Windows terminal and run
`wsl --install --no-distribution`. If WSL is older, run `wsl --update`. Complete
any elevation or reboot prompts, then reopen PowerShell. Launchpad does not
self-elevate, enable Windows features, or reboot Windows. A pending Windows
servicing reboot stops setup.

## Set up the core environment

Download or clone this repository, then open PowerShell 7 from its directory.
Choose your own Linux username; do not use `root`:

```powershell
pwsh -NoProfile -File .\bootstrap.ps1 -LinuxUser devuser
```

The bootstrap checks the Windows architecture and WSL prerequisites. If
`AzureLinux-4` is missing, it downloads the matching Microsoft `.wsl` image,
verifies Microsoft's signed checksum in a temporary keyring, and installs the
image without interactive setup. It then checks WSL 2, Azure Linux 4, native
architecture, and systemd before installing or updating the tools.

The bootstrap reuses the chosen Linux user if it exists and passes the checks.
Otherwise, it creates the user with `/bin/bash` and a locked password. It does
not create a password, passwordless sudo rule, or cloud sign-in, and it does not
copy Windows credentials. To set a Linux password, run this from a root session:

```powershell
wsl -d AzureLinux-4 -u root -- passwd devuser
```

For a fresh install, the signed checksum must come from the trusted Microsoft
key with fingerprint
`2BC9 4FFF 7015 A5F2 8F15 37AD 0CD9 FED3 3135 CE90`; the image must match the
architecture-specific checksum in the signed manifest. This fingerprint is a
trust anchor, not a version pin. If the key changes, verification stops until
the new key is reviewed independently. Bicep and Copilot CLI downloads also
require official release URLs and SHA-256 digests from the official release
API. The bootstrap does not use a GitHub token or authenticated download header.

The bootstrap does not convert an existing WSL 1 `AzureLinux-4`. Review and back
it up before converting it yourself:

```powershell
wsl --set-version AzureLinux-4 2
```

Then rerun Launchpad. If systemd is disabled, preserve the other sections in
`/etc/wsl.conf`, set `[boot] systemd=true`, exit the distro's sessions, and
restart only that distro with `wsl --terminate AzureLinux-4`. Launchpad does
not edit this file or run a global WSL shutdown.

### Verify and sign in

In Windows PowerShell, check that the distro uses WSL 2 and is the default.
`whoami` confirms the default Linux user:

```powershell
wsl --list --verbose
wsl --exec whoami
```

Open the selected Linux account:

```powershell
wsl -d AzureLinux-4 -u devuser
```

Check that these commands resolve to Linux binaries and report their versions:

```bash
uname -m
command -v az gh bicep copilot
az --version
gh --version
bicep --version
az bicep version
copilot --version
systemctl status dnf5-automatic.timer
```

When needed, sign in **inside Linux** with your own accounts:

```bash
gh auth login --hostname github.com
az login
copilot
```

These sign-ins are manual. Launchpad does not copy Windows credential
caches, browser sessions, tokens, passwords, or subscriptions. A successful
setup does not mean you are signed in or have cloud access.

## Where to keep projects

Microsoft recommends keeping files in the filesystem where their tools run.
Use `~/src` for Linux development in WSL and a Windows folder for Windows-native
development. See the [WSL performance cheat sheet](docs/performance.md) for
editor setup, generated files, cross-filesystem access, and security tips.

The initial Launchpad checkout can stay on Windows because `bootstrap.ps1` runs
there. The recommended VS Code WSL workflow is documented, but remains
**unvalidated on Azure Linux 4** here.

## Optional dotfiles

The core bootstrap does not clone or apply dotfiles. The optional
[`dotfiles/`](dotfiles/README.md) starter links neutral shell hooks and a Git
include. It does not set your Git identity or editor preferences. Review its
backup and override behavior before opting in, and run it as your user in the
environment you want to configure. You can also choose and review another
dotfiles repository.

## Tooling and updates

The bootstrap installs Azure CLI from Azure Linux's existing Microsoft
repository, GitHub CLI from GitHub's official RPM repository, and Git, `jq`,
`curl`, `unzip`, `tar`/`gzip`, `libicu` and account/session utilities. It also
installs standalone Bicep and Copilot CLI binaries from their official GitHub
latest-release endpoints.

Each run resolves the **latest stable** Bicep and Copilot CLI release. Versions
are not pinned, and prereleases are not used. Unlike the dev-container, the
bootstrap does not wait seven days before adopting a stable release. It requires
an official SHA-256 asset digest and verifies the download before installing.
Missing digests, unexpected URLs, signature mismatches, network errors, or API
rate limits stop setup. Retry a temporary publishing or rate-limit failure;
never bypass verification.

Rerun the same command to reconcile configuration and resolve current stable
standalone releases. The bootstrap reuses the distro and user; it does not
rebuild the OS. It may replace a prerelease or custom standalone binary with
the current stable release.

DNF automatic updates are enabled for RPM packages, including Azure CLI and
GitHub CLI. The timer runs **Sunday at 06:00 in the distro's local time zone**,
with a random delay of up to one hour. WSL must be running; Windows does not
wake the distro for updates. Missed runs may catch up when the distro starts.
Updates do not reboot automatically.

DNF does **not** update standalone Bicep or Copilot CLI. Rerun the bootstrap to
update them. Copilot's product-managed updater and cache are separate. Check
package-update failures with:

```bash
systemctl status dnf5-automatic.service
journalctl -u dnf5-automatic.service
systemctl cat dnf5-automatic.timer
```

See [`docs/validation.md`](docs/validation.md) for test evidence,
[`docs/troubleshooting.md`](docs/troubleshooting.md) for recovery steps, and
[`docs/defender.md`](docs/defender.md) for Microsoft Defender guidance.

## Safe local checks

These tests use temporary fixtures and mock WSL, network, GPG, and release
responses. They do not provision WSL, install packages, sign in, or run the
dotfiles installer.

```powershell
pwsh -NoProfile -File .\tests\test-bootstrap.ps1
```

```bash
bash -n provision.sh tests/test-provision.sh
bash tests/test-provision.sh
```

The dotfiles Bash installer tests need symlink support. They run on Linux and
macOS. On Git Bash, the suite skips if it cannot create symlinks.

```bash
bash -n dotfiles/install.sh dotfiles/tests/install.sh
bash dotfiles/tests/install.sh
```

See [`docs/provenance.md`](docs/provenance.md) for source and license history.
