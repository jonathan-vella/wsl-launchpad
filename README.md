# WSL Launchpad

Set up a Windows development environment with **Azure Linux 4 on WSL** and
native Linux developer tools: Azure CLI, GitHub CLI, Bicep, Copilot CLI, and Git.
Azure Linux 4 is **in preview** and is not recommended for production.

**You do not need to fork this repository or create your own GitHub copy.**
Clone it locally or download and extract a ZIP. Keep personal configuration in
your own dotfiles repository or local overrides; maintain a separate GitHub
copy only if you want to maintain a customized version of Launchpad.

The steps below run first in **Windows PowerShell 7**, then **inside Linux**.
You do not need to install Azure Linux or create its user beforehand.

## What setup changes

The bootstrap:

- Installs a signature- and checksum-verified `AzureLinux-4` distribution if
  it is missing, or reuses the existing one.
- Installs or updates native Linux tools and enables weekly RPM updates.
- Creates your chosen Linux user if needed.
- **Makes AzureLinux-4 the default WSL distribution and your chosen user its
  default account.** This changes what a plain `wsl` command opens.

It does not remove, stop, convert, or recreate existing distributions, sign
you in, copy Windows credentials, or apply dotfiles. Existing distributions
such as Ubuntu and Docker's WSL distributions remain installed.

## Before you start

- Windows on native **x64 or ARM64**, hardware virtualization, and WSL 2.
- PowerShell **7.4 or newer** on Windows (`pwsh`), not the built-in Windows
  PowerShell 5.1.
- WSL **2.6.0 or newer**. The bootstrap checks this and does not install or
  update WSL for you.
- For a fresh distribution only: GnuPG (`gpg.exe` on `PATH` or the copy included
  with Git for Windows) to verify Microsoft's signed image checksum.
- Internet access to Microsoft's Azure Linux/WSL services, GitHub's
  unauthenticated release API and official release assets, GitHub CLI packages,
  and Azure Linux package repositories.
- Enough disk space for the distribution and packages.
- Git for Windows if using the clone instructions below. Its bundled GnuPG
  can also satisfy the image-verification prerequisite.

Open **PowerShell 7** from the Start menu or select its profile in Windows
Terminal. Check the prerequisites there:

```powershell
$PSVersionTable.PSVersion
wsl --version
wsl --status
```

