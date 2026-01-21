#Requires -RunAsAdministrator

$minVersion = "7.4.0"
$pwshPath = Get-Command -Name "pwsh" -ErrorAction SilentlyContinue

if ($null -ne $pwshPath) {
    $currentVersion = (pwsh -Command "$PSVersionTable.PSVersion").ToString()
    if ([version]$currentVersion -lt [version]$minVersion) {
        Write-Host "PowerShell 7 is outdated ($currentVersion). Upgrading..."
        winget upgrade --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --silent
    } else {
        Write-Host "PowerShell 7 is already up to date (version $currentVersion)."
    }
} else {
    Write-Host "PowerShell 7 is not installed. Installing..."
    winget install --id Microsoft.PowerShell --source winget --accept-package-agreements --accept-source-agreements --silent
}