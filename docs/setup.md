# Set up Azure Linux 4 on WSL

Launchpad runs first in Windows PowerShell 7, then installs native tools
inside AzureLinux-4-GA. You do not need to install Azure Linux or create its
user beforehand. Azure Linux 4 is
[generally available](https://techcommunity.microsoft.com/blog/LinuxandOpenSourceBlog/azure-linux-4-is-generally-available/4573381).
WSL receives [best-effort support](https://learn.microsoft.com/azure/azure-linux/windows-subsystem-for-linux-overview);
see [Launchpad validation status](validation.md) for what has actually been tested.

## Before you start

- Windows on native x64 or ARM64, hardware virtualization, and WSL 2.
- PowerShell 7.4 or newer on Windows, `pwsh`, not Windows PowerShell 5.1.
- WSL 2.6.0 or newer. Launchpad checks this but does not install or update WSL.
- For a fresh distribution: GnuPG, `gpg.exe` on PATH or bundled with Git for
  Windows, to verify Microsoft's signed image checksum.
- Internet access to Microsoft's Azure Linux/WSL services, Azure Linux package
  repositories, GitHub's unauthenticated release API and official release
  assets, and GitHub CLI packages.
- Enough disk space for the distribution and packages.
- Git for Windows if cloning; its bundled GnuPG can satisfy image verification.

On a managed device, follow your organization's installation and security
policies. Launchpad does not change Defender, firewall, or Intune settings.
Microsoft CFS feeds are [optional corporate configuration](cfs.md), not a
prerequisite for general users.

Open PowerShell 7 from Start or its Windows Terminal profile. Check there:

```powershell
$PSVersionTable.PSVersion
wsl --version
wsl --status
```

If PowerShell is missing, follow the
[Windows installation guide](https://learn.microsoft.com/powershell/scripting/install/installing-powershell-on-windows).
For Git and bundled GnuPG, use [Git for Windows](https://gitforwindows.org/).

If WSL is missing, open an elevated Windows terminal and run:

```powershell
wsl --install --no-distribution
```

If WSL is already installed but too old:

```powershell
wsl --update
```

Complete any elevation or reboot prompts, then reopen PowerShell 7.
`--no-distribution` installs WSL without adding the default Ubuntu distro.
Launchpad does not self-elevate, enable Windows features, or reboot Windows.
A pending Windows servicing reboot stops setup.

## What the bootstrap changes

It installs a signature- and checksum-verified AzureLinux-4-GA distro if missing,
or checks and reuses the existing one. It installs or updates native Linux tools, enables
weekly RPM updates, and creates your chosen Linux user if needed.
**AzureLinux-4-GA becomes the default WSL distribution, and your chosen user
becomes its default account.** This changes what a plain `wsl` command opens.

It does not remove, stop, convert, or recreate existing distributions, sign
you in, copy Windows credentials, or apply dotfiles. Ubuntu and Docker's
distributions remain installed. An older `AzureLinux-4` distro is left untouched.
Launchpad does not migrate its files, accounts, credentials, or beta repositories.

Before provisioning, Launchpad checks Azure Linux 4.0 identity, rejects
beta/preview branding, and requires the enabled `azurelinux-base` and
`azurelinux-microsoft` feeds to use Microsoft's `/azurelinux/4/prod/` endpoints.
The name alone is not proof of GA. A beta image registered as AzureLinux-4-GA
is rejected before package installation, user creation, or default changes.
Custom Azure Linux feed URLs require an explicit review; Launchpad does not
silently treat them as GA or rewrite them.

## 1. Get a local copy

In Windows PowerShell 7, from the folder where you want to keep Launchpad:

```powershell
git clone https://github.com/jonathan-vella/wsl-launchpad.git
Set-Location .\wsl-launchpad
```

No fork or personal GitHub copy is required. Alternatively, choose
Code > Download ZIP on GitHub, extract it, and open PowerShell 7 in the
folder containing `bootstrap.ps1` and `provision.sh`. A ZIP download does
not remove the GnuPG prerequisite.

If repository access requires authentication, use an account with access.
Never put tokens in clone URLs or scripts. Keep personal settings in
local overrides or your own dotfiles repository.

## 2. Choose a username and run setup

Replace `devuser` everywhere with your chosen non-root Linux username.
It need not match your Windows username. Start with a lowercase letter
or underscore, followed by lowercase letters, digits, underscores, or
hyphens; use at most 32 characters. Do not choose `root`.

From the Launchpad folder in Windows PowerShell 7:

```powershell
pwsh -NoProfile -File .\bootstrap.ps1 -LinuxUser devuser
```

Wait for downloads and installation to finish. No separate Linux terminal
or interactive account creation is needed during this step.

The bootstrap checks Windows architecture and WSL prerequisites, downloads
the matching Microsoft `.wsl` image if needed, and verifies its signed
checksum in a temporary keyring. It then checks WSL 2, Azure Linux 4,
native architecture, and systemd before provisioning.
See [download verification](validation.md#download-verification).

Successful setup ends with:

```text
Core setup verified. Sign-ins and optional dotfiles remain separate human steps.
Open: wsl -d AzureLinux-4-GA -u devuser
```

If setup fails, fix the reported problem and rerun with the same username.
The distro and user are reused, not reset. See [troubleshooting](troubleshooting.md).

## 3. Verify and open Linux

In Windows PowerShell 7:

```powershell
wsl --list --verbose
wsl -d AzureLinux-4-GA --exec whoami
```

Expect an asterisk beside AzureLinux-4-GA, `2` in its VERSION column, and your
chosen username from `whoami`. That column is the WSL version, not the
Azure Linux release. To check the OS from Linux, read `/etc/os-release`.

Open a Linux shell in your home directory:

```powershell
wsl -d AzureLinux-4-GA -u devuser --cd "~"
```

If the first interactive launch asks you to create an account and then says
"User account already exists, skipping creation", the bootstrap already
created it. You do not need another account.

Run these checks inside Linux:

```bash
cat /etc/os-release
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

Expect Azure Linux 4.0, `x86_64` or `aarch64`, Linux command paths rather
than Windows `.exe` paths, tool versions, and `enabled` / `active` for the timer.

## 4. Sign in inside Linux

As your chosen non-root Linux user:

```bash
gh auth login --hostname github.com
az login
copilot
```

Follow each tool's prompts. These sign-ins are separate from Windows sign-ins.
A successful setup does not establish cloud access, subscription permissions,
or a service entitlement. Launchpad does not copy credential caches or tokens.

## Linux passwords and administrator access

A new account has a home directory, `/bin/bash`, and a locked password.
WSL can open it without a password as shown above. Existing accounts are
reused only if they pass the checks; their metadata is not rewritten.

Launchpad does not grant sudo privileges or configure passwordless sudo.
Setting a password does not grant administrator access. For occasional
administration, open a root shell from Windows PowerShell:

```powershell
wsl -d AzureLinux-4-GA -u root --cd "~"
```

Use it only for administrative tasks and run `exit` afterwards. Run normal
development, sign-ins, and dotfiles installers as your non-root user.
To set that user's password interactively from Windows PowerShell:

```powershell
wsl -d AzureLinux-4-GA -u root -- passwd devuser
```

## Next tasks

Keep Linux projects under `~/src`; the initial Launchpad checkout can remain
on Windows because the bootstrap runs there. Follow [performance and VS Code
guidance](performance.md) for project storage and editor setup.
The VS Code WSL workflow remains unvalidated on Azure Linux 4 in this project.

Use [maintenance](maintenance.md) for updates and backups.
[Dotfiles](dotfiles.md) and [Microsoft corporate CFS feeds](cfs.md) are
separate opt-ins. Skip either if you do not need it.
