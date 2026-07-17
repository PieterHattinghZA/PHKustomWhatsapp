# Install script for PHKustomWhatsapp module
# Dynamically determines install paths and elevates permissions if needed

[CmdletBinding()]
param(
    [Parameter(Mandatory = $false)]
    [ValidateSet('CurrentUser', 'AllUsers')]
    [string]$Scope = 'CurrentUser'
)

$moduleName = 'PHKustomWhatsapp'

# Determine destination path based on Scope
if ($Scope -eq 'AllUsers') {
    # Ensure running as Administrator to write to Program Files
    $isAdmin = ([Security.Principal.WindowsPrincipal][Security.Principal.WindowsIdentity]::GetCurrent()).IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)
    if (-not $isAdmin) {
        Write-Host "Requesting Administrator privileges to install the module system-wide..." -ForegroundColor Yellow
        Start-Process powershell.exe -ArgumentList "-NoProfile -ExecutionPolicy Bypass -File `"$PSCommandPath`" -Scope AllUsers" -Verb RunAs
        Exit
    }
    $modulesRoot = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'
} else {
    # CurrentUser scope
    $documentsDir = [Environment]::GetFolderPath('MyDocuments')
    $modulesRoot = Join-Path $documentsDir 'WindowsPowerShell\Modules'
}

$moduleDestDir = Join-Path $modulesRoot $moduleName

# Check if source files exist
$sourcePsm1 = Join-Path $PSScriptRoot 'PHKustomWhatsapp.psm1'
$sourcePsd1 = Join-Path $PSScriptRoot 'PHKustomWhatsapp.psd1'
$sourceHelpDir = Join-Path $PSScriptRoot 'en-US'

if (-not (Test-Path $sourcePsm1)) {
    Write-Error "Module source file not found: $sourcePsm1. Please run this script from the original source folder."
    if ($Scope -eq 'AllUsers') {
        # Keep window open if elevated process was spawned
        Read-Host "Press Enter to exit"
    }
    return
}

# Create module directory if needed
if (-not (Test-Path $moduleDestDir)) {
    try {
        New-Item -Path $moduleDestDir -ItemType Directory -Force | Out-Null
    } catch {
        Write-Error "Failed to create directory ${moduleDestDir}: $($_.Exception.Message)"
        if ($Scope -eq 'AllUsers') { Read-Host "Press Enter to exit" }
        return
    }
}

# Copy .psm1 file
try {
    Copy-Item -Path $sourcePsm1 -Destination (Join-Path $moduleDestDir 'PHKustomWhatsapp.psm1') -Force
    Write-Host "Copied module file to $moduleDestDir" -ForegroundColor Cyan
} catch {
    Write-Error "Failed to copy module file: $($_.Exception.Message)"
    if ($Scope -eq 'AllUsers') { Read-Host "Press Enter to exit" }
    return
}

# Copy .psd1 file if it exists
if (Test-Path $sourcePsd1) {
    try {
        Copy-Item -Path $sourcePsd1 -Destination (Join-Path $moduleDestDir 'PHKustomWhatsapp.psd1') -Force
        Write-Host "Copied manifest file to $moduleDestDir" -ForegroundColor Cyan
    } catch {
        Write-Error "Failed to copy manifest file: $($_.Exception.Message)"
    }
}

# Copy help folder if it exists
if (Test-Path $sourceHelpDir) {
    $destHelpDir = Join-Path $moduleDestDir 'en-US'
    if (-not (Test-Path $destHelpDir)) {
        try {
            New-Item -Path $destHelpDir -ItemType Directory -Force | Out-Null
        } catch {
            Write-Error "Failed to create help directory $destHelpDir"
        }
    }
    try {
        Copy-Item -Path "$sourceHelpDir\*" -Destination $destHelpDir -Force
        Write-Host "Copied help folder to $destHelpDir" -ForegroundColor Cyan
    } catch {
        Write-Error "Failed to copy help files: $($_.Exception.Message)"
    }
}

Write-Host "PHKustomWhatsapp module installed successfully to $moduleDestDir" -ForegroundColor Green

if ($Scope -eq 'AllUsers') {
    # Keep window open for verification when running in elevated pop-up window
    Read-Host "Press Enter to exit"
}