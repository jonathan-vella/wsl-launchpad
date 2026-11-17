#Requires -Version 7.4
<#
.SYNOPSIS
    Saves optional Microsoft CFS feed settings for the current Windows user.
.DESCRIPTION
    Configures future Windows and WSL sessions without administrator access.
    Preserves unrelated WSLENV entries. Does not install packages, change
    repository files, restart applications, or disable TLS verification.
    With -ConfigureClients, also changes native Windows package-client defaults.
    Add -WslDistribution to configure NuGet, Cargo, and installed PowerShell
    clients for the default user in that one distribution. Not for CI workloads.
.EXAMPLE
    pwsh -NoProfile -File .\configure-cfs.ps1 -WhatIf
.EXAMPLE
    pwsh -NoProfile -File .\configure-cfs.ps1
.EXAMPLE
    pwsh -NoProfile -File .\configure-cfs.ps1 -ConfigureClients -WslDistribution Ubuntu
#>
[CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
param(
    [switch]$ConfigureClients,
    [string]$WslDistribution
)

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

function Get-CfsNuGetContent {
    param([string]$Content)

    $document = [Xml.XmlDocument]::new()
    $document.PreserveWhitespace = $true
    $document.XmlResolver = $null
    if ($Content -match '<!DOCTYPE') { throw 'NuGet configuration must not contain a DTD.' }
    if ([string]::IsNullOrWhiteSpace($Content)) { $Content = '<configuration />' }
    $document.LoadXml($Content)
    if ($document.FirstChild -is [Xml.XmlDeclaration]) {
        $document.FirstChild.Encoding = 'utf-8'
    }
    if ($document.DocumentElement.Name -cne 'configuration') {
        throw 'Expected a NuGet configuration document.'
    }
    $sources = $document.DocumentElement.SelectSingleNode('packageSources')
    if ($null -eq $sources) {
        $sources = $document.CreateElement('packageSources')
        [void]$document.DocumentElement.AppendChild($sources)
    }
    $url = 'https://packagefeedproxy.microsoft.io/nuget/v3/index.json'
    $found = $false
    foreach ($source in $sources.SelectNodes('add')) {
        $uri = $null
        $value = $source.GetAttribute('value')
        if ([Uri]::TryCreate($value, [UriKind]::Absolute, [ref]$uri) -and
            $uri.Host -in @('nuget.org', 'www.nuget.org', 'api.nuget.org')) {
            # Retain source keys so existing packageSourceMapping rules still apply.
            $source.SetAttribute('value', $url)
            $source.SetAttribute('protocolVersion', '3')
            $found = $true
        } elseif ($value -eq $url) {
            $found = $true
        }
    }
    if (-not $found) {
        if ($sources.SelectSingleNode("add[@key='CFS']")) {
            throw 'The NuGet source name CFS is already used by another feed.'
        }
        $source = $document.CreateElement('add')
        $source.SetAttribute('key', 'CFS')
        $source.SetAttribute('value', $url)
        $source.SetAttribute('protocolVersion', '3')
        [void]$sources.AppendChild($source)
    }
    $document.OuterXml
}

function Get-CfsCargoContent {
    param([string]$Content)

    $begin = '# BEGIN wsl-launchpad CFS'
    $end = '# END wsl-launchpad CFS'
    $pattern = '(?ms)^# BEGIN wsl-launchpad CFS\r?\n.*?^# END wsl-launchpad CFS(?:\r?\n|\z)'
    $blocks = [regex]::Matches($Content, $pattern)
    if ($blocks.Count -gt 1 -or
        ([regex]::Matches($Content, [regex]::Escape($begin)).Count -ne $blocks.Count) -or
        ([regex]::Matches($Content, [regex]::Escape($end)).Count -ne $blocks.Count)) {
        throw 'Malformed managed CFS block in Cargo configuration.'
    }
    $remaining = [regex]::Replace($Content, $pattern, '')
    # Refuse source declarations, including quoted/dotted/inline forms, rather
    # than attempting to rewrite arbitrary TOML without a parser.
    if ($remaining -match '(?m)^\s*(?:\[\[?\s*[''"]?source(?:[''"]|\s|\.|\])|[''"]?source[''"]?\s*[.=])') {
        throw 'Cargo already has source configuration. Merge the CFS source replacement manually; no files were changed.'
    }
    if ($remaining -match "'''|`"`"`"") {
        throw 'Cargo configuration contains multiline strings; merge CFS manually to avoid changing TOML string contents.'
    }
    $block = @"
$begin
[source.crates-io]
replace-with = "cfs"

[source.cfs]
registry = "sparse+https://packagefeedproxy.microsoft.io/cargo/index/"
$end
"@
    if ($blocks.Count -eq 1) {
        return $Content.Substring(0, $blocks[0].Index) + $block + "`n" +
            $Content.Substring($blocks[0].Index + $blocks[0].Length)
    }
    $separator = if ($Content.Length -eq 0 -or $Content.EndsWith("`n")) { '' } else { "`n" }
    $Content + $separator + $block + "`n"
}

function Get-CfsClientFilePlan {
    param([string[]]$NuGetPaths, [string]$CargoHome)

    foreach ($path in $NuGetPaths) {
        $content = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path) } else { '' }
        [pscustomobject]@{ Path = $path; Content = Get-CfsNuGetContent -Content $content }
    }
    $legacy = Join-Path $CargoHome 'config'
    $path = if (Test-Path -LiteralPath $legacy) { $legacy } else { Join-Path $CargoHome 'config.toml' }
    $content = if (Test-Path -LiteralPath $path) { [IO.File]::ReadAllText($path) } else { '' }
    [pscustomobject]@{ Path = $path; Content = Get-CfsCargoContent -Content $content }
}

