[CmdletBinding()]
param()

$ErrorActionPreference = 'Stop'
$Repo = Split-Path -Parent $PSScriptRoot
$Root = Join-Path ([IO.Path]::GetTempPath()) "dotfiles test $([guid]::NewGuid())"
$HomePath = Join-Path $Root 'home with spaces'
$XdgConfigHome = Join-Path $Root 'config #semi; with spaces'
$ProfilePath = Join-Path $HomePath 'PowerShell Profiles\Microsoft.PowerShell_profile.ps1'
$Installer = Join-Path $Repo 'install.ps1'
$failures = 0

function Assert-True {
    param(
        [Parameter(Mandatory)][bool]$Condition,
        [Parameter(Mandatory)][string]$Description
    )

    if ($Condition) {
        Write-Output "PASS: $Description"
    } else {
        Write-Output "FAIL: $Description"
        $script:failures++
    }
}

function Assert-Link {
    param(
        [Parameter(Mandatory)][string]$Path,
        [Parameter(Mandatory)][string]$Target
    )

    $item = Get-Item -LiteralPath $Path -Force
    Assert-True ($item.LinkType -eq 'SymbolicLink') "$Path is linked"
    Assert-True ([IO.Path]::GetFullPath([string]$item.Target) -eq [IO.Path]::GetFullPath($Target)) "$Path has the expected target"
}

try {
    New-Item -ItemType Directory -Path (Join-Path $XdgConfigHome 'dotfiles') -Force | Out-Null
    New-Item -ItemType Directory -Path $HomePath -Force | Out-Null
    $trackedGitConfig = Join-Path $Repo 'git\.gitconfig'
    $trackedIdentity = git config --file $trackedGitConfig --get user.name 2>$null
    Assert-True ([string]::IsNullOrEmpty($trackedIdentity)) 'tracked Git config does not set an identity'
    $installerSource = Get-Content -LiteralPath $Installer -Raw
    Assert-True ($installerSource -notmatch 'VsCode|DOTFILES_VSCODE|settings\.json') 'PowerShell installer does not configure VS Code'

    Set-Content -LiteralPath (Join-Path $HomePath '.gitconfig') -Value @(
        '[user]'
        "`tname = Existing User"
        "`temail = existing@example.com"
        '[core]'
        "`teditor = code"
    )
    Set-Content -LiteralPath (Join-Path $XdgConfigHome 'dotfiles\gitconfig.bak') -Value 'old backup'
    Set-Content -LiteralPath (Join-Path $XdgConfigHome 'dotfiles\gitconfig') -Value 'original tracked config'

    $arguments = @{
        HomePath = $HomePath
        XdgConfigHome = $XdgConfigHome
        PowerShellProfilePath = $ProfilePath
    }

    try {
        & $Installer @arguments | Out-Null
    } catch {
        if ($_.Exception.Message -notlike 'Cannot create symbolic links*') {
            throw
        }

        Assert-True (Test-Path -LiteralPath (Join-Path $XdgConfigHome 'dotfiles\gitconfig')) 'preflight failure preserves destination'
        Assert-True ((Get-Content -LiteralPath (Join-Path $XdgConfigHome 'dotfiles\gitconfig') -Raw).Trim() -eq 'original tracked config') 'preflight failure preserves destination content'
        Assert-True ((Get-Content -LiteralPath (Join-Path $XdgConfigHome 'dotfiles\gitconfig.bak') -Raw).Trim() -eq 'old backup') 'preflight failure preserves existing backup'
        $preservedEditor = git config --file (Join-Path $HomePath '.gitconfig') core.editor
        Assert-True ($preservedEditor -eq 'code') 'preflight failure preserves user .gitconfig'
        Assert-True (-not (Test-Path -LiteralPath (Join-Path $HomePath '.gitconfig.bak'))) 'preflight failure creates no user config backup'
        Write-Output 'SKIP: symbolic-link success tests require platform link permission'
        exit $failures
    }

    Assert-Link (Join-Path $XdgConfigHome 'dotfiles\gitconfig') (Join-Path $Repo 'git\.gitconfig')
    Assert-Link $ProfilePath (Join-Path $Repo 'powershell\Microsoft.PowerShell_profile.ps1')
    Assert-True ((Get-Content -LiteralPath (Join-Path $XdgConfigHome 'dotfiles\gitconfig.bak') -Raw).Trim() -eq 'old backup') 'existing backup is preserved'
    Assert-True ((Get-Content -LiteralPath (Join-Path $XdgConfigHome 'dotfiles\gitconfig.bak.1') -Raw).Trim() -eq 'original tracked config') 'new backup uses a unique name'
    $userConfig = Get-Content -LiteralPath (Join-Path $HomePath '.gitconfig') -Raw
    $userEditor = git config --file (Join-Path $HomePath '.gitconfig') core.editor
    $userEmail = git config --file (Join-Path $HomePath '.gitconfig') user.email
    Assert-True ($userEditor -eq 'code') 'user .gitconfig content keeps final precedence'
    Assert-True ($userEmail -eq 'existing@example.com') 'existing Git identity keeps final precedence'
    Assert-True ($userConfig.IndexOf('[include]') -lt $userConfig.IndexOf('[core]')) 'dotfiles include precedes user settings'
    $backupEditor = git config --file (Join-Path $HomePath '.gitconfig.bak') core.editor
    Assert-True ($backupEditor -eq 'code') 'original user .gitconfig is backed up'

    & $Installer @arguments | Out-Null
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $XdgConfigHome 'dotfiles\gitconfig.bak.2'))) 'repeat install creates no extra backup'
    Assert-True (-not (Test-Path -LiteralPath (Join-Path $HomePath '.gitconfig.bak.1'))) 'repeat install creates no extra user config backup'

    $gitPath = (Join-Path $XdgConfigHome 'dotfiles\gitconfig').Replace('\', '/')
    Set-Content -LiteralPath (Join-Path $HomePath '.gitconfig') -Value ''
    git config --file (Join-Path $HomePath '.gitconfig') core.editor code
    git config --file (Join-Path $HomePath '.gitconfig') --add include.path $gitPath
    & $Installer @arguments | Out-Null
    $keys = @(git config --file (Join-Path $HomePath '.gitconfig') --name-only --get-regexp '.*')
    $includes = @(git config --file (Join-Path $HomePath '.gitconfig') --get-all include.path)
    Assert-True ($keys[0] -eq 'include.path') 'existing include is moved before user settings'
    Assert-True (@($includes | Where-Object { $_ -eq $gitPath }).Count -eq 1) 'repositioned include remains unique'

    Write-Output "Architecture: $([Runtime.InteropServices.RuntimeInformation]::OSArchitecture)"
    Write-Output "Failures: $failures"
    exit $failures
} finally {
    if (Test-Path -LiteralPath $Root) {
        Remove-Item -LiteralPath $Root -Recurse -Force
    }
}
