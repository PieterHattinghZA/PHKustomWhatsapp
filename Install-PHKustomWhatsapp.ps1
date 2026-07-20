<#
.SYNOPSIS
    Installs PHKustomWhatsapp 4.0.0 for the current user or all users.

.DESCRIPTION
    Copies the manifest, module, private implementation files and GUI to a
    versioned Windows PowerShell module directory. AllUsers installation
    self-elevates when required and validates the installed manifest.

.NOTES
    Author  : Pieter Hattingh
    Date    : 20/07/2026
    Version : 4.0.0
#>

[CmdletBinding()]
param(
    [ValidateSet('CurrentUser','AllUsers')]
    [string]$Scope = 'CurrentUser'
)

$ErrorActionPreference = 'Stop'
$moduleName = 'PHKustomWhatsapp'
$moduleVersion = '4.0.0'

if ($Scope -eq 'AllUsers') {
    $principal = New-Object Security.Principal.WindowsPrincipal([Security.Principal.WindowsIdentity]::GetCurrent())
    if (-not $principal.IsInRole([Security.Principal.WindowsBuiltInRole]::Administrator)) {
        Write-Host 'Requesting administrator privileges for an all-users installation...' -ForegroundColor Yellow
        $arguments = '-NoProfile -ExecutionPolicy RemoteSigned -File "{0}" -Scope AllUsers' -f $PSCommandPath
        Start-Process -FilePath 'powershell.exe' -ArgumentList $arguments -Verb RunAs -Wait
        return
    }
    $modulesRoot = Join-Path $env:ProgramFiles 'WindowsPowerShell\Modules'
}
else {
    $modulesRoot = Join-Path ([Environment]::GetFolderPath('MyDocuments')) 'WindowsPowerShell\Modules'
}

$destination = Join-Path (Join-Path $modulesRoot $moduleName) $moduleVersion
$requiredFiles = @(
    'PHKustomWhatsapp.psm1',
    'PHKustomWhatsapp.psd1',
    'simple-gui.ps1',
    'Private\Configuration.ps1',
    'Private\ApiClient.ps1'
)

foreach ($relativePath in $requiredFiles) {
    $source = Join-Path $PSScriptRoot $relativePath
    if (-not (Test-Path -LiteralPath $source -PathType Leaf)) {
        throw "Required source file not found: $source"
    }
}

try {
    New-Item -Path $destination -ItemType Directory -Force | Out-Null
    New-Item -Path (Join-Path $destination 'Private') -ItemType Directory -Force | Out-Null
    foreach ($relativePath in $requiredFiles) {
        Copy-Item -LiteralPath (Join-Path $PSScriptRoot $relativePath) -Destination (Join-Path $destination $relativePath) -Force
    }

    $helpSource = Join-Path $PSScriptRoot 'en-US'
    if (Test-Path -LiteralPath $helpSource -PathType Container) {
        Copy-Item -LiteralPath $helpSource -Destination $destination -Recurse -Force
    }

    $installedManifest = Join-Path $destination 'PHKustomWhatsapp.psd1'
    Test-ModuleManifest -Path $installedManifest -ErrorAction Stop | Out-Null
    Import-Module $installedManifest -Force -ErrorAction Stop
    Write-Host "PHKustomWhatsapp $moduleVersion installed successfully:" -ForegroundColor Green
    Write-Host $destination -ForegroundColor Cyan
}
catch {
    Write-Error ('Installation failed: {0}' -f $_.Exception.Message)
    throw
}