function Get-CfsWindowsClientPaths {
    $cargoHome = if ($env:CARGO_HOME) { $env:CARGO_HOME } else { Join-Path $HOME '.cargo' }
    $cargoHome = [IO.Path]::GetFullPath($cargoHome, $PWD.Path)
    @{
        NuGetPaths = @(Join-Path $env:APPDATA 'NuGet\NuGet.Config')
        CargoHome = $cargoHome
    }
}

function Get-CfsWslContext {
    param([string]$Distribution)

    $probe = @'
set -eu
wslpath -w "$HOME"
wslpath -w "${CARGO_HOME:-$HOME/.cargo}"
if command -v pwsh >/dev/null 2>&1; then printf 'pwsh\n'; else printf 'no-pwsh\n'; fi
'@
    $result = @(& wsl.exe --distribution $Distribution --exec sh -c $probe)
    if ($LASTEXITCODE -ne 0 -or $result.Count -ne 3) {
        throw "Could not discover the default user's paths in WSL distribution '$Distribution'."
    }
    $homePath = $result[0].Trim()
    $cargoHome = $result[1].Trim()
    if (-not [IO.Path]::IsPathFullyQualified($homePath) -or
        -not [IO.Path]::IsPathFullyQualified($cargoHome)) {
        throw 'WSL returned non-absolute Windows paths.'
    }
    $nugetPaths = @(Join-Path $homePath '.nuget\NuGet\NuGet.Config')
    # Mono/NuGet clients can use this second location instead of dotnet's.
    $alternative = Join-Path $homePath '.config\NuGet\NuGet.Config'
    if (Test-Path -LiteralPath $alternative) { $nugetPaths += $alternative }
    @{
        NuGetPaths = $nugetPaths
        CargoHome = $cargoHome
        HasPowerShell = $result[2].Trim() -eq 'pwsh'
    }
}

function Save-CfsClientFile {
    param([string]$Path, [string]$Content)

    if (Test-Path -LiteralPath $Path) {
        if ([IO.File]::ReadAllText($Path) -ceq $Content) { return }
        $backup = "$Path.cfs.bak"
        if (-not (Test-Path -LiteralPath $backup)) { [IO.File]::Copy($Path, $backup) }
    }
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $Path))
    [IO.File]::WriteAllText($Path, $Content, [Text.UTF8Encoding]::new($false))
    if ([IO.File]::ReadAllText($Path) -cne $Content) { throw "Verification failed for $Path." }
    Write-Output "Saved and verified $Path."
}

