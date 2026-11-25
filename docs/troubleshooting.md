# Troubleshooting and recovery

The bootstrap can resume after a failure. Fix the reported problem, then rerun
the same command with the same Linux username. It does not reset or recreate
`AzureLinux-4`.

If file access is slow, check the [project location and toolchain](performance.md)
first. Then see the [Defender guidance](defender.md). Do not disable Defender
to work around the problem.

## Windows and WSL prerequisites

- **WSL is missing or too old:** run `wsl --install --no-distribution`
  from an elevated terminal or `wsl --update`, as applicable. Complete any
  requested reboot yourself, then rerun.
- **Windows needs a reboot:** finish Windows servicing and reboot before retrying.
  The bootstrap will not restart the host.
- **Virtualization or WSL status error:** resolve the Windows/firmware prerequisite
  shown by `wsl --status`; rerun after WSL is ready.
- **GnuPG unavailable:** fresh image install requires `gpg.exe` on `PATH` or the
  Git for Windows copy at `C:\Program Files\Git\usr\bin\gpg.exe`. Install Git
  for Windows or GnuPG yourself, then retry. Existing distro setup does not
  require GnuPG.
- **No release digest, API rate limit, or download failure:** retry when the
  official endpoint is available. Do not use an unchecked binary or disable
  signature verification.

## Distribution checks

`wsl --list --verbose` shows WSL 1 or 2, not the Azure Linux release.
Check `cat /etc/os-release` inside Linux for the OS series and
`uname -m` for architecture. The [setup guide](setup.md#3-verify-and-open-linux)
lists expected tool and timer results.

- **AzureLinux-4 uses WSL 1:** review and back it up first. If you choose to
  convert it, run `wsl --set-version AzureLinux-4 2` manually and rerun. The
  bootstrap does not convert it.
- **Architecture mismatch:** do not force provisioning. The existing distro
  architecture must match the native Windows architecture; use a matching
  distro or make a separate, informed decision about the environment.
- **systemd is not PID 1:** preserve the other sections in
  `/etc/wsl.conf`, set `[boot] systemd=true`, exit sessions, and restart only
  AzureLinux-4 with `wsl --terminate AzureLinux-4`. Then rerun. The bootstrap
  does not edit this file or run `wsl --shutdown`.
- **Linux user rejected:** use an explicit non-root username matching the
  documented Linux account format. An existing account must have UID >=1000
  and an existing absolute home directory. Existing account metadata is not
  rewritten.
- **Provisioning failed partway through:** resolve the displayed package,
  network, or configuration problem and rerun. A newly installed distro may
  remain registered after a later failure; the bootstrap reuses it and does
  not recreate it.

## Startup issues

The following issues were observed during an ARM64 onboarding session with
WSL 2.7.14 and Azure Linux systemd 258.4. They are not necessarily present
on every machine. Azure Linux's GA status does not mean these WSL-specific
failures cannot occur.

### Account already exists

The first interactive launch may ask you to create an account, then report
"User account already exists, skipping creation". Launchpad already created
that user; this message alone is harmless. It is separate from systemd and
WSLg failures. Check the default user with the command in
[setup verification](setup.md#3-verify-and-open-linux).

### Failed to start the systemd user session

The terminal can open while the user's systemd services fail. Inside Linux:

```bash
systemctl status "user@$(id -u).service" --no-pager
journalctl -b -u "user@$(id -u).service" --no-pager -n 50
```

In the observed case, Azure Linux and Ubuntu both used UID `1000`, and their
systemd user managers collided in WSL's shared cgroup hierarchy. The journal
reported "Failed to spawn executor: Device or resource busy". That message
alone is not enough to diagnose every occurrence.

To investigate this case, save work and close applications in both distros.
In Windows PowerShell, list running distributions:

```powershell
wsl --list --verbose
```

If you choose to test with the other distro stopped, terminate only that
specific distro, then restart Azure Linux. Only if the other distro is named
Ubuntu:

```powershell
wsl --terminate Ubuntu
wsl --terminate AzureLinux-4
wsl -d AzureLinux-4 --cd "~"
```

These commands stop all processes in the named distros without deleting files.
Check the user service again. Another application may restart the other
distro, and the issue can recur. Do not unregister a distro to troubleshoot;
unregistering permanently deletes its data.

### WSLg service fails with "are the same file"

Another observed failure came from WSL's generated `wslg-session.service`.
It tried to link the PulseAudio socket to a path already resolving to that
socket. The `ln` failure marked the service failed but did not, by itself,
establish whether GUI audio worked.

Once the user manager works, inspect inside Linux:

```bash
systemctl --user status wslg-session.service --no-pager
journalctl --user -b -u wslg-session.service --no-pager -n 50
```

Terminal tools can still work; GUI/audio behavior needs its own check.
Do not delete audio sockets or edit generated service files to hide failures.

## Sign-in, updates, and optional configuration

- Run `gh auth login`, `az login`, and Copilot's interactive flow as the
  selected Linux user when needed. Core provisioning does not sign in or copy
  credentials from Windows.
- Choose and run dotfiles separately. Review the repository, branch, installer,
  identity settings, backups, and local overrides. Run the installer as your
  Linux user, not root.
- If an existing `~/dotfiles` checkout has uncommitted or divergent changes,
  resolve them manually. Do not discard them to install an update.
- To undo optional dotfiles, follow the [link and backup recovery steps](dotfiles.md#undo-the-starter).
  Do not delete the checkout while active links still point into it.
- For DNF failures or timer settings, use the commands in the
  [maintenance guide](maintenance.md#linux-package-updates). Rerun Launchpad
  to update standalone Bicep and Copilot CLI; DNF does not update them.
- Microsoft corporate/APEX users should check the [CFS client scope and activation
  steps](cfs.md) when package downloads fail. Other users should keep their
  approved package sources. Do not disable TLS checks or bypass feed restrictions.

## Recovery boundaries

- The bootstrap saves the original DNF/timer configuration next to the managed
  configuration as `.wsl-launchpad-before-bootstrap`. It preserves unrelated
  INI settings and refuses managed config symlinks. If an earlier toolkit run
  left a `.csa-before-bootstrap` backup, the bootstrap keeps it and does not
  create a new baseline. Inspect files and backups before restoring them.
- The bootstrap may install or upgrade packages and replace standalone Bicep
  and Copilot CLI binaries. It does not roll back package upgrades when you
  restore a configuration backup.
- To restore the previous default distro, select it with
  `wsl --set-default <your-distro>`. To change that distribution's default
  Linux user, use WSL's `--manage ... --set-default-user` operation after
  reviewing its supported syntax with `wsl --help`.
- Do not unregister the distro or delete user files to recover. Back up your
  data and investigate the failure first.
