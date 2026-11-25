# Optional Microsoft CFS device setup

This is an **opt-in device setting for Microsoft maintainers**.
Skip it if you do not need Microsoft's CFS package feeds. The core Launchpad
bootstrap never runs it, and other users keep their existing package sources.

[`configure-cfs.ps1`](../configure-cfs.ps1) saves the APEX feed variables in
your **Windows user environment** and forwards them into future WSL sessions.
This avoids running APEX's host launcher every time you open VS Code on this device.
The existing APEX launchers remain available for other users and one-off sessions.
APEX reads these variables from the Windows VS Code process environment when
building a devcontainer. Setting them only in an integrated terminal is too
late for that build; a running VS Code process or existing container can retain
the old feed defaults. This helper does not install the APEX devcontainer stack.
Add `-ConfigureClients` for native Windows npm, PyPI (pip/uv), NuGet,
PowerShell Gallery, and Cargo defaults. Add `-WslDistribution <name>` to
configure native clients for the default user in one WSL distribution as well.
Without these options, the existing APEX-only behavior is unchanged.

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

Without `-ConfigureClients`, only applications consuming these APEX variables
use them; npm and pip are not globally reconfigured.
The settings affect future processes for your Windows account, not only one
project. Launchpad's core bootstrap and Linux provisioning remain unchanged.
Do not use the corporate dev-box proxy as a replacement for an authenticated,
approved CI package feed.

No administrator access, installation, credential changes, TLS overrides,
application restarts, or WSL provisioning are performed. Corporate network/VPN
access remains necessary when required by your organization. Rerunning is safe.

## Native client configuration

With `-ConfigureClients`, the script also makes these changes:

| Client | User setting |
|---|---|
| npm | `NPM_CONFIG_REGISTRY=https://packagefeedproxy.microsoft.io/npm/` |
| pip | `PIP_INDEX_URL=https://packagefeedproxy.microsoft.io/pypi/simple/` |
| uv | `UV_DEFAULT_INDEX=https://packagefeedproxy.microsoft.io/pypi/simple/` |
| NuGet | Public nuget.org sources in the user config point to `https://packagefeedproxy.microsoft.io/nuget/v3/index.json`; adds `CFS` if none exists |
| Cargo | User source replacement redirects crates.io to `sparse+https://packagefeedproxy.microsoft.io/cargo/index/` |
| PowerShellGet | PSGallery uses `https://packagefeedproxy.microsoft.io/powershell/v2` |
| PSResourceGet | PSGallery uses `https://packagefeedproxy.microsoft.io/powershell/v3/index.json` |

The three native environment variables are persisted alongside the APEX
variables and forwarded through `WSLENV`. Native clients need fresh processes
to receive them. Existing extra indexes, scoped registries, private feeds,
disabled sources, source mappings, and project/command-line overrides are
not removed. **This configures defaults, not comprehensive feed enforcement.**
If a new NuGet `CFS` source is added and source mappings are in use, explicitly
map the intended packages to it; the script does not broaden existing mappings.

Windows NuGet configuration is `%APPDATA%\NuGet\NuGet.Config`. Cargo uses
`%CARGO_HOME%` from the invoking process, or `$HOME\.cargo`, preferring the legacy
`config` file over `config.toml` when it exists. Unrelated XML/TOML settings
are preserved. Existing Cargo source declarations or multiline strings require
a manual merge instead of a potentially unsafe TOML rewrite. File conflicts
are checked before settings are written. Each existing file is backed up to
`<filename>.cfs.bak` before its first change; an existing backup is never replaced.
New files have no backup.

Installed PowerShellGet and PSResourceGet clients in the running PowerShell
are configured without elevating repository trust. If PSGallery is absent,
an existing repository using the same CFS endpoint is reused, regardless of
its name; otherwise an untrusted `CFS` repository is registered. A conflicting private `CFS`
repository is not overwritten. Missing clients are reported, not installed.
PowerShellGet also needs an already-installed NuGet provider; if it is missing,
that client is skipped with a warning instead of bootstrapping a provider.
Other PowerShell installations (such as Windows PowerShell 5.1) may have separate
repository settings and are not configured by a PowerShell 7 run.

