#Requires -Version 7.4
# Persistence is mocked; these tests never change the host environment.
Set-StrictMode -Version Latest
$ErrorActionPreference = 'Stop'
. "$PSScriptRoot\..\configure-cfs.ps1"

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

$script:userEnvironment = @{}
$script:machineEnvironment = @{}
$script:writes = [Collections.Generic.List[string]]::new()
$script:failName = ''
$script:corruptName = ''

function Get-PersistentEnvironmentVariable {
    param([string]$Name, [string]$Scope)
    $values = if ($Scope -eq 'User') { $script:userEnvironment } else { $script:machineEnvironment }
    $values[$Name]
}
function Set-PersistentEnvironmentVariable {
    param([string]$Name, [string]$Value)
    $script:writes.Add($Name)
    if ($Name -eq $script:failName) { throw 'Mock persistence failure' }
    $script:userEnvironment[$Name] = if ($Name -eq $script:corruptName) { 'incorrect' } else { $Value }
}

if (-not $IsWindows) {
    Assert-Throws { Invoke-CfsSetup -Confirm:$false } 'on Windows'
    Assert-True ($writes.Count -eq 0) 'Non-Windows setup must not write settings.'
    Write-Output 'Non-Windows host rejection passed.'
    return
}

$names = 'APEX_NPM_REGISTRY_HOST_PATH:APEX_PIP_INDEX_HOST_PATH:APEX_POWERSHELL_REPOSITORY_URL'
$userEnvironment['WSLENV'] = 'KEEP/p:apex_pip_index_host_path/u:ALSO_KEEP/l:APEX_NPM_REGISTRY_HOST_PATH/p'
$userEnvironment['APEX_NPM_REGISTRY_HOST_PATH'] = 'previous.example/npm/'
$userEnvironment['UNRELATED'] = 'retain'
$machineEnvironment['WSLENV'] = 'MACHINE/p'
Invoke-CfsSetup -Confirm:$false | Out-Null
Assert-True ($userEnvironment['WSLENV'] -ceq "KEEP/p:ALSO_KEEP/l:$names") 'User entries/flags were not preserved.'
Assert-True ($userEnvironment['APEX_NPM_REGISTRY_HOST_PATH'] -ceq 'packagefeedproxy.microsoft.io/npm/') 'npm feed mismatch.'
Assert-True ($userEnvironment['APEX_PIP_INDEX_HOST_PATH'] -ceq 'packagefeedproxy.microsoft.io/pypi/simple/') 'Python feed mismatch.'
Assert-True ($userEnvironment['APEX_POWERSHELL_REPOSITORY_URL'] -ceq 'https://packagefeedproxy.microsoft.io/powershell/v2') 'PowerShell feed mismatch.'
Assert-True ($userEnvironment['UNRELATED'] -ceq 'retain') 'An unrelated user setting changed.'
Assert-True ($machineEnvironment['WSLENV'] -ceq 'MACHINE/p') 'Machine settings changed.'
Assert-True ($writes.Count -eq 4) 'Expected only the three feeds and WSLENV to be written.'
$saved = $userEnvironment['WSLENV']
Invoke-CfsSetup -Confirm:$false | Out-Null
Assert-True ($userEnvironment['WSLENV'] -ceq $saved) 'Repeated setup changed WSLENV.'

$writes.Clear()
Invoke-CfsSetup -WhatIf | Out-Null
Assert-True ($writes.Count -eq 0 -and $userEnvironment['WSLENV'] -ceq $saved) 'WhatIf changed settings.'

$userEnvironment.Clear()
Invoke-CfsSetup -Confirm:$false | Out-Null
Assert-True ($userEnvironment['WSLENV'] -ceq "MACHINE/p:$names") 'Machine fallback lost existing entries.'

$userEnvironment.Clear()
$userEnvironment['WSLENV'] = ''
Invoke-CfsSetup -Confirm:$false | Out-Null
Assert-True ($userEnvironment['WSLENV'] -ceq $names) 'An explicit empty user value must shadow machine settings.'

