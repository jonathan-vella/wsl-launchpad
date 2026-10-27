#Requires -Version 7.4
# No Pester dependency: every WSL invocation and network download is mocked.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\bootstrap.ps1" -LinuxUser tester

function Assert-True($Condition, $Message) {
    if (-not $Condition) { throw $Message }
}
function Assert-Throws([scriptblock]$Action, [string]$Pattern) {
    try { & $Action } catch {
        Assert-True ($_.Exception.Message -match $Pattern) "Unexpected error: $_"
        return
    }
    throw "Expected failure matching: $Pattern"
}

$testDirectory = Join-Path ([IO.Path]::GetTempPath()) ("wsl-launchpad-tests-" + [guid]::NewGuid())
New-Item -ItemType Directory -Path $testDirectory | Out-Null
try {
    $Wsl = (Get-Process -Id $PID).Path
    Assert-Throws { Invoke-Wsl -Arguments @('-NoProfile', '-Command', 'exit 20') } 'exit 20'
    Invoke-Wsl -Arguments @('-NoProfile', '-Command',
        '$text = [Console]::In.ReadToEnd(); if ($text -cne "one`ntwo`n") { exit 17 }') -InputText "one`r`ntwo`r`n"
    Assert-Throws { Invoke-Wsl -Arguments @('-NoProfile', '-Command', 'exit 20') -InputText '' } 'exit 20'
    $script:releasePrerelease = $false
    $script:releaseDigest = 'sha256:' + ('a' * 64)
    $script:assetOverride = ''
    function Invoke-RestMethod {
        param($Uri)
        $repository = if ($Uri -like '*/Azure/bicep/*') { 'Azure/bicep' } else { 'github/copilot-cli' }
        $names = if ($repository -eq 'Azure/bicep') { @('bicep-linux-x64', 'bicep-linux-arm64') } else {
            @('copilot-linux-x64.tar.gz', 'copilot-linux-arm64.tar.gz')
        }
        return [pscustomobject]@{
            tag_name = 'v9.8.7'; prerelease = $script:releasePrerelease; draft = $false
            assets = @($names | ForEach-Object { [pscustomobject]@{
                name = $_; digest = $script:releaseDigest
                browser_download_url = if ($script:assetOverride) { $script:assetOverride } else {
                    "https://github.com/$repository/releases/download/v9.8.7/$_"
                }
            } })
        }
    }
    $release = Get-StableRelease 'Azure/bicep' 'bicep-linux-x64'
    Assert-True ($release.Version -eq '9.8.7' -and $release.Hash -eq ('a' * 64)) 'Latest stable resolution failed.'
    $script:releasePrerelease = $true
    Assert-Throws { Get-StableRelease 'Azure/bicep' 'bicep-linux-x64' } 'stable release'
    $script:releasePrerelease = $false
    $script:releaseDigest = ''
    Assert-Throws { Get-StableRelease 'Azure/bicep' 'bicep-linux-x64' } 'SHA-256'
    $script:releaseDigest = 'sha256:' + ('a' * 64)
    $script:assetOverride = 'https://example.invalid/binary'
    Assert-Throws { Get-StableRelease 'Azure/bicep' 'bicep-linux-x64' } 'asset URL'
    $script:assetOverride = ''

    # Exercise signer identity/status handling with a mocked GPG process.
    function Invoke-WebRequest {
        param($Uri, $OutFile)
        [IO.File]::WriteAllText($OutFile, 'not an official image')
    }
    function Get-Command { param($Name, $ErrorAction); [pscustomobject]@{ Source = 'mock-gpg' } }
    $script:trustedKey = $true
    $script:validSignature = $true
    function Invoke-Gpg {
        param($Executable, $Arguments)
        if ('--show-keys' -in $Arguments) {
            if ($script:trustedKey) { 'fpr:::::::::2BC94FFF7015A5F28F1537AD0CD9FED33135CE90:' } else { 'fpr:::::::::UNTRUSTED:' }
        } elseif ('--verify' -in $Arguments -and $script:validSignature) {
            '[GNUPG:] VALIDSIG 2BC94FFF7015A5F28F1537AD0CD9FED33135CE90 2026-01-01'
        }
    }
    $signatureDirectory = Join-Path $testDirectory 'signature'
    New-Item -ItemType Directory -Path $signatureDirectory | Out-Null
    $fixtureChecksum = Join-Path $signatureDirectory 'checksum'
    $fixtureSignature = Join-Path $signatureDirectory 'checksum.sig'
    [IO.File]::WriteAllText($fixtureChecksum, 'fixture')
    [IO.File]::WriteAllText($fixtureSignature, 'fixture')
    Assert-ImageSignature $signatureDirectory $fixtureChecksum $fixtureSignature
    Remove-Item -LiteralPath (Join-Path $signatureDirectory 'gnupg') -Recurse
    $script:trustedKey = $false
    Assert-Throws { Assert-ImageSignature $signatureDirectory $fixtureChecksum $fixtureSignature } 'fingerprint'
    Remove-Item -LiteralPath (Join-Path $signatureDirectory 'gnupg') -Recurse
    $script:trustedKey = $true
    $script:validSignature = $false
    Assert-Throws { Assert-ImageSignature $signatureDirectory $fixtureChecksum $fixtureSignature } 'not signed'
    Remove-Item Function:\Get-Command
    function Assert-ImageSignature {}
    function Invoke-WebRequest {
        param($Uri, $OutFile)
        if ($Uri -like '*-wsl-checksum') {
            [IO.File]::WriteAllText($OutFile, ('0' * 64) + ' *AzureLinux-4.0-x86_64.wsl')
        } else { [IO.File]::WriteAllText($OutFile, 'fake image or signature') }
    }
    Assert-Throws { Get-VerifiedImage x64 } 'checksum mismatch'
    Assert-Throws { Get-VerifiedImage arm64 } 'architecture-matched checksum'

    function Test-Path {
        param($Path)
        return $Path -notlike 'HKLM:*'
    }
    function Invoke-Wsl {
        param([string[]]$Arguments)
        if ($Arguments[0] -eq '--version') { return ("WSL version: 3.0.4.0".ToCharArray() -join "`0") }
    }
    Assert-Prerequisites
    Remove-Item Function:\Test-Path
    function Assert-Prerequisites {}
    $script:testArchitecture = 'x64'
    function Get-HostArchitecture { $script:testArchitecture }
    function Get-VerifiedImage {
        param($Architecture)
        $directory = Join-Path $testDirectory 'download'
        New-Item -ItemType Directory -Path $directory -Force | Out-Null
        $package = Join-Path $directory 'fake.wsl'
        [IO.File]::WriteAllText($package, 'fixture')
        return $package
    }
    $script:calls = [Collections.Generic.List[object]]::new()
    $script:existing = $true
    $script:failSystem = $false
    $script:wslVersion = 2
    function Invoke-Wsl {
        param([string[]]$Arguments, [string]$InputText)
        $script:calls.Add($Arguments)
        switch ($Arguments[0]) {
            '--list' {
                if ($Arguments[1] -eq '--quiet') {
                    if ($script:existing) { "AzureLinux-4`0"; 'Ubuntu'; 'docker-desktop' }
                } else { "* AzureLinux-4 Running $script:wslVersion" }
            }
            '-d' {
                Assert-True ($Arguments[5] -eq '/usr/bin/env' -and $Arguments[6] -eq '-i') 'Linux must start with a clean environment.'
                Assert-True ($InputText -match 'provision_system') 'Expected the real helper as stdin.'
                if ('system' -in $Arguments -and $script:failSystem) { throw 'Mock system failure' }
            }
        }
    }

    Invoke-Bootstrap
    Assert-True (@($calls | Where-Object { $_[0] -eq '--install' }).Count -eq 0) 'Existing distro must not be reinstalled.'
    Assert-True ($calls[-1][0] -eq '--set-default') 'Default must follow verification.'

    $calls.Clear()
    $script:existing = $false
    Invoke-Bootstrap
    Assert-True (@($calls | Where-Object { $_[0] -eq '--install' }).Count -eq 1) 'Missing distro must install exactly once.'
    Assert-True (-not (Test-Path (Join-Path $testDirectory 'download'))) 'Temporary image must be cleaned up.'

    $calls.Clear()
    $script:existing = $true
    $script:failSystem = $true
    Assert-Throws { Invoke-Bootstrap } 'Mock system failure'
    Assert-True (@($calls | Where-Object { $_[0] -in @('--manage', '--set-default') }).Count -eq 0) 'Failed verification must not change defaults.'

    $calls.Clear()
    $script:failSystem = $false
    $script:wslVersion = 1
    Assert-Throws { Invoke-Bootstrap } 'not WSL 2'
    Assert-True (@($calls | Where-Object { $_[0] -eq '-d' }).Count -eq 0) 'WSL 1 must not be provisioned.'

    $script:wslVersion = 2
    $calls.Clear()
    $script:testArchitecture = 'arm64'
    Invoke-Bootstrap
    $systemCall = @($calls | Where-Object { 'system' -in $_ })[0]
    Assert-True ('arm64' -in $systemCall -and '9.8.7' -in $systemCall) 'ARM64 must receive dynamically resolved stable versions.'
    $LinuxUser = 'root'
    Assert-Throws { Invoke-Bootstrap } 'non-root'
    Assert-True (@($calls | Where-Object {
        $_[0] -in @('--unregister', '--shutdown', '--terminate', '--set-version')
    }).Count -eq 0) 'Bootstrap must never remove, stop, or convert existing distros.'
    $bootstrapSource = Get-Content (Join-Path $PSScriptRoot '..\bootstrap.ps1') -Raw
    Assert-True ($bootstrapSource -notmatch 'ApplyDotfiles|jonathan-vella/dotfiles') 'Core bootstrap has no personal dotfiles dependency.'
    Write-Host 'PASS: latest release/digest selection, signer identity, image checksum, UTF-16 output, stdin transport and safe orchestration checks.'
} finally {
    Remove-Item -LiteralPath $testDirectory -Recurse -Force
}
