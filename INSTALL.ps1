# Installer for PHKustomWhatsapp PowerShell Module
# Usage: Run this script in PowerShell to copy the module to your user profile

$ModuleSource = Join-Path (Get-Location).Path 'PHKustomWhatsapp.psm1'
$ModuleTar1 = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\PHKustomWhatsapp"
$ModuleTar2 = "C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules\PHKustomWhatsapp"
$ModuleDest1 = "$env:USERPROFILE\Documents\WindowsPowerShell\Modules\PHKustomWhatsapp"
$ModuleDest2 = "C:\WINDOWS\system32\WindowsPowerShell\v1.0\Modules\PHKustomWhatsapp"

if (!(Test-Path $ModuleTar1)) {
    New-Item -Path $ModuleTar1 -ItemType Directory -Force | Out-Null
}
if (!(Test-Path $ModuleTar2)) {
    New-Item -Path $ModuleTar2 -ItemType Directory -Force | Out-Null
}


Copy-Item -Path $ModuleSource -Destination $Moduletar1 -Force
Write-Host "PHKustomWhatsapp module installed to $Moduletar1"

Copy-Item -Path $ModuleSource -Destination $Moduletar2 -Force
Write-Host "PHKustomWhatsapp module installed to $Moduletar2"