function Set-CfsPowerShellRepositories {
    $configured = $false
    $hasPowerShellGet = $null -ne (Get-Command Get-PSRepository -ErrorAction SilentlyContinue)
    if ($hasPowerShellGet) {
        $providers = @(Get-PackageProvider -ListAvailable -ErrorAction Stop | Where-Object Name -eq 'NuGet')
        if (-not $providers.Count) {
            Write-Warning 'PowerShellGet requires an installed NuGet provider. Its repository was not changed; install the provider through your approved process and rerun.'
            $hasPowerShellGet = $false
        }
    }
    if ($hasPowerShellGet) {
        $repositories = @(Get-PSRepository -ErrorAction Stop)
        $gallery = @($repositories | Where-Object Name -eq 'PSGallery')
        $name = 'PSGallery'
        if ($gallery.Count) {
            Set-PSRepository -Name PSGallery -SourceLocation 'https://packagefeedproxy.microsoft.io/powershell/v2' -ErrorAction Stop
        } else {
            $name = 'CFS'
            $matching = @($repositories | Where-Object {
                $_.SourceLocation.TrimEnd('/') -eq 'https://packagefeedproxy.microsoft.io/powershell/v2'
            })
            if ($matching.Count) { $name = $matching[0].Name }
            $cfs = @($repositories | Where-Object Name -eq $name)
            if ($cfs.Count) {
                if ($cfs[0].SourceLocation.TrimEnd('/') -ne 'https://packagefeedproxy.microsoft.io/powershell/v2') {
                    throw 'The PowerShellGet repository name CFS is already used by another feed.'
                }
                Set-PSRepository -Name $name -SourceLocation 'https://packagefeedproxy.microsoft.io/powershell/v2' -ErrorAction Stop
            } else {
                Register-PSRepository -Name CFS -SourceLocation 'https://packagefeedproxy.microsoft.io/powershell/v2' -InstallationPolicy Untrusted -ErrorAction Stop
            }
        }
        $saved = Get-PSRepository -Name $name -ErrorAction Stop
        if ($saved.SourceLocation.TrimEnd('/') -ne 'https://packagefeedproxy.microsoft.io/powershell/v2') {
            throw 'PowerShellGet CFS repository verification failed.'
        }
        $configured = $true
        Write-Output 'Configured PowerShellGet CFS source; repository trust was not elevated.'
    }
    if (Get-Command Get-PSResourceRepository -ErrorAction SilentlyContinue) {
        $repositories = @(Get-PSResourceRepository -ErrorAction Stop)
        $names = @($repositories | ForEach-Object Name)
        $name = if ($names -contains 'PSGallery') { 'PSGallery' } else { 'CFS' }
        if ($name -eq 'CFS') {
            $matching = @($repositories | Where-Object {
                $_.Uri.ToString().TrimEnd('/') -eq 'https://packagefeedproxy.microsoft.io/powershell/v3/index.json'
            })
            if ($matching.Count) { $name = $matching[0].Name }
        }
        if ($names -contains $name) {
            $existing = @($repositories | Where-Object Name -eq $name)[0]
            if ($name -eq 'CFS' -and $existing.Uri.ToString().TrimEnd('/') -ne 'https://packagefeedproxy.microsoft.io/powershell/v3/index.json') {
                throw 'The PSResourceGet repository name CFS is already used by another feed.'
            }
            Set-PSResourceRepository -Name $name -Uri 'https://packagefeedproxy.microsoft.io/powershell/v3/index.json' -ErrorAction Stop
        } else {
            Register-PSResourceRepository -Name $name -Uri 'https://packagefeedproxy.microsoft.io/powershell/v3/index.json' -Trusted:$false -ErrorAction Stop
        }
        $saved = Get-PSResourceRepository -Name $name -ErrorAction Stop
        if ($saved.Uri.ToString().TrimEnd('/') -ne 'https://packagefeedproxy.microsoft.io/powershell/v3/index.json') {
            throw 'PSResourceGet CFS repository verification failed.'
        }
        $configured = $true
        Write-Output 'Configured PSResourceGet CFS source; repository trust was not elevated.'
    }
    if (-not $configured) {
        Write-Warning 'No usable PowerShellGet or PSResourceGet client is available. PowerShell Gallery client configuration was not applied.'
    }
}

