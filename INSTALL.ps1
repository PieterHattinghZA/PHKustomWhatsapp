# Installer for PHKustomWhatsapp PowerShell Module
# Usage: Run this script in PowerShell to copy the module to your user profile

$ModuleSource = "$(Split-Path -Parent $MyInvocation.MyCommand.Path)\PHKustomWhatsapp.psm1"
$ModuleDest = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\PHKustomWhatsapp\PHKustomWhatsapp.psm1"

if (!(Test-Path "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\PHKustomWhatsapp")) {
    New-Item -Path "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\PHKustomWhatsapp" -ItemType Directory -Force | Out-Null
}

Copy-Item -Path $ModuleSource -Destination $ModuleDest -Force
Write-Host "PHKustomWhatsapp module installed to $ModuleDest"
