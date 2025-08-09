@{
    # Script module or binary module file associated with this manifest
    RootModule        = 'PHKustomWhatsapp.psm1'

    # Version number of this module.
    ModuleVersion     = '3.4.0'

    # ID used to uniquely identify this module
    GUID              = 'd2e7a1b2-8c4e-4e2a-9b7a-1a2b3c4d5e6f'

    # Author of this module
    Author            = 'Pieter Hattingh'

    # Company or vendor of this module
    CompanyName       = 'Blikbrein Pyn'

    # Copyright statement for this module
    Copyright         = 'Copyright (c) 2025 Pieter Hattingh'

    # Description of the functionality provided by this module
    Description       = 'WhatsApp automation and reporting toolkit using Green API. Provides messaging, media, status, contact, and group management.'

    # Minimum version of the Windows PowerShell engine required by this module
    PowerShellVersion = '5.1'

    # Modules that must be imported into the global environment prior to importing this module
    RequiredModules   = @('ImportExcel')

    # Functions to export from this module
    FunctionsToExport = '*'

    # Cmdlets to export from this module
    CmdletsToExport   = @()

    # Variables to export from this module
    VariablesToExport = @()

    # Aliases to export from this module
    AliasesToExport  = @()

    # Private data to pass to the module specified in RootModule
    PrivateData      = @{
        PSData = @{
            Tags = @('WhatsApp','GreenAPI','Messaging','Automation','PowerShell')
            LicenseUri = 'https://opensource.org/licenses/MIT'
            ProjectUri = 'https://github.com/PieterHattinghZA/Scripts-and-Automate'
            ReleaseNotes = 'Initial module release. All major WhatsApp/Green API functions included.'
        }
    }
}
