# Troubleshooting and recovery

The bootstrap can resume after a failure. Fix the reported problem, then rerun
the same command with the same Linux username. It does not reset or recreate
`AzureLinux-4`.

If file access is slow, check the [project location and toolchain](../README.md#where-to-keep-projects)
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

## Sign-in, updates, and optional configuration

- Run `gh auth login`, `az login`, and Copilot's interactive flow as the
  selected Linux user when needed. Core provisioning does not sign in or copy
  credentials from Windows.
- Choose and run dotfiles separately. Review the repository, branch, installer,
  identity settings, backups, and local overrides. Run the installer as your
  Linux user, not root.
- If an existing `~/dotfiles` checkout has uncommitted or divergent changes,
  resolve them manually. Do not discard them to install an update.
- To undo optional dotfiles links, first verify each target points into the
  Launchpad `dotfiles` directory. Remove only those links and restore the
  intended numbered `.bak` file. For example, in Linux:

  ```bash
  rm ~/.bashrc
  mv ~/.bashrc.bak ~/.bashrc
  ```

  In PowerShell, use `Remove-Item $PROFILE` and move the chosen
  `"$PROFILE.bak"` back to `$PROFILE`. The installer may also have backed up
  `~/.gitconfig`; inspect it and the XDG `dotfiles/gitconfig` backups before
  restoring Git configuration. Do not delete the checkout while active links
  still point into it.
- For DNF failures or timer settings, use the commands in the
  [tooling and updates guide](../README.md#tooling-and-updates). Rerun Launchpad
  to update standalone Bicep and Copilot CLI; DNF does not update them.

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
