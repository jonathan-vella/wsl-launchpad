#Requires -Version 7.4
<#
.SYNOPSIS
    Saves optional Microsoft CFS feed settings for the current Windows user.
.DESCRIPTION
    Configures future Windows and WSL sessions without administrator access.
    Preserves unrelated WSLENV entries. Does not install packages, change
    repository files, restart applications, or disable TLS verification.
.EXAMPLE
    pwsh -NoProfile -File .\configure-cfs.ps1 -WhatIf
.EXAMPLE
    pwsh -NoProfile -File .\configure-cfs.ps1
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param()

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'

function Get-PersistentEnvironmentVariable {
    param([string]$Name, [ValidateSet('User', 'Machine')][string]$Scope)
    [Environment]::GetEnvironmentVariable($Name, $Scope)
}

function Set-PersistentEnvironmentVariable {
    param([string]$Name, [string]$Value)
    [Environment]::SetEnvironmentVariable($Name, $Value, 'User')
}

function Invoke-CfsSetup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param()

    if (-not $IsWindows) {
        throw 'Run with PowerShell 7.4 or newer on Windows. From WSL, use pwsh.exe and the Windows-hosted script.'
    }

    $settings = [ordered]@{
        APEX_NPM_REGISTRY_HOST_PATH = 'packagefeedproxy.microsoft.io/npm/'
        APEX_PIP_INDEX_HOST_PATH = 'packagefeedproxy.microsoft.io/pypi/simple/'
        APEX_POWERSHELL_REPOSITORY_URL = 'https://packagefeedproxy.microsoft.io/powershell/v2'
    }
    $feedNames = @($settings.Keys)
    $existingWslEnv = Get-PersistentEnvironmentVariable -Name 'WSLENV' -Scope User
    if ($null -eq $existingWslEnv) {
        $existingWslEnv = Get-PersistentEnvironmentVariable -Name 'WSLENV' -Scope Machine
    }

    # A user-level WSLENV shadows the machine value; retain the effective entries.
    $entries = @($existingWslEnv -split ':' | Where-Object {
        $_ -and $feedNames -notcontains ($_ -split '/', 2)[0]
    })
    # Unflagged entries forward in both directions without translating feed paths.
    $settings['WSLENV'] = (@($entries) + $feedNames) -join ':'

    if (-not $PSCmdlet.ShouldProcess('Current Windows user environment', 'Persist CFS feeds and WSL forwarding')) {
        Write-Output 'No settings were changed.'
        return
    }

    foreach ($setting in $settings.GetEnumerator()) {
        Set-PersistentEnvironmentVariable -Name $setting.Key -Value $setting.Value
        $saved = Get-PersistentEnvironmentVariable -Name $setting.Key -Scope User
        if ($saved -cne $setting.Value) {
            throw "Verification failed for $($setting.Key)."
        }
        Write-Output "Saved and verified $($setting.Key)."
    }

    Write-Output 'Setup complete. Existing processes still have their old environment.'
    Write-Output 'Save your work, sign out of Windows and back in, then restart WSL.'
    Write-Output 'Rebuild existing APEX devcontainers once; future sessions can open VS Code normally.'
}

if ($MyInvocation.InvocationName -ne '.') {
    try {
        Invoke-CfsSetup @PSBoundParameters
    } catch {
        Write-Error "CFS device setup failed; some settings may already have been saved. $($_.Exception.Message)" -ErrorAction Continue
        exit 1
    }
}
