#Requires -Version 7.4
[CmdletBinding()]
param(
    [Parameter(Mandatory)]
    [ValidatePattern('^[a-z_][a-z0-9_-]{0,31}$')]
    [string]$LinuxUser
)

Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
$Distro = 'AzureLinux-4'
$Wsl = "$env:WINDIR\System32\wsl.exe"

function Invoke-Wsl {
    param([string[]]$Arguments, [string]$InputText)
    if ($PSBoundParameters.ContainsKey('InputText')) {
        # Write exact UTF-8/LF bytes; PowerShell's text pipeline appends CRLF on Windows.
        $start = [Diagnostics.ProcessStartInfo]::new($Wsl)
        $start.UseShellExecute = $false
        $start.RedirectStandardInput = $true
        $start.StandardInputEncoding = [Text.UTF8Encoding]::new($false)
        foreach ($argument in $Arguments) { $start.ArgumentList.Add($argument) }
        $process = [Diagnostics.Process]::Start($start)
        try {
            $process.StandardInput.Write($InputText.Replace("`r`n", "`n"))
            $process.StandardInput.Close()
            $process.WaitForExit()
            $exitCode = $process.ExitCode
        } finally {
            $process.Dispose()
        }
    } else {
        & $Wsl @Arguments
        $exitCode = $LASTEXITCODE
    }
    if ($exitCode -ne 0) {
        throw "WSL failed (exit $exitCode): $($Arguments -join ' '). Resolve the error and rerun."
    }
}

function Assert-Prerequisites {
    if (-not $IsWindows) { throw 'Run this entry point in Windows PowerShell 7.4 or newer.' }
    if (-not (Test-Path $Wsl)) {
        throw 'WSL is missing. In an elevated Windows terminal run: wsl --install --no-distribution. Reboot when requested, then rerun.'
    }
    foreach ($key in @(
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\Component Based Servicing\RebootPending',
        'HKLM:\SOFTWARE\Microsoft\Windows\CurrentVersion\WindowsUpdate\Auto Update\RebootRequired'
    )) {
        if (Test-Path $key) { throw 'Windows reports a pending reboot. Reboot explicitly, then rerun.' }
    }
    try {
        $versionOutput = ((Invoke-Wsl -Arguments @('--version')) -join "`n") -replace "`0", ''
    } catch {
        throw "Modern WSL is unavailable. Run wsl --update yourself (or elevated wsl --install --no-distribution if missing), reboot if requested, then rerun. $_"
    }
    if ($versionOutput -notmatch '(\d+\.\d+\.\d+)(?:\.\d+)?' -or [version]$Matches[1] -lt [version]'2.6.0') {
        throw 'WSL 2.6.0+ is required. Run wsl --update yourself, reboot if requested, then rerun.'
    }
    try {
        Invoke-Wsl -Arguments @('--status') | Out-Host
    } catch {
        throw "WSL is not ready. Resolve its prerequisite/virtualization error above and any requested elevation or reboot, then rerun. $_"
    }
}

function Get-HostArchitecture {
    switch ([System.Runtime.InteropServices.RuntimeInformation]::OSArchitecture.ToString()) {
        'X64' { return 'x64' }
        'Arm64' { return 'arm64' }
        default { throw 'Only native Windows x64 and ARM64 are supported.' }
    }
}

function Get-StableRelease {
    param([string]$Repository, [string]$AssetName)
    $release = Invoke-RestMethod -Uri "https://api.github.com/repos/$Repository/releases/latest"
    if ($release.prerelease -or $release.draft -or $release.tag_name -cnotmatch '^v\d+\.\d+\.\d+$') {
        throw "Expected a stable release from $Repository."
    }
    $assets = @($release.assets | Where-Object { $_.name -ceq $AssetName })
    if ($assets.Count -ne 1 -or $assets[0].digest -cnotmatch '^sha256:([a-f0-9]{64})$') {
        throw "Missing unique official SHA-256 asset digest: $Repository/$AssetName."
    }
    $hash = $Matches[1]
    $expectedUrl = "https://github.com/$Repository/releases/download/$($release.tag_name)/$AssetName"
    if ($assets[0].browser_download_url -cne $expectedUrl) { throw 'Unexpected official release asset URL.' }
    return [pscustomobject]@{ Version = $release.tag_name.Substring(1); Hash = $hash }
}

function Invoke-Gpg {
    param([string]$Executable, [string[]]$Arguments)
    $output = & $Executable @Arguments
    if ($LASTEXITCODE -ne 0) { throw 'Microsoft image signature/key verification failed; no image was installed.' }
    return $output
}

