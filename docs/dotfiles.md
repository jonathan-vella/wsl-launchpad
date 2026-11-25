# Optional dotfiles

The starter configuration is **opt-in**. The core bootstrap never applies it.
It contains hooks for your local configuration, but sets no Git identity or
VS Code settings.

## Choose a dotfiles source

Skip this guide if you only want the installed tools. Choose either Launchpad's
neutral starter or your own repository. Do not apply both unless you intend
to replace the first configuration.

For a private GitHub repository, authenticate inside Linux before cloning:

```bash
gh auth login --hostname github.com
gh auth setup-git
```

Windows authentication is not automatically available inside Linux. Never
copy credential caches or embed tokens in URLs.

## Use the included starter

For WSL profiles, use a
[Linux-filesystem checkout](performance.md#put-the-working-files-with-the-tools) of Launchpad.
Keep that checkout while profile links point into it. If you need a Linux
checkout, run inside WSL as your non-root user:

```bash
mkdir -p ~/src
git clone https://github.com/jonathan-vella/wsl-launchpad.git ~/src/wsl-launchpad
cd ~/src/wsl-launchpad
cat dotfiles/install.sh
```

If that checkout already exists, use it instead of cloning over it. Review
the installer before applying it. From the repository root inside WSL:

```bash
bash ./dotfiles/install.sh
```

This links the Git configuration under `${XDG_CONFIG_HOME:-~/.config}/dotfiles`
and the `.profile`, `.bashrc`, `.zprofile`, and `.zshrc` hooks. The installer
preserves existing destinations as `.bak`, `.bak.1`, and so on. It checks that
it can create links before changing files, preserves existing `.gitconfig`
content, and can be rerun. Read the script first. It changes the selected
user's shell startup files and global Git configuration include.

To apply the PowerShell profile and Git include in the environment where
PowerShell is running:

```powershell
pwsh -NoProfile -File .\dotfiles\install.ps1
```

On Windows, symbolic links may require Developer Mode or an elevated terminal.
The installer checks link support before moving files. The PowerShell
installer changes the Windows PowerShell profile and Windows home Git config.
It does not install WSL profiles. The Bash installer changes Linux profiles
only.

## Use your own repository

Review its instructions, installer, tracked identity, and backup behavior.
Inside Linux, replace the example URL with your repository:

```bash
git clone https://github.com/YOUR-USERNAME/dotfiles.git ~/dotfiles
cd ~/dotfiles
cat README.md
```

If its instructions specify `install.sh`, review it with `cat install.sh`
before running `bash ./install.sh`. Other repositories may use different
installers. Do not clone over an existing checkout or discard local changes.
Linux-side VS Code settings do not configure the Windows client.

## Git identity

The tracked Git configuration contains no identity. Set your own in each
environment where you commit:

```bash
git config --global user.name "Your Name"
git config --global user.email "you@example.com"
git config --show-origin --get user.name
git config --show-origin --get user.email
```

Alternatively, put machine-specific values in the untracked
`~/.gitconfig.local` file included by the starter config. Existing settings in
`~/.gitconfig` remain after the starter include and take precedence. Check the
effective identity with `git config --show-origin --get user.email` before
committing.

## VS Code and authentication boundaries

- Linux settings such as `~/.config/Code/User/settings.json` are not the
  Windows VS Code client's user settings.
- Windows VS Code settings, WSL Remote settings, and workspace settings are
  separate scopes. This starter does not configure any of them; configure each
  deliberately.
- Sign in to GitHub, Azure, Copilot, VS Code, and extensions in their relevant
  application or account. Launchpad does not copy Windows tokens, credential
  caches, or browser sessions into WSL.

You can use another dotfiles repository and branch. Review it and authenticate
to it yourself. Launchpad does not clone a fixed personal repository or run
remote install commands.

## Local overrides

When present, the linked shell files load these optional, untracked files:

| File | Loaded by |
|---|---|
| `~/.profile.local` | Login environment |
| `~/.bashrc.local` | Interactive Bash |
| `~/.zprofile.local` | Zsh login |
| `~/.zshrc.local` | Interactive Zsh |
| `~/.gitconfig.local` | Git |
| `profile.local.ps1` beside `$PROFILE` | PowerShell |

Keep personal preferences and machine-specific values in these files, not in
the tracked starter configuration.

## Undo the starter

Before removing any link, verify that its target points into Launchpad's
`dotfiles` directory. Remove only that link and restore the intended numbered
backup. For example, inside Linux, after checking `~/.bashrc`:

```bash
rm ~/.bashrc
mv ~/.bashrc.bak ~/.bashrc
```

In PowerShell, inspect `$PROFILE`, remove only its verified starter link with
`Remove-Item $PROFILE`, and move the chosen `"$PROFILE.bak"` back to `$PROFILE`.
The installer may also have backed up `~/.gitconfig`; inspect it and the XDG
`dotfiles/gitconfig` backups before restoring Git configuration. Never delete
the checkout while active profile or Git links still point into it.
