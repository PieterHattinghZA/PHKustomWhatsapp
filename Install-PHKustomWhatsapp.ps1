# Install script for PHKustomWhatsapp module
# Dynamically determines install and config paths

$moduleName = 'PHKustomWhatsapp'
$moduleSource = Join-Path $PSScriptRoot 'PHKustomWhatsapp.psm1'
$modulesRoot = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'
$moduleDestDir = Join-Path $modulesRoot $moduleName
$moduleDest = Join-Path $moduleDestDir 'PHKustomWhatsapp.psm1'

# Check if source file exists
if (-not (Test-Path $moduleSource)) {
    Write-Error "Module source file not found: $moduleSource. Please run this script from the original source folder."
    return
}

# Create module directory if needed
if (-not (Test-Path $moduleDestDir)) {
    New-Item -Path $moduleDestDir -ItemType Directory -Force | Out-Null
}

# Prevent copying if source and destination are the same
if ($moduleSource -ne $moduleDest) {
    Copy-Item -Path $moduleSource -Destination $moduleDest -Force
    Write-Host "Module installed to $moduleDestDir" -ForegroundColor Green
} else {
    Write-Host "Module source and destination are the same. Skipping copy." -ForegroundColor Yellow
}

# Set up config path (dynamic, per-user)
$configDir = Join-Path $env:APPDATA 'PHWhatsapp'
$configFile = Join-Path $configDir 'config.json'

if (-not (Test-Path $configDir)) {
    New-Item -Path $configDir -ItemType Directory -Force | Out-Null
}

if (-not (Test-Path $configFile)) {
    Write-Host "Creating WhatsApp config file at $configFile ..." -ForegroundColor Cyan
    Import-Module $moduleDest -Force
    New-WhatsappConfigFile
} else {
    Write-Host "Config file already exists at $configFile" -ForegroundColor Yellow
}