$userEnvironment.Clear()
$machineEnvironment.Clear()
Invoke-CfsSetup -Confirm:$false | Out-Null
Assert-True ($userEnvironment['WSLENV'] -ceq $names) 'Empty environment setup failed.'

$userEnvironment.Clear()
$writes.Clear()
$script:failName = 'APEX_NPM_REGISTRY_HOST_PATH'
Assert-Throws { Invoke-CfsSetup -Confirm:$false | Out-Null } 'Mock persistence failure'
Assert-True ($writes.Count -eq 1) 'Setup continued after a persistence failure.'
$script:failName = ''
$script:corruptName = 'APEX_NPM_REGISTRY_HOST_PATH'
$writes.Clear()
Assert-Throws { Invoke-CfsSetup -Confirm:$false | Out-Null } 'Verification failed'
Assert-True ($writes.Count -eq 1) 'Setup continued after a verification failure.'
$script:corruptName = ''

# Pure transforms must preserve private feeds and unrelated client settings.
$nugetOriginal = @'
<?xml version="1.0" encoding="utf-16"?>
<configuration>
  <packageSources>
    <add key="public" value="https://api.nuget.org/v3/index.json" />
    <add key="private" value="https://private.example/nuget/" />
  </packageSources>
  <packageSourceMapping><packageSource key="public"><package pattern="Public.*" /></packageSource></packageSourceMapping>
  <config><add key="description" value="café" /></config>
</configuration>
'@
$nuget = Get-CfsNuGetContent -Content $nugetOriginal
$nugetXml = [xml]$nuget
Assert-True ($nugetXml.configuration.packageSources.add[0].key -ceq 'public') 'NuGet changed the public source key.'
Assert-True ($nugetXml.configuration.packageSources.add[0].value -ceq 'https://packagefeedproxy.microsoft.io/nuget/v3/index.json') 'NuGet did not redirect the public source.'
Assert-True ($nugetXml.configuration.packageSources.add[0].protocolVersion -ceq '3') 'NuGet protocol mismatch.'
Assert-True ($nugetXml.configuration.packageSources.add[1].value -ceq 'https://private.example/nuget/') 'NuGet changed a private feed.'
Assert-True ($nugetXml.configuration.packageSourceMapping.packageSource.key -ceq 'public' -and
    $nugetXml.configuration.packageSourceMapping.packageSource.package.pattern -ceq 'Public.*') 'NuGet lost source mapping.'
Assert-True ($nuget -match 'encoding="utf-8"' -and $nuget -cmatch 'café') 'NuGet encoding declaration/content mismatch.'
Assert-True ((Get-CfsNuGetContent -Content $nuget) -ceq $nuget) 'NuGet rerun was not idempotent.'
$emptyNuget = [xml](Get-CfsNuGetContent -Content '')
Assert-True ($emptyNuget.configuration.packageSources.add.key -ceq 'CFS') 'Empty NuGet config did not gain a CFS source.'
Assert-Throws { Get-CfsNuGetContent -Content '<configuration>' } 'XML|end|closed'
Assert-Throws { Get-CfsNuGetContent -Content '<wrong />' } 'configuration'
Assert-Throws { Get-CfsNuGetContent -Content '<!DOCTYPE configuration [<!ENTITY x "unsafe">]><configuration />' } 'DTD'
Assert-Throws { Get-CfsNuGetContent -Content '<configuration><packageSources><add key="CFS" value="https://private.example/" /></packageSources></configuration>' } 'already used'

