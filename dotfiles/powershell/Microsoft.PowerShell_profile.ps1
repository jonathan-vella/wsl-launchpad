$localProfile = Join-Path (Split-Path $PROFILE) 'profile.local.ps1'
if (Test-Path -LiteralPath $localProfile) {
    . $localProfile
}
