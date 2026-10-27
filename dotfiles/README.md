# Optional dotfiles

The starter configuration is **opt-in**. The core bootstrap never applies it.
It contains hooks for your local configuration, but sets no Git identity or
VS Code settings.

For WSL profiles, use a
[Linux-filesystem checkout](../README.md#where-to-keep-projects) of Launchpad.
Keep that checkout while profile links point into it. Run this from WSL inside
that checkout:

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