$cargoOriginal = "[alias]`ncheck-all = `"check --all-targets`"`n[build]`njobs = 2"
$cargo = Get-CfsCargoContent -Content $cargoOriginal
Assert-True ($cargo.StartsWith($cargoOriginal + "`n")) 'Cargo lost aliases or build configuration.'
Assert-True ($cargo.Contains("[source.crates-io]`nreplace-with = `"cfs`"")) 'Cargo did not replace crates.io.'
Assert-True ($cargo.Contains('registry = "sparse+https://packagefeedproxy.microsoft.io/cargo/index/"')) 'Cargo sparse registry mismatch.'
Assert-True ((Get-CfsCargoContent -Content $cargo) -ceq $cargo) 'Cargo rerun was not idempotent.'
$cargoWithTail = $cargo + "[net]`nretry = 2`n"
Assert-True ((Get-CfsCargoContent -Content $cargoWithTail) -ceq $cargoWithTail) 'Cargo rerun moved or removed trailing settings.'
foreach ($conflict in @('[source.crates-io]', '["source".crates-io]', 'source.crates-io.replace-with = "private"', 'source = { crates-io = {} }')) {
    Assert-Throws { Get-CfsCargoContent -Content $conflict } 'already has source configuration'
}
foreach ($malformed in @('# BEGIN wsl-launchpad CFS', '# END wsl-launchpad CFS', ($cargo + $cargo))) {
    Assert-Throws { Get-CfsCargoContent -Content $malformed } 'Malformed managed'
}
foreach ($multiline in @('description = """text"""', "description = '''text'''")) {
    Assert-Throws { Get-CfsCargoContent -Content $multiline } 'multiline'
}

# All filesystem tests stay in one uniquely owned directory inside the checkout.
$testRoot = Join-Path (Split-Path -Parent $PSScriptRoot) ('.cfs-tests-' + [guid]::NewGuid().ToString('N'))
[void][IO.Directory]::CreateDirectory($testRoot)
$resolvedTestRoot = (Resolve-Path -LiteralPath $testRoot).ProviderPath
try {
    $savedPath = Join-Path $testRoot 'save\NuGet.Config'
    [void][IO.Directory]::CreateDirectory((Split-Path -Parent $savedPath))
    [IO.File]::WriteAllText($savedPath, $nugetOriginal, [Text.UnicodeEncoding]::new($false, $true))
    $originalBytes = [Convert]::ToBase64String([IO.File]::ReadAllBytes($savedPath))
    Save-CfsClientFile -Path $savedPath -Content $nuget | Out-Null
    Assert-True ([IO.File]::ReadAllText($savedPath) -ceq $nuget) 'Save did not persist transformed content.'
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes("$savedPath.cfs.bak")) -ceq $originalBytes) 'Backup did not preserve original bytes.'
    $savedBytes = [IO.File]::ReadAllBytes($savedPath)
    Assert-True ($savedBytes[0] -eq 60 -and [Text.UTF8Encoding]::new($false, $true).GetString($savedBytes) -ceq $nuget) 'Save did not write declaration-consistent UTF-8.'
    Save-CfsClientFile -Path $savedPath -Content $nuget | Out-Null
    Save-CfsClientFile -Path $savedPath -Content ($nuget + "`n") | Out-Null
    Assert-True ([Convert]::ToBase64String([IO.File]::ReadAllBytes("$savedPath.cfs.bak")) -ceq $originalBytes) 'A later save overwrote the first backup.'
    Assert-True (@(Get-ChildItem -LiteralPath (Split-Path -Parent $savedPath) -Filter '*.bak*').Count -eq 1) 'Save created duplicate backups.'
    $newPath = Join-Path $testRoot 'save\new\config.toml'
    Save-CfsClientFile -Path $newPath -Content $cargo | Out-Null
    Assert-True ((Test-Path -LiteralPath $newPath) -and -not (Test-Path -LiteralPath "$newPath.cfs.bak")) 'New file save/backup behavior was incorrect.'

    $legacyHome = Join-Path $testRoot 'legacy-cargo'
    [void][IO.Directory]::CreateDirectory($legacyHome)
    [IO.File]::WriteAllText((Join-Path $legacyHome 'config'), $cargoOriginal)
    [IO.File]::WriteAllText((Join-Path $legacyHome 'config.toml'), '[source.private]')
    $plan = @(Get-CfsClientFilePlan -NuGetPaths @() -CargoHome $legacyHome)
    Assert-True ($plan.Count -eq 1 -and $plan[0].Path -ceq (Join-Path $legacyHome 'config')) 'Legacy Cargo config did not take precedence.'
    Assert-True ($plan[0].Content -ceq $cargo) 'Legacy Cargo config was not used as input.'
    Assert-True ([IO.File]::ReadAllText((Join-Path $legacyHome 'config')) -ceq $cargoOriginal) 'Planning wrote a file.'

    # Command stubs are child-scoped: never query or change real repositories.
    & {
        $repositoryState = @{
            Available = $true
            PowerShellGet = @([pscustomobject]@{ Name = 'PSGallery'; SourceLocation = 'https://www.powershellgallery.com/api/v2'; InstallationPolicy = 'Untrusted' })
            PSResourceGet = @([pscustomobject]@{ Name = 'PSGallery'; Uri = [uri]'https://www.powershellgallery.com/api/v2'; Trusted = $false })
            IgnoreWrites = $false
            HasNuGetProvider = $true
            LegacyReads = 0
            Calls = [Collections.Generic.List[object]]::new()
        }
        function Get-Command {
            param($Name, $ErrorAction)
            if ($repositoryState.Available -and $Name -in @('Get-PSRepository', 'Get-PSResourceRepository')) { $true }
        }
        function Get-PackageProvider {
            [CmdletBinding()] param([switch]$ListAvailable)
            Assert-True ([bool]$ListAvailable) 'Provider discovery must not bootstrap a provider.'
            if ($repositoryState.HasNuGetProvider) { [pscustomobject]@{ Name = 'NuGet' } }
        }
        function Get-PSRepository {
            [CmdletBinding()] param($Name)
            $repositoryState.LegacyReads++
            $repositoryState.PowerShellGet | Where-Object { -not $Name -or $_.Name -eq $Name }
        }
        function Get-PSResourceRepository {
            [CmdletBinding()] param($Name)
            $repositoryState.PSResourceGet | Where-Object { -not $Name -or $_.Name -eq $Name }
        }
        function Set-PSRepository {
            [CmdletBinding()] param($Name, $SourceLocation, $InstallationPolicy)
            $repositoryState.Calls.Add(@{ Kind = 'SetPS'; Parameters = @{} + $PSBoundParameters })
            if (-not $repositoryState.IgnoreWrites) {
                ($repositoryState.PowerShellGet | Where-Object Name -eq $Name).SourceLocation = $SourceLocation
            }
        }
        function Register-PSRepository {
            [CmdletBinding()] param($Name, $SourceLocation, $InstallationPolicy)
            $repositoryState.Calls.Add(@{ Kind = 'RegisterPS'; Parameters = @{} + $PSBoundParameters })
            $repositoryState.PowerShellGet += [pscustomobject]@{ Name = $Name; SourceLocation = $SourceLocation; InstallationPolicy = $InstallationPolicy }
        }
        function Set-PSResourceRepository {
            [CmdletBinding()] param($Name, $Uri, [switch]$Trusted)
            $repositoryState.Calls.Add(@{ Kind = 'SetResource'; Parameters = @{} + $PSBoundParameters })
            if (-not $repositoryState.IgnoreWrites) {
                ($repositoryState.PSResourceGet | Where-Object Name -eq $Name).Uri = [uri]$Uri
            }
        }
        function Register-PSResourceRepository {
            [CmdletBinding()] param($Name, $Uri, [switch]$Trusted)
            $repositoryState.Calls.Add(@{ Kind = 'RegisterResource'; Parameters = @{} + $PSBoundParameters })
            $repositoryState.PSResourceGet += [pscustomobject]@{ Name = $Name; Uri = [uri]$Uri; Trusted = [bool]$Trusted }
        }
        Set-CfsPowerShellRepositories | Out-Null
        Assert-True ($repositoryState.Calls.Count -eq 2) 'Expected both installed repository clients to be configured.'
        Assert-True ($repositoryState.Calls[0].Kind -eq 'SetPS' -and $repositoryState.Calls[0].Parameters.Name -eq 'PSGallery' -and
            $repositoryState.Calls[0].Parameters.SourceLocation -ceq 'https://packagefeedproxy.microsoft.io/powershell/v2') 'PowerShellGet gallery redirect mismatch.'
        Assert-True ($repositoryState.Calls[1].Kind -eq 'SetResource' -and $repositoryState.Calls[1].Parameters.Name -eq 'PSGallery' -and
            $repositoryState.Calls[1].Parameters.Uri -ceq 'https://packagefeedproxy.microsoft.io/powershell/v3/index.json') 'PSResourceGet gallery redirect mismatch.'
        Assert-True (-not $repositoryState.Calls[0].Parameters.ContainsKey('InstallationPolicy') -and
            -not $repositoryState.Calls[1].Parameters.ContainsKey('Trusted')) 'Updating existing repositories must not change trust.'
        Assert-True ($repositoryState.PowerShellGet[0].InstallationPolicy -ceq 'Untrusted' -and
            -not $repositoryState.PSResourceGet[0].Trusted) 'Repository updates elevated trust.'

        $repositoryState.PowerShellGet = @()
        $repositoryState.PSResourceGet = @()
        $repositoryState.Calls.Clear()
        Set-CfsPowerShellRepositories | Out-Null
        Assert-True ($repositoryState.Calls.Count -eq 2 -and $repositoryState.Calls[0].Kind -eq 'RegisterPS' -and
            $repositoryState.Calls[0].Parameters.Name -eq 'CFS' -and $repositoryState.Calls[0].Parameters.InstallationPolicy -eq 'Untrusted') 'Missing PowerShellGet gallery should register untrusted CFS.'
        Assert-True ($repositoryState.Calls[1].Kind -eq 'RegisterResource' -and $repositoryState.Calls[1].Parameters.Name -eq 'CFS' -and
            $repositoryState.Calls[1].Parameters.ContainsKey('Trusted') -and -not $repositoryState.Calls[1].Parameters.Trusted) 'Missing PSResourceGet gallery should register untrusted CFS.'

        $repositoryState.Calls.Clear()
        Set-CfsPowerShellRepositories | Out-Null
        Assert-True ($repositoryState.Calls.Count -eq 2 -and $repositoryState.Calls[0].Kind -eq 'SetPS' -and
            $repositoryState.Calls[1].Kind -eq 'SetResource') 'Existing CFS repositories should be updated rather than duplicated.'

        $repositoryState.PowerShellGet[0].Name = 'azure-powershell'
        $repositoryState.PowerShellGet[0].SourceLocation += '/'
        $repositoryState.PSResourceGet[0].Name = 'existing-proxy'
        $repositoryState.Calls.Clear()
        Set-CfsPowerShellRepositories | Out-Null
        Assert-True ($repositoryState.Calls.Count -eq 2 -and
            $repositoryState.Calls[0].Kind -eq 'SetPS' -and
            $repositoryState.Calls[0].Parameters.Name -eq 'azure-powershell' -and
            $repositoryState.Calls[1].Kind -eq 'SetResource' -and
            $repositoryState.Calls[1].Parameters.Name -eq 'existing-proxy') 'Existing CFS sources under other names should be reused, not registered again.'
        $repositoryState.PowerShellGet[0].Name = 'CFS'
        $repositoryState.PSResourceGet[0].Name = 'CFS'

        $repositoryState.PowerShellGet[0].SourceLocation = 'https://private.example/powershell/'
        $repositoryState.Calls.Clear()
        Assert-Throws { Set-CfsPowerShellRepositories | Out-Null } 'PowerShellGet.*already used'
        Assert-True ($repositoryState.Calls.Count -eq 0) 'Private PowerShellGet CFS feed was overwritten.'
        $repositoryState.PowerShellGet[0].SourceLocation = 'https://packagefeedproxy.microsoft.io/powershell/v2'
        $repositoryState.PSResourceGet[0].Uri = [uri]'https://private.example/powershell/'
        $repositoryState.Calls.Clear()
        Assert-Throws { Set-CfsPowerShellRepositories | Out-Null } 'PSResourceGet.*already used'
        Assert-True (@($repositoryState.Calls | Where-Object { $_.Kind -like '*Resource' }).Count -eq 0) 'Private PSResourceGet CFS feed was overwritten.'

        $repositoryState.PowerShellGet = @([pscustomobject]@{ Name = 'PSGallery'; SourceLocation = 'https://unchanged.example/' })
        $repositoryState.IgnoreWrites = $true
        Assert-Throws { Set-CfsPowerShellRepositories | Out-Null } 'PowerShellGet.*verification failed'
        $repositoryState.PowerShellGet[0].SourceLocation = 'https://packagefeedproxy.microsoft.io/powershell/v2'
        $repositoryState.PSResourceGet = @([pscustomobject]@{ Name = 'PSGallery'; Uri = [uri]'https://unchanged.example/' })
        Assert-Throws { Set-CfsPowerShellRepositories | Out-Null } 'PSResourceGet.*verification failed'

        $repositoryState.IgnoreWrites = $false
        $repositoryState.HasNuGetProvider = $false
        $repositoryState.Calls.Clear()
        $legacyReads = $repositoryState.LegacyReads
        $messages = @(Set-CfsPowerShellRepositories 3>&1)
        Assert-True ($repositoryState.LegacyReads -eq $legacyReads -and $repositoryState.Calls.Count -eq 1 -and
            $repositoryState.Calls[0].Kind -eq 'SetResource') 'Missing NuGet provider should skip legacy repository calls but configure PSResourceGet.'
        Assert-True (@($messages | Where-Object { $_ -is [Management.Automation.WarningRecord] -and
            $_ -match 'requires an installed NuGet provider' }).Count -eq 1) 'Missing NuGet provider should warn without installing it.'
        $repositoryState.Available = $false
        $repositoryState.Calls.Clear()
        $messages = @(Set-CfsPowerShellRepositories 3>&1)
        Assert-True ($repositoryState.Calls.Count -eq 0 -and @($messages | Where-Object { $_ -is [Management.Automation.WarningRecord] -and $_ -match 'No usable PowerShellGet or PSResourceGet' }).Count -eq 1) 'Missing repository clients should warn without invoking commands.'
    }

    # Native integration resolves only test paths and invokes only repository/WSL mocks.
    & {
        $native = @{
            HostRoot = Join-Path $testRoot 'host'
            WslRoot = Join-Path $testRoot 'wsl'
            HasPowerShell = $true
            Actions = [Collections.Generic.List[string]]::new()
        }
        $saveClientFile = ${function:Save-CfsClientFile}
        function Get-CfsWindowsClientPaths {
            $native.Actions.Add('HostPaths')
            @{ NuGetPaths = @(Join-Path $native.HostRoot 'NuGet.Config'); CargoHome = Join-Path $native.HostRoot 'cargo' }
        }
        function Get-CfsWslContext {
            param([string]$Distribution)
            $native.Actions.Add("WslContext:$Distribution")
            @{
                NuGetPaths = @(Join-Path $native.WslRoot 'NuGet.Config')
                CargoHome = Join-Path $native.WslRoot 'cargo'
                HasPowerShell = $native.HasPowerShell
            }
        }
        function Save-CfsClientFile {
            param([string]$Path, [string]$Content)
            Assert-True ($Path.StartsWith($resolvedTestRoot + [IO.Path]::DirectorySeparatorChar, [StringComparison]::OrdinalIgnoreCase)) 'Native test attempted a host file write.'
            $native.Actions.Add("Save:$Path")
            & $saveClientFile -Path $Path -Content $Content
        }
        function Set-CfsPowerShellRepositories { $native.Actions.Add('HostRepositories') }
        function Set-CfsWslPowerShellRepositories {
            param([string]$Distribution)
            $native.Actions.Add("WslRepositories:$Distribution")
        }

        $userEnvironment.Clear()
        $machineEnvironment.Clear()
        $writes.Clear()
        Assert-Throws { Invoke-CfsSetup -WslDistribution 'Test Linux' -Confirm:$false | Out-Null } 'requires -ConfigureClients'
        Assert-True ($writes.Count -eq 0 -and $native.Actions.Count -eq 0) 'Invalid WSL options performed work.'
        Invoke-CfsSetup -ConfigureClients -WslDistribution 'Test Linux' -WhatIf | Out-Null
        Assert-True ($writes.Count -eq 0 -and $native.Actions.Count -eq 0 -and
            -not (Test-Path -LiteralPath $native.HostRoot) -and -not (Test-Path -LiteralPath $native.WslRoot)) 'Native WhatIf performed file, environment, WSL, or repository actions.'

        [void][IO.Directory]::CreateDirectory((Join-Path $native.HostRoot 'cargo'))
        $conflictPath = Join-Path $native.HostRoot 'cargo\config.toml'
        [IO.File]::WriteAllText($conflictPath, '[source.private]')
        Assert-Throws { Invoke-CfsSetup -ConfigureClients -Confirm:$false | Out-Null } 'already has source configuration'
        Assert-True ($writes.Count -eq 0 -and -not (Test-Path -LiteralPath (Join-Path $native.HostRoot 'NuGet.Config')) -and
            -not ($native.Actions -contains 'HostRepositories')) 'Conflict preflight performed mutations.'
        [IO.File]::WriteAllText($conflictPath, $cargoOriginal)

        $native.Actions.Clear()
        $userEnvironment['WSLENV'] = 'KEEP/pl:npM_CONFIG_REGISTRY/p:UV_DEFAULT_INDEX/u:ALSO_KEEP/w:apex_pip_index_host_path/l:PIP_INDEX_URL/p'
        Invoke-CfsSetup -ConfigureClients -Confirm:$false | Out-Null
        $expectedFeeds = [ordered]@{
            APEX_NPM_REGISTRY_HOST_PATH = 'packagefeedproxy.microsoft.io/npm/'
            APEX_PIP_INDEX_HOST_PATH = 'packagefeedproxy.microsoft.io/pypi/simple/'
            APEX_POWERSHELL_REPOSITORY_URL = 'https://packagefeedproxy.microsoft.io/powershell/v2'
            NPM_CONFIG_REGISTRY = 'https://packagefeedproxy.microsoft.io/npm/'
            PIP_INDEX_URL = 'https://packagefeedproxy.microsoft.io/pypi/simple/'
            UV_DEFAULT_INDEX = 'https://packagefeedproxy.microsoft.io/pypi/simple/'
        }
        foreach ($feed in $expectedFeeds.GetEnumerator()) {
            Assert-True ($userEnvironment[$feed.Key] -ceq $feed.Value) "Native feed mismatch: $($feed.Key)"
        }
        Assert-True ($writes.Count -eq 7) 'Native setup should persist exactly six feeds plus WSLENV.'
        $expectedWslEnv = (@('KEEP/pl', 'ALSO_KEEP/w') + @($expectedFeeds.Keys)) -join ':'
        Assert-True ($userEnvironment['WSLENV'] -ceq $expectedWslEnv) 'Native forwarding lost unrelated flags or retained flagged/duplicate feed names.'
        Assert-True (@($native.Actions | Where-Object { $_ -like 'Save:*' }).Count -eq 2 -and
            @($native.Actions | Where-Object { $_ -eq 'HostRepositories' }).Count -eq 1) 'Host clients should be configured once per invocation.'
        Assert-True (@($native.Actions | Where-Object { $_ -like 'Wsl*' }).Count -eq 0 -and
            -not (Test-Path -LiteralPath $native.WslRoot)) 'Host-only setup accessed WSL.'
        Assert-True ([IO.File]::ReadAllText($conflictPath) -ceq $cargo) 'Host Cargo configuration was not saved.'
        Assert-True ([IO.File]::ReadAllText("$conflictPath.cfs.bak") -ceq $cargoOriginal) 'Native setup lost original Cargo backup.'
        $hostNuget = Join-Path $native.HostRoot 'NuGet.Config'
        Assert-True (([xml][IO.File]::ReadAllText($hostNuget)).configuration.packageSources.add.key -ceq 'CFS') 'Host NuGet configuration was not saved.'

        $native.Actions.Clear()
        $writes.Clear()
        Invoke-CfsSetup -ConfigureClients -WslDistribution 'Test Linux' -Confirm:$false | Out-Null
        Assert-True (@($native.Actions | Where-Object { $_ -ceq 'WslContext:Test Linux' }).Count -eq 1 -and
            @($native.Actions | Where-Object { $_ -ceq 'WslRepositories:Test Linux' }).Count -eq 1) 'Selected WSL distribution/pwsh setup mismatch.'
        Assert-True ((Test-Path -LiteralPath (Join-Path $native.WslRoot 'NuGet.Config')) -and
            (Test-Path -LiteralPath (Join-Path $native.WslRoot 'cargo\config.toml'))) 'Selected WSL client files were not saved.'
        Assert-True ($userEnvironment['WSLENV'] -ceq $expectedWslEnv -and
            -not (Test-Path -LiteralPath "$hostNuget.cfs.bak")) 'Native rerun changed forwarding or backed up unchanged content.'

        $native.HasPowerShell = $false
        $native.Actions.Clear()
        $warnings = @()
        Invoke-CfsSetup -ConfigureClients -WslDistribution 'Test Linux' -Confirm:$false -WarningVariable warnings -WarningAction SilentlyContinue | Out-Null
        Assert-True (@($warnings | Where-Object { $_ -match "Test Linux.*no pwsh" }).Count -eq 1 -and
            @($native.Actions | Where-Object { $_ -like 'WslRepositories:*' }).Count -eq 0) 'Missing WSL pwsh should warn once and skip repository setup.'
        Assert-True (@($native.Actions | Where-Object { $_ -like 'Save:*' }).Count -eq 4) 'Missing WSL pwsh must not skip file configuration.'

        # A Linux conflict must also be detected before Windows settings are saved.
        [IO.File]::WriteAllText((Join-Path $native.WslRoot 'cargo\config.toml'), '[source.private]')
        $native.Actions.Clear()
        $writes.Clear()
        Assert-Throws { Invoke-CfsSetup -ConfigureClients -WslDistribution 'Test Linux' -Confirm:$false | Out-Null } 'already has source configuration'
        Assert-True ($writes.Count -eq 0 -and
            @($native.Actions | Where-Object { $_ -like 'Save:*' -or $_ -like '*Repositories*' }).Count -eq 0) 'WSL conflict preflight changed environment, files, or repositories.'
    }
} finally {
    if ((Resolve-Path -LiteralPath $testRoot).ProviderPath -cne $resolvedTestRoot) {
        throw 'Refusing cleanup because the test directory resolved to a different path.'
    }
    Remove-Item -LiteralPath $resolvedTestRoot -Recurse -Force
}

Write-Output 'CFS persistence, native transforms/backups, repository trust, WSL selection, dry-run/preflight safety, and rerun tests passed.'
