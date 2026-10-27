#!/usr/bin/env pwsh
# Create symlinks for dotfiles with PowerShell 7+.
#Requires -Version 7

[CmdletBinding()]
param(
    [string]$HomePath = $HOME,
    [string]$PowerShellProfilePath = $PROFILE,
    [string]$XdgConfigHome
)

$ErrorActionPreference = 'Stop'
$DotfilesDir = $PSScriptRoot

if (-not $XdgConfigHome) {
    $XdgConfigHome = if ($env:XDG_CONFIG_HOME) {
        $env:XDG_CONFIG_HOME
    } else {
        Join-Path $HomePath '.config'
    }
}

function Get-PathEntry {
    param([Parameter(Mandatory)][string]$Path)

    Get-Item -LiteralPath $Path -Force -ErrorAction SilentlyContinue
}

function Get-BackupPath {
    param([Parameter(Mandatory)][string]$Path)

    $candidate = "$Path.bak"
    $index = 1
    while (Get-PathEntry -Path $candidate) {
        $candidate = "$Path.bak.$index"
        $index++
    }
    $candidate
}

function Test-SymlinkSupport {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    if (-not (Get-PathEntry -Path $Source)) {
        throw "Source file does not exist: $Source"
    }

    $directory = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $testPath = Join-Path $directory ".dotfiles-link-test-$([guid]::NewGuid())"
    try {
        New-Item -ItemType SymbolicLink -Path $testPath -Target $Source -ErrorAction Stop | Out-Null
    } catch {
        throw "Cannot create symbolic links in '$directory'. Enable Developer Mode, run an elevated shell, or verify filesystem permissions. $($_.Exception.Message)"
    } finally {
        if (Get-PathEntry -Path $testPath) {
            Remove-Item -LiteralPath $testPath -Force
        }
    }
}

function Test-FileReplacementSupport {
    param([Parameter(Mandatory)][string]$Destination)

    $directory = Split-Path -Parent $Destination
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
    }

    $testPath = Join-Path $directory ".dotfiles-file-test-$([guid]::NewGuid())"
    try {
        New-Item -ItemType File -Path $testPath -ErrorAction Stop | Out-Null
    } catch {
        throw "Cannot create files in '$directory'. Verify filesystem permissions. $($_.Exception.Message)"
    } finally {
        if (Get-PathEntry -Path $testPath) {
            Remove-Item -LiteralPath $testPath -Force
        }
    }
}

function Install-DotfileLink {
    param(
        [Parameter(Mandatory)][string]$Source,
        [Parameter(Mandatory)][string]$Destination
    )

    $sourcePath = [IO.Path]::GetFullPath($Source)
    $existing = Get-PathEntry -Path $Destination
    if ($existing -and $existing.LinkType -eq 'SymbolicLink') {
        $existingTarget = [string]$existing.Target
        if ([IO.Path]::GetFullPath($existingTarget) -eq $sourcePath) {
            Write-Host "  unchanged: $Destination"
            return
        }
    }

    $directory = Split-Path -Parent $Destination
    $temporaryLink = Join-Path $directory ".dotfiles-link-$([guid]::NewGuid())"
    $backup = $null

    New-Item -ItemType SymbolicLink -Path $temporaryLink -Target $sourcePath | Out-Null
    try {
        if ($existing) {
            $backup = Get-BackupPath -Path $Destination
            Write-Host "  backup: $Destination -> $backup"
            Move-Item -LiteralPath $Destination -Destination $backup
        }

        Move-Item -LiteralPath $temporaryLink -Destination $Destination
        Write-Host "  linked: $Destination"
    } catch {
        if (Get-PathEntry -Path $temporaryLink) {
            Remove-Item -LiteralPath $temporaryLink -Force
        }
        if ($backup -and -not (Get-PathEntry -Path $Destination)) {
            Move-Item -LiteralPath $backup -Destination $Destination
        }
        throw
    }
}