If PowerShell 7 is missing, follow Microsoft's
[PowerShell installation instructions](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows).
For Git and its bundled GnuPG, use [Git for Windows](https://gitforwindows.org/).

If WSL is not installed, open an elevated Windows terminal and run
`wsl --install --no-distribution`. If WSL is older, run `wsl --update`. Complete
any elevation or reboot prompts, then reopen PowerShell. Launchpad does not
self-elevate, enable Windows features, or reboot Windows. A pending Windows
servicing reboot stops setup.

## Set up the core environment

### 1. Get a local copy

Run in **Windows PowerShell 7**, from the folder where you want to keep
Launchpad:

```powershell
git clone https://github.com/jonathan-vella/wsl-launchpad.git
Set-Location .\wsl-launchpad
```

Alternatively, select **Code > Download ZIP** on GitHub, extract the archive,
then open PowerShell 7 in the extracted folder containing `bootstrap.ps1` and
`provision.sh`. Downloading a ZIP does not replace the GnuPG prerequisite.

If the repository requires authentication, use a GitHub account with access.
Do not put a token in the clone URL or scripts.

### 2. Choose a Linux username and run setup

In the examples, **replace `devuser` with your chosen username everywhere**.
It does not need to match your Windows username. Start with a lowercase letter
or underscore, followed by lowercase letters, digits, underscores, or hyphens;
use at most 32 characters. Do not choose `root`.

Run from the Launchpad folder in **Windows PowerShell 7**:

```powershell
pwsh -NoProfile -File .\bootstrap.ps1 -LinuxUser devuser
```

Allow the image download and package installation to finish. You do not need
to open a separate Linux terminal or create an account during this step.

The bootstrap checks the Windows architecture and WSL prerequisites. If
`AzureLinux-4` is missing, it downloads the matching Microsoft `.wsl` image,
verifies Microsoft's signed checksum in a temporary keyring, and installs the
image without interactive setup. It then checks WSL 2, Azure Linux 4, native
architecture, and systemd before installing or updating the tools.

Successful setup ends with messages like:

```text
Core setup verified. Sign-ins and optional dotfiles remain separate human steps.
Open: wsl -d AzureLinux-4 -u devuser
```

If setup fails, fix the reported problem and rerun the same command with the
same username. The bootstrap reuses the distro and user; it does not reset
them. See [startup issues](#startup-issues) and the
[troubleshooting guide](docs/troubleshooting.md).

### 3. Verify and open Linux

In **Windows PowerShell 7**:

```powershell
wsl --list --verbose
wsl -d AzureLinux-4 --exec whoami
```

Expect an asterisk beside `AzureLinux-4`, `2` in its VERSION column, and your
chosen username from `whoami`.

Open a Linux shell in your home directory:

```powershell
wsl -d AzureLinux-4 -u devuser --cd "~"
```

The first interactive launch may print **"User account already exists,
skipping creation"** after asking you to create an account. This is harmless:
the bootstrap already created it. You do not need another account.

Run these checks **inside Linux**:

```bash
uname -m
command -v az gh bicep copilot
az --version
gh --version
bicep --version
az bicep version
copilot --version
systemctl is-enabled dnf5-automatic.timer
systemctl is-active dnf5-automatic.timer
```

Expect `x86_64` or `aarch64`, Linux command paths rather than Windows `.exe`
paths, tool versions, and `enabled` / `active` for the update timer.

### 4. Sign in to the services you use

Run **inside Linux** as your chosen user:

```bash
gh auth login --hostname github.com
az login
copilot
```

Follow each tool's prompts. These sign-ins are manual and separate from any
Windows sign-ins. A successful setup does not mean you have cloud access or
the subscription or entitlement a particular service requires.

### Linux passwords and administrator access

The bootstrap reuses an existing account if it passes the checks. For a new
account, it creates a home directory and `/bin/bash` shell with a **locked
password**. You can still open it through WSL as shown above.

The bootstrap does not grant sudo privileges or configure passwordless sudo.
Setting a password does not grant administrator access. For occasional Linux
administration, open a root shell from **Windows PowerShell**:

```powershell
wsl -d AzureLinux-4 -u root --cd "~"
```

Use that shell only for administrative tasks and run `exit` when finished.
Run normal development tools, sign-ins, and dotfiles installers as your
non-root user.

If you want a Linux password, set it interactively from **Windows PowerShell**:

```powershell
wsl -d AzureLinux-4 -u root -- passwd devuser
```

## Where to keep projects

Microsoft recommends keeping files in the filesystem where their tools run.
Use `~/src` for Linux development in WSL and a Windows folder for Windows-native
development. See the [WSL performance cheat sheet](docs/performance.md) for
editor setup, generated files, cross-filesystem access, and security tips.

The initial Launchpad checkout can stay on Windows because `bootstrap.ps1` runs
there. The recommended VS Code WSL workflow is documented, but remains
**unvalidated on Azure Linux 4** here.

## Optional Microsoft CFS feeds for APEX

Microsoft maintainers using APEX devcontainers can run
[`configure-cfs.ps1`](configure-cfs.ps1) once to persist their approved feed
settings for future Windows and WSL sessions. This removes the need to run the
APEX host launcher on every VS Code launch on that device.

This is **opt-in** and separate from the core bootstrap and dotfiles.
It does not install packages or change other users' defaults. Follow the
[Windows and WSL instructions](docs/cfs.md), including preview, activation,
verification, and removal.

## Optional dotfiles

**Skip this section if you only want the installed tools.** The core bootstrap
does not clone or apply dotfiles.

Choose either Launchpad's neutral starter or your own repository; do not
install both unless you intend to replace the first configuration.

For a **private GitHub repository**, authenticate **inside Linux** before
cloning:

```bash
gh auth login --hostname github.com
gh auth setup-git
```

Windows authentication is not automatically available inside Linux. Do not
copy credential caches or embed tokens in URLs.

### Use the included starter

The [`dotfiles/`](dotfiles/README.md) starter links shell hooks and a Git
include. It does not set Git identity or editor preferences.

For Linux configuration, keep a Launchpad checkout in the **Linux filesystem**.
Run **inside Linux** as your non-root user:

```bash
mkdir -p ~/src
git clone https://github.com/jonathan-vella/wsl-launchpad.git ~/src/wsl-launchpad
cd ~/src/wsl-launchpad
cat dotfiles/install.sh
```

After reviewing the installer, run:

```bash
bash ./dotfiles/install.sh
```

If that checkout already exists, use it rather than cloning over it.
Keep the checkout while your configuration links point into it.

The installer backs up existing destinations as `.bak`, `.bak.1`, and so on.
Use the documented local overrides for personal settings. Follow the
[dotfiles guide](dotfiles/README.md) for Git identity, recovery, and the
separate Windows PowerShell installer.

### Use your own dotfiles repository

Use your repository's own instructions and review its installer and tracked
Git identity before applying it. For example, **inside Linux**, replace the
example URL with your repository:

```bash
git clone https://github.com/YOUR-USERNAME/dotfiles.git ~/dotfiles
cd ~/dotfiles
cat README.md
```

If its instructions specify `install.sh`, review it with `cat install.sh`.
Only after checking its effects and backup behavior, run:

```bash
bash ./install.sh
```

Other repositories may use a different installer. Do not clone over an
existing `~/dotfiles` checkout or discard its local changes. Linux-side
VS Code settings do not configure the Windows VS Code client.

## Startup issues

These issues were observed during an ARM64 onboarding session with WSL
2.7.14 and Azure Linux systemd 258.4. They are not necessarily present on
every machine.

### "Failed to start the systemd user session"

The terminal can open even when the user's systemd services fail. Check
**inside Linux**:

```bash
systemctl status "user@$(id -u).service" --no-pager
journalctl -b -u "user@$(id -u).service" --no-pager -n 50
```

In the observed case, Azure Linux and Ubuntu used the same user ID, `1000`,
and their systemd user managers collided in WSL's shared cgroup hierarchy.
The journal reported **"Failed to spawn executor: Device or resource busy"**.
That message alone is not enough to diagnose every occurrence.

To investigate that case, save work and close applications in both distros.
In **Windows PowerShell**, list running distributions:

```powershell
wsl --list --verbose
```

If you choose to test with the other distro stopped, terminate only that
specific distro, then restart Azure Linux. For example, **only if your other
distro is named Ubuntu**:

```powershell
wsl --terminate Ubuntu
wsl --terminate AzureLinux-4
wsl -d AzureLinux-4 --cd "~"
```

These commands stop all processes in the named distros but do not delete
their files. Check the user service again after opening Linux. Another
application may automatically restart the other distro, and the issue can
recur. **Do not unregister a distro as a troubleshooting step:** unregistering
permanently deletes its data.

### WSLg service fails with "are the same file"

A separate observed failure came from WSL's generated `wslg-session.service`.
It tried to link the PulseAudio socket into a path that already resolved to
that same socket. The `ln` command failed, marking the service failed even
though that alone does not establish whether GUI audio works.

Once the user manager is working, inspect it **inside Linux**:

```bash
systemctl --user status wslg-session.service --no-pager
journalctl --user -b -u wslg-session.service --no-pager -n 50
```

This is separate from the account-creation message and your dotfiles. Terminal
tools can still work; GUI/audio behavior needs its own check. Do not delete
audio sockets or edit generated service files to hide the failure.

### Existing distro uses WSL 1 or has systemd disabled

The bootstrap does not convert WSL 1 distributions. Review and back up the
existing distro before choosing to run this in **Windows PowerShell**:

```powershell
wsl --set-version AzureLinux-4 2
```

If systemd is not PID 1, preserve the other sections in `/etc/wsl.conf`, set
`[boot] systemd=true`, save work, and restart only Azure Linux with
`wsl --terminate AzureLinux-4` from Windows PowerShell. Then rerun the bootstrap.
It does not edit this file or run a global WSL shutdown.

See the [troubleshooting guide](docs/troubleshooting.md) for prerequisites,
partial failures, and recovery.

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

Run from your Launchpad folder in **Windows PowerShell 7**, using the same
Linux username as before:

```powershell
pwsh -NoProfile -File .\bootstrap.ps1 -LinuxUser devuser
```

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

## Download verification

For a fresh install, the signed checksum must come from the trusted Microsoft
key with fingerprint
`2BC9 4FFF 7015 A5F2 8F15 37AD 0CD9 FED3 3135 CE90`; the image must match the
architecture-specific checksum in the signed manifest. This fingerprint is a
trust anchor, not a version pin. If the key changes, verification stops until
the new key is reviewed independently.

Bicep and Copilot CLI downloads require official release URLs and SHA-256
digests from the official release API. The bootstrap does not use a GitHub
token or authenticated download header. Never bypass signature or checksum
verification to get past a setup failure.

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