function Set-CfsWslPowerShellRepositories {
    param([string]$Distribution)

    $code = "`$ErrorActionPreference = 'Stop'; function Set-CfsPowerShellRepositories {`n" +
        ${function:Set-CfsPowerShellRepositories}.ToString() + "`n}; Set-CfsPowerShellRepositories"
    $encoded = [Convert]::ToBase64String([Text.Encoding]::Unicode.GetBytes($code))
    & wsl.exe --distribution $Distribution --exec pwsh -NoLogo -NoProfile -NonInteractive -EncodedCommand $encoded
    if ($LASTEXITCODE -ne 0) { throw "PowerShell repository setup failed in WSL distribution '$Distribution'." }
}

function Invoke-CfsSetup {
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'Medium')]
    param(
        [switch]$ConfigureClients,
        [string]$WslDistribution
    )

    if (-not $IsWindows) {
        throw 'Run with PowerShell 7.4 or newer on Windows. From WSL, use pwsh.exe and the Windows-hosted script.'
    }
    if ($WslDistribution -and -not $ConfigureClients) {
        throw '-WslDistribution requires -ConfigureClients.'
    }

    $settings = [ordered]@{
        APEX_NPM_REGISTRY_HOST_PATH = 'packagefeedproxy.microsoft.io/npm/'
        APEX_PIP_INDEX_HOST_PATH = 'packagefeedproxy.microsoft.io/pypi/simple/'
        APEX_POWERSHELL_REPOSITORY_URL = 'https://packagefeedproxy.microsoft.io/powershell/v2'
    }
    if ($ConfigureClients) {
        $settings['NPM_CONFIG_REGISTRY'] = 'https://packagefeedproxy.microsoft.io/npm/'
        $settings['PIP_INDEX_URL'] = 'https://packagefeedproxy.microsoft.io/pypi/simple/'
        $settings['UV_DEFAULT_INDEX'] = 'https://packagefeedproxy.microsoft.io/pypi/simple/'
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

    $target = 'Current Windows user environment'
    if ($ConfigureClients) { $target += ' and native Windows package clients' }
    if ($WslDistribution) { $target += " and WSL distribution '$WslDistribution'" }
    if (-not $PSCmdlet.ShouldProcess($target, 'Configure CFS feeds for interactive development (not CI)')) {
        Write-Output 'No settings were changed.'
        return
    }

    # Detect file conflicts before persisting any settings.
    $files = @()
    $wslContext = $null
    if ($ConfigureClients) {
        $paths = Get-CfsWindowsClientPaths
        $files += @(Get-CfsClientFilePlan @paths)
        if ($WslDistribution) {
            $wslContext = Get-CfsWslContext -Distribution $WslDistribution
            $files += @(Get-CfsClientFilePlan -NuGetPaths $wslContext.NuGetPaths -CargoHome $wslContext.CargoHome)
        }
    }
    foreach ($setting in $settings.GetEnumerator()) {
        Set-PersistentEnvironmentVariable -Name $setting.Key -Value $setting.Value
        $saved = Get-PersistentEnvironmentVariable -Name $setting.Key -Scope User
        if ($saved -cne $setting.Value) {
            throw "Verification failed for $($setting.Key)."
        }
        Write-Output "Saved and verified $($setting.Key)."
    }
    foreach ($file in $files) { Save-CfsClientFile -Path $file.Path -Content $file.Content }
    if ($ConfigureClients) {
        Set-CfsPowerShellRepositories
        if ($WslDistribution) {
            if ($wslContext.HasPowerShell) {
                Set-CfsWslPowerShellRepositories -Distribution $WslDistribution
            } else {
                Write-Warning "WSL '$WslDistribution' has no pwsh. PowerShell Gallery there is not configured; rerun after installing an approved PowerShell client if needed."
            }
        }
        Write-Output 'Native client defaults configured. Project settings, extra indexes, and private feeds may still override or supplement them.'
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
