# Maintain an existing installation

Windows, WSL, Linux RPM packages, and standalone developer tools have separate
update mechanisms. Updating one does not update them all. Follow your
organization's maintenance policies on a managed device.

## Before changing an existing environment

Save work and check which distro you are using. In Windows PowerShell:

```powershell
wsl --list --verbose
```

Back up important projects and local configuration before package upgrades
or distro conversion. WSL supports distribution exports:

```powershell
wsl --export AzureLinux-4-GA C:\backups\AzureLinux-4-GA.tar
```

Create the destination folder first and choose an unused filename with
enough free space. An export can contain credentials and private files;
protect it like the original environment. For a quiet backup, close
applications and save work before stopping only AzureLinux-4-GA with
`wsl --terminate AzureLinux-4-GA`. This stops its processes, not its files.
Use [Microsoft's WSL command reference](https://learn.microsoft.com/windows/wsl/basic-commands)
for export/import options. Launchpad does not create distro backups for you.

## Windows and WSL updates

Use Windows Update for Windows servicing. In Windows PowerShell:

```powershell
wsl --update
wsl --version
```

Finish any requested reboot yourself. Launchpad does not update WSL,
restart Windows, or shut down your distributions automatically.

## Rerun Launchpad for developer tools

Update your Launchpad checkout without discarding local changes. For an
unchanged Git checkout, review `git status --short`, then `git pull --ff-only`.
If it has local changes or diverged history, resolve them before updating.
For a ZIP checkout, use a separately extracted current copy.

From that Windows checkout in PowerShell 7.4 or newer, use the same Linux
username as the original setup:

```powershell
pwsh -NoProfile -File .\bootstrap.ps1 -LinuxUser devuser
```

This reuses the distro and user, reconciles managed configuration, and
resolves current stable Bicep and Copilot CLI releases. It does not reinstall
the OS or replace an existing distro with a newer WSL image. Each run also
sets AzureLinux-4-GA and the chosen user as the WSL defaults.

### Moving from a beta installation

The older `AzureLinux-4` name is not reused by Launchpad. Back it up separately,
using its actual name:

```powershell
wsl --export AzureLinux-4 C:\backups\AzureLinux-4-beta.tar
```

Choose an unused destination in an existing folder. Then run the bootstrap
command above to create and configure the separate GA target. Migrate projects
and reviewed personal configuration selectively, and sign in again. Do not
import the beta export as the GA target; that retains its beta OS and feeds.
Keep the beta distro until the new environment works for you.

If AzureLinux-4-GA already exists but fails GA checks, stop and investigate.
Launchpad does not delete, convert, or repair beta instances under that name.

Bicep and Copilot CLI versions are not pinned; prereleases are not selected.
Unlike the source devcontainer, Launchpad does not wait seven days before
adopting a stable release. Rerunning may replace custom or prerelease standalone
binaries. Missing official SHA-256 digests, unexpected URLs, signature
mismatches, network errors, or API rate limits stop setup. Retry temporary
failures; never bypass [download verification](validation.md#download-verification).

Azure CLI comes from Azure Linux's existing Microsoft repository, GitHub CLI
from GitHub's official RPM repository. Git, `jq`, `curl`, `unzip`, `tar`,
`gzip`, `libicu`, and account/session utilities are also RPM packages.

## Linux package updates

The bootstrap installs and upgrades its selected RPM packages. It is not a
complete OS upgrade. To review and apply all available RPM upgrades yourself,
run from Windows PowerShell:

```powershell
wsl -d AzureLinux-4-GA -u root --exec dnf5 --refresh --setopt=gpgcheck=1 upgrade
```

Review the transaction before accepting. Preserve signature checking and
approved repository settings. A `VERSION_ID` of `4.0` identifies the OS series,
not whether all GA-era packages or later fixes are installed. An existing
pre-GA installation is not converted merely because the upstream release is GA.
An ordinary upgrade uses its configured feeds; `/beta/` feeds do not become
production feeds automatically. Use the separate GA setup described above
rather than blindly replacing repository URLs.

Launchpad enables `dnf5-automatic.timer` for RPM packages, including Azure CLI
and GitHub CLI. It runs Sunday at 06:00 in the distro's local time zone with
a random delay of up to one hour. WSL must be running; Windows does not wake
the distro for this timer. Missed runs may catch up on startup. Updates do
not reboot automatically.

DNF does not update standalone Bicep or Copilot CLI. Rerun the bootstrap
for those; Copilot's product-managed updater and cache are separate.
Inside Linux, inspect timer state or failures:

```bash
systemctl is-enabled dnf5-automatic.timer
systemctl is-active dnf5-automatic.timer
systemctl status dnf5-automatic.service --no-pager
journalctl -u dnf5-automatic.service --no-pager -n 50
systemctl cat dnf5-automatic.timer --no-pager
```

## Configuration and recovery

Rerunning core setup does not apply [dotfiles](dotfiles.md), refresh sign-ins,
or configure [CFS](cfs.md). Each has its own scope and activation steps.
Before undoing configuration, inspect the first-run backups described in
[recovery boundaries](troubleshooting.md#recovery-boundaries).
Restoring a configuration file does not roll back package upgrades.

For native Linux tool checks, use [setup verification](setup.md#3-verify-and-open-linux).
See [validation status](validation.md) for untested update and installation
paths; GA status is not a substitute for verifying your own environment.