function Assert-ImageSignature {
    param([string]$Directory, [string]$Checksum, [string]$Signature)
    $gpg = Get-Command gpg.exe -ErrorAction SilentlyContinue
    if (-not $gpg) {
        $gitGpg = Join-Path $env:ProgramFiles 'Git\usr\bin\gpg.exe'
        if (-not (Test-Path $gitGpg)) { throw 'Fresh image verification requires GnuPG on Windows (for example Git for Windows). Install it explicitly, then rerun.' }
        $executable = $gitGpg
    } else { $executable = $gpg.Source }
    $gpgHome = Join-Path $Directory 'gnupg'
    New-Item -ItemType Directory -Path $gpgHome | Out-Null
    $key = Join-Path $gpgHome 'microsoft.asc'
    Invoke-WebRequest -Uri 'https://raw.githubusercontent.com/microsoft/azurelinux/refs/heads/4.0/base/comps/azurelinux-repos/RPM-GPG-KEY-azurelinux-4.0-primary' -OutFile $key
    Copy-Item -LiteralPath $Checksum -Destination (Join-Path $gpgHome 'checksum')
    Copy-Item -LiteralPath $Signature -Destination (Join-Path $gpgHome 'checksum.sig')
    # Relative names work with both native Windows and Git for Windows GnuPG.
    Push-Location $gpgHome
    try {
        $common = @('--no-options', '--homedir', '.', '--batch', '--no-autostart')
        $keyInfo = (Invoke-Gpg $executable ($common + @('--with-colons', '--show-keys', 'microsoft.asc'))) -join "`n"
        $fingerprint = '2BC94FFF7015A5F28F1537AD0CD9FED33135CE90'
        if ($keyInfo -notmatch "(?m)^fpr:::::::::$fingerprint`:") { throw 'Unexpected Microsoft signing key fingerprint.' }
        Invoke-Gpg $executable ($common + @('--dearmor', '--output', 'microsoft.gpg', 'microsoft.asc')) | Out-Null
        $status = (Invoke-Gpg $executable ($common + @('--no-default-keyring', '--keyring', 'microsoft.gpg',
            '--status-fd', '1', '--verify', 'checksum.sig', 'checksum'))) -join "`n"
        if ($status -notmatch "(?m)^\[GNUPG:\] VALIDSIG $fingerprint ") {
            throw 'Checksum was not signed by the trusted Microsoft key.'
        }
    } finally {
        Pop-Location
    }
}

function Get-VerifiedImage {
    param([ValidateSet('x64', 'arm64')][string]$Architecture)
    $directory = Join-Path ([IO.Path]::GetTempPath()) ("wsl-launchpad-" + [guid]::NewGuid())
    New-Item -ItemType Directory -Path $directory | Out-Null
    $imageArch = if ($Architecture -eq 'x64') { 'x86_64' } else { 'aarch64' }
    $name = "AzureLinux-4.0-$imageArch.wsl"
    $package = Join-Path $directory $name
    try {
        $checksum = Join-Path $directory 'checksum'
        $signature = Join-Path $directory 'checksum.sig'
        Invoke-WebRequest -Uri "https://aka.ms/azurelinux-4.0-$imageArch-wsl-checksum" -OutFile $checksum
        Invoke-WebRequest -Uri "https://aka.ms/azurelinux-4.0-$imageArch-wsl-checksum-signature" -OutFile $signature
        Assert-ImageSignature $directory $checksum $signature
        $lines = @(Get-Content $checksum | Where-Object { $_ -cmatch "^([a-f0-9]{64})\s+\*?$([regex]::Escape($name))$" })
        if ($lines.Count -ne 1) { throw 'Missing unique architecture-matched checksum in the signed Microsoft manifest.' }
        $expected = ($lines[0] -split '\s+')[0]
        Invoke-WebRequest -Uri "https://aka.ms/azurelinux-4.0-$imageArch.wsl" -OutFile $package
        if ((Get-FileHash -Algorithm SHA256 $package).Hash -ne $expected) {
            throw 'WSL image checksum mismatch. No image was installed; retry if Microsoft is publishing a new image.'
        }
        return $package
    } catch {
        Remove-Item -LiteralPath $directory -Recurse -Force
        throw
    }
}

function Invoke-Bootstrap {
    if ($LinuxUser -eq 'root') { throw 'Choose a non-root Linux user explicitly.' }
    Assert-Prerequisites
    $arch = Get-HostArchitecture
    $bicep = Get-StableRelease 'Azure/bicep' "bicep-linux-$arch"
    $copilot = Get-StableRelease 'github/copilot-cli' "copilot-linux-$arch.tar.gz"
    Write-Host "Resolved latest stable Bicep $($bicep.Version), Copilot $($copilot.Version)."
    $helper = Get-Content (Join-Path $PSScriptRoot 'provision.sh') -Raw
    $installed = @((Invoke-Wsl -Arguments @('--list', '--quiet')) |
        ForEach-Object { ($_ -replace "`0", '').Trim() })
    if ($Distro -notin $installed) {
        $package = Get-VerifiedImage $arch
        try {
            Invoke-Wsl -Arguments @('--install', '--from-file', $package, '--name', $Distro, '--no-launch') | Out-Host
        } finally {
            Remove-Item -LiteralPath (Split-Path $package) -Recurse -Force
        }
    }
    $list = ((Invoke-Wsl -Arguments @('--list', '--verbose')) -join "`n") -replace "`0", ''
    if ($list -notmatch '(?m)^\s*\*?\s*AzureLinux-4\s+.+?\s+2\s*$') {
        throw 'AzureLinux-4 is not WSL 2. Convert it explicitly with wsl --set-version AzureLinux-4 2, then rerun.'
    }
    Invoke-Wsl -Arguments @('-d', $Distro, '-u', 'root', '--exec', '/usr/bin/env', '-i',
        'PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin', '/bin/bash', '-s', '--',
        'system', $LinuxUser, $arch, $bicep.Version, $bicep.Hash, $copilot.Version, $copilot.Hash) -InputText $helper | Out-Host
    Invoke-Wsl -Arguments @('--manage', $Distro, '--set-default-user', $LinuxUser) | Out-Host
    Invoke-Wsl -Arguments @('--set-default', $Distro) | Out-Host
    Write-Host 'Core setup verified. Sign-ins and optional dotfiles remain separate human steps.'
    Write-Host "Open: wsl -d $Distro -u $LinuxUser"
    Write-Host 'Sign in inside Linux: gh auth login --hostname github.com; az login; copilot'
    Write-Host 'No cloud sign-in or dotfiles installer was run.'
}

if ($MyInvocation.InvocationName -ne '.') { Invoke-Bootstrap }
