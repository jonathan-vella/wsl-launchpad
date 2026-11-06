# Optional Microsoft CFS device setup

This is an **opt-in host setting for Microsoft maintainers using APEX devcontainers**.
Skip it if you do not need Microsoft's CFS package feeds. The core Launchpad
bootstrap never runs it, and other users keep their existing package sources.

[`configure-cfs.ps1`](../configure-cfs.ps1) saves the APEX feed variables in
your **Windows user environment** and forwards them into future WSL sessions.
This avoids running APEX's host launcher every time you open VS Code on this device.
The existing APEX launchers remain available for other users and one-off sessions.

## What changes

The script replaces these Windows user variables:

| Variable | Value |
|---|---|
| `APEX_NPM_REGISTRY_HOST_PATH` | `packagefeedproxy.microsoft.io/npm/` |
| `APEX_PIP_INDEX_HOST_PATH` | `packagefeedproxy.microsoft.io/pypi/simple/` |
| `APEX_POWERSHELL_REPOSITORY_URL` | `https://packagefeedproxy.microsoft.io/powershell/v2` |

It adds these names to user-level `WSLENV` for forwarding in both directions,
without translating their values as filesystem paths. Existing forwarding
flags for these three names are replaced; unrelated entries are retained.
If user-level `WSLENV` is absent, existing machine-level entries are retained
in the new user value. Machine-level settings are never changed.

The settings affect future processes for your Windows account, not only one
project. Only applications consuming these APEX variables use them: this does
not globally reconfigure npm, pip, or Launchpad's native Linux provisioning.
Do not use the corporate dev-box proxy as a replacement for an authenticated,
approved CI package feed.

No administrator access, installation, credential changes, TLS overrides,
application restarts, or WSL provisioning are performed. Corporate network/VPN
access remains necessary when required by your organization. Rerunning is safe.

## Run from Windows

Use **PowerShell 7.4 or newer** in an external Windows terminal. Keep the
Launchpad checkout on a local Windows disk, not inside a devcontainer or at a
WSL/network path. Run from its folder:

```powershell
pwsh -NoProfile -File .\configure-cfs.ps1 -WhatIf
```

The preview changes nothing. After reviewing its scope, apply once:

```powershell
pwsh -NoProfile -File .\configure-cfs.ps1
```

If organizational execution policy blocks the script, use your approved
signing/execution method. Do not change or bypass the policy. Under
`RemoteSigned`, unsigned scripts on WSL/network paths can require a signature;
keep your host-side Launchpad checkout on the Windows disk as recommended.

## Run from WSL

Use the **same Windows-hosted checkout**, not the Linux checkout used for
dotfiles. In these examples it is at `$HOME\src\wsl-launchpad` on Windows.
If your Windows checkout is elsewhere, replace that path in both commands.

From an external WSL terminal, preview:

```bash
pwsh.exe -NoProfile -Command '& "$HOME\src\wsl-launchpad\configure-cfs.ps1" -WhatIf'
```

Apply once:

```bash
pwsh.exe -NoProfile -Command '& "$HOME\src\wsl-launchpad\configure-cfs.ps1"'
```

The single quotes keep Bash from expanding `$HOME`; Windows PowerShell resolves
it to your Windows home directory. These commands invoke the script normally
and do not override execution policy. If `pwsh.exe` is not on WSL's `PATH`,
use the Windows instructions instead.

## Activate and verify

1. Save your work and close VS Code.
1. **Sign out of Windows and sign back in.** Existing applications still have
   their old environment until restarted from the refreshed Windows session.
1. For WSL, save any remaining work and run this in a new Windows terminal:

   ```powershell
   wsl.exe --shutdown
   ```

   This stops **all WSL distributions** without deleting their files.
   Reopen your WSL terminal afterwards.

1. Open the project normally from Windows or use `code .` in WSL.
1. Run **Dev Containers: Rebuild Container** once for existing APEX containers.
   Reopening or restarting an old container does not update its build-time feeds.

In a fresh Windows PowerShell terminal:

```powershell
$env:APEX_NPM_REGISTRY_HOST_PATH
$env:APEX_PIP_INDEX_HOST_PATH
$env:APEX_POWERSHELL_REPOSITORY_URL
$env:WSLENV
```

In a fresh WSL terminal:

```bash
printenv APEX_NPM_REGISTRY_HOST_PATH APEX_PIP_INDEX_HOST_PATH APEX_POWERSHELL_REPOSITORY_URL WSLENV
```

Check the feed values against the table and confirm `WSLENV` contains all three
names. After rebuilding, APEX startup should label npm, pip, and uv sources as
`Microsoft CFS`. Future VS Code sessions can use your normal launch method.

Correct settings do not prove feed reachability or successful package installs.
If downloads still fail, check approved network/VPN access rather than disabling
TLS verification or switching to public feeds to evade restrictions.

## Remove the opt-in

Open **Edit environment variables for your account** in Windows. Delete the
three APEX variables, or restore their previous custom values. Remove only
their entries from user-level `WSLENV`, retaining unrelated entries.
Sign out and back in, restart WSL, and rebuild affected containers.

If setup reports a persistence or verification failure, it exits nonzero and
later settings are not written. Some earlier settings may already have been
saved: inspect the four user variables before rerunning or removing the opt-in.
