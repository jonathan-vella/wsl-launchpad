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

Write-Output 'CFS feed persistence, WSL forwarding, preservation, reruns, dry-run safety, and failure tests passed.'