For WSL, specify a distribution explicitly; the script never configures all
distributions. It discovers that distribution's default user's home and
`CARGO_HOME` using `wsl.exe`, then edits the files through Windows-accessible
paths. It uses `.nuget\NuGet\NuGet.Config` and also updates
`.config\NuGet\NuGet.Config` if that alternative file exists. NuGet/Cargo do
not have to be installed yet. If Linux `pwsh` is installed, its installed
PowerShell repository clients are configured too; otherwise a warning explains
that PowerShell Gallery there remains unconfigured. Shell profile-only overrides,
other Linux users, and other distributions are outside this run's scope.

**Devcontainers are separate clients.** Existing APEX npm/Python/PowerShell
variables are retained, but this repository has no APEX NuGet/Cargo consumer.
Those clients inside a container still need the corresponding configuration
copied or mounted by the container definition. No unsupported APEX variables
are invented, and host settings alone do not configure every container.

Only stable `packagefeedproxy.microsoft.io` URLs are saved. The article's
`ms-feed-*` Azure Artifacts links are for browsing, not client configuration.
These proxy defaults are for interactive corporate laptops and dev boxes only;
use an approved, authenticated Azure Artifacts feed for CI and automated builds.

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

For native Windows clients as well:

```powershell
pwsh -NoProfile -File .\configure-cfs.ps1 -ConfigureClients -WhatIf
pwsh -NoProfile -File .\configure-cfs.ps1 -ConfigureClients
```

For Windows and one selected WSL distribution, replace `Ubuntu` with its exact
name from `wsl.exe --list --quiet`:

```powershell
pwsh -NoProfile -File .\configure-cfs.ps1 -ConfigureClients -WslDistribution Ubuntu -WhatIf
pwsh -NoProfile -File .\configure-cfs.ps1 -ConfigureClients -WslDistribution Ubuntu
```

The script does not need administrator access. The WSL option starts the
selected distribution to discover paths, except under `-WhatIf`, which performs
no WSL calls or configuration writes.

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
The same native-client options can be appended inside the quoted PowerShell
command. `-WslDistribution` requires `-ConfigureClients`.

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

With native client setup, also check `NPM_CONFIG_REGISTRY`, `PIP_INDEX_URL`,
and `UV_DEFAULT_INDEX` in fresh Windows/WSL processes. Inspect the NuGet user
config and Cargo managed block at the paths above. For installed PowerShell
clients, run `Get-PSRepository` and/or `Get-PSResourceRepository` in each configured
PowerShell installation and confirm the stable proxy URLs.

Correct settings do not prove feed reachability or successful package installs.
If downloads still fail, check approved network/VPN access rather than disabling
TLS verification or switching to public feeds to evade restrictions.

## Remove the opt-in

Open **Edit environment variables for your account** in Windows. Delete the
three APEX variables, or restore their previous custom values. Remove only
their entries from user-level `WSLENV`, retaining unrelated entries.
Sign out and back in, restart WSL, and rebuild affected containers.

If native setup was used, remove or restore the three native environment
variables and only their `WSLENV` entries too. Restore each edited NuGet/Cargo
file from its `.cfs.bak` backup, or manually undo only the CFS changes if the
file has since changed. For a newly created Cargo file, remove the managed
CFS block; for a newly created NuGet file, remove the added `CFS` source.
In each affected PowerShell installation, restore PSGallery's previous URL
with `Set-PSRepository` / `Set-PSResourceRepository`, or unregister the `CFS`
repository if the script created it. Repository settings are not file-backed
up by this helper; record custom PSGallery URLs before opting in.

If setup reports a persistence or verification failure, it exits nonzero and
later settings are not written. Some earlier settings may already have been
saved: inspect the user variables, client files/backups, and repository settings
before rerunning or removing the opt-in.

Reference: [Finding Packages in the Default Proxy](https://eng.ms/docs/coreai/devdiv/one-engineering-system-1es/1es-docs/secure-supply-chain/central-feed-services-cfs/finding-packages-in-default-proxy.html).
The PowerShell and Cargo routes being available does not establish their
enforcement/quarantine rollout. A held version intentionally appears absent
to package clients; a successful configuration check is not a package restore.