function Add-GitConfigInclude {
    param(
        [Parameter(Mandatory)][string]$DotfilesConfig,
        [Parameter(Mandatory)][string]$UserConfig
    )

    $gitPath = $DotfilesConfig.Replace('\', '/')
    $existingEntry = Get-PathEntry -Path $UserConfig
    if ($existingEntry) {
        $configuredKeys = @(git -C (Split-Path -Parent $UserConfig) config --file $UserConfig --name-only --get-regexp '.*' 2>$null)
        $configuredIncludes = @(git -C (Split-Path -Parent $UserConfig) config --file $UserConfig --get-all include.path 2>$null)
        $matchingIncludes = @($configuredIncludes | Where-Object { $_ -eq $gitPath })
        if (
            $configuredKeys.Count -gt 0 -and
            $configuredKeys[0] -eq 'include.path' -and
            $configuredIncludes.Count -gt 0 -and
            $configuredIncludes[0] -eq $gitPath -and
            $matchingIncludes.Count -eq 1
        ) {
            Write-Host "  unchanged: $UserConfig"
            return
        }
    }

    $directory = Split-Path -Parent $UserConfig
    $temporaryConfig = Join-Path $directory ".dotfiles-gitconfig-$([guid]::NewGuid())"
    $includeFragment = Join-Path $directory ".dotfiles-gitinclude-$([guid]::NewGuid())"
    $sanitizedConfig = Join-Path $directory ".dotfiles-gitbody-$([guid]::NewGuid())"
    $backup = $null
    $existingContent = if ($existingEntry) {
        Copy-Item -LiteralPath $UserConfig -Destination $sanitizedConfig
        git -C $directory config --file $sanitizedConfig --fixed-value --unset-all include.path $gitPath 2>$null
        $content = [IO.File]::ReadAllText($sanitizedConfig)
        Remove-Item -LiteralPath $sanitizedConfig -Force
        $content
    } else {
        ''
    }
    git -C $directory config --file $includeFragment include.path $gitPath
    if ($LASTEXITCODE -ne 0) {
        throw 'Unable to serialize the Git include path.'
    }
    $includeContent = [IO.File]::ReadAllText($includeFragment)
    Remove-Item -LiteralPath $includeFragment -Force

    if ($existingEntry) {
        Copy-Item -LiteralPath $UserConfig -Destination $temporaryConfig
    }
    [IO.File]::WriteAllText(
        $temporaryConfig,
        "$includeContent`n$existingContent",
        [Text.UTF8Encoding]::new($false)
    )
    if (-not $IsWindows) {
        [IO.File]::SetUnixFileMode(
            $temporaryConfig,
            [IO.UnixFileMode]::UserRead -bor [IO.UnixFileMode]::UserWrite
        )
    }

    git -C $directory config --file $temporaryConfig --list | Out-Null
    if ($LASTEXITCODE -ne 0) {
        Remove-Item -LiteralPath $temporaryConfig -Force
        throw 'Generated Git configuration is invalid.'
    }

    try {
        if ($existingEntry) {
            $backup = Get-BackupPath -Path $UserConfig
            Write-Host "  backup: $UserConfig -> $backup"
            Move-Item -LiteralPath $UserConfig -Destination $backup
        }

        Move-Item -LiteralPath $temporaryConfig -Destination $UserConfig
        Write-Host "  included: $DotfilesConfig"
    } catch {
        if (Get-PathEntry -Path $temporaryConfig) {
            Remove-Item -LiteralPath $temporaryConfig -Force
        }
        if ($backup -and -not (Get-PathEntry -Path $UserConfig)) {
            Move-Item -LiteralPath $backup -Destination $UserConfig
        }
        throw
    }
}

$gitConfigPath = Join-Path $XdgConfigHome 'dotfiles\gitconfig'
$userGitConfigPath = Join-Path $HomePath '.gitconfig'
$links = @(
    @{
        Source = Join-Path $DotfilesDir 'git\.gitconfig'
        Destination = $gitConfigPath
        Group = 'git'
    },
    @{
        Source = Join-Path $DotfilesDir 'powershell\Microsoft.PowerShell_profile.ps1'
        Destination = $PowerShellProfilePath
        Group = 'PowerShell profile'
    }
)

foreach ($link in $links) {
    Test-SymlinkSupport -Source $link.Source -Destination $link.Destination
}
Get-Command git -ErrorAction Stop | Out-Null
Test-FileReplacementSupport -Destination $userGitConfigPath

foreach ($group in $links.Group | Select-Object -Unique) {
    Write-Host "==> Linking $group"
    foreach ($link in $links | Where-Object Group -EQ $group) {
        Install-DotfileLink -Source $link.Source -Destination $link.Destination
    }
    if ($group -eq 'git') {
        Add-GitConfigInclude -DotfilesConfig $gitConfigPath -UserConfig $userGitConfigPath
    }
}

Write-Host ''
Write-Host 'Done. Restart PowerShell or run: . $PROFILE'
