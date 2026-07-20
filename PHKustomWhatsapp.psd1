@{
    RootModule        = 'PHKustomWhatsapp.psm1'
    ModuleVersion     = '4.0.0'
    GUID              = 'd2e7a1b2-8c4e-4e2a-9b7a-1a2b3c4d5e6f'
    Author            = 'Pieter Hattingh'
    CompanyName       = 'PHKustom'
    Copyright         = 'Copyright (c) 2025-2026 Pieter Hattingh'
    Description       = 'PowerShell 5.1 Green API messaging toolkit with protected credentials, resilient API calls, active chats, media and a two-column Windows Forms client.'
    PowerShellVersion = '5.1'
    RequiredModules   = @()
    FunctionsToExport = @(
        'New-WhatsappConfigFile','Get-WhatsappConfig','Clear-WhatsappLocalData',
        'Send-Whatsapp','Send-WhatsappFileByUpload','Send-WhatsappFileByUrl',
        'Send-WhatsappLocation','Send-WhatsappContact','Get-LastIncomingMessages',
        'Get-LastOutgoingMessages','Get-ChatHistory','Set-ChatRead','Get-WhatsappFile',
        'Get-WhatsappChats','Get-Contacts','Test-WhatsappAvailability',
        'Get-WhatsappInstanceStatus','Get-WhatsappMessageStatus',
        'Receive-WhatsappNotification','Remove-WhatsappNotification',
        'Get-WhatsappSettings','Set-WhatsappSettings','Get-WhatsappInstanceState',
        'Restart-WhatsappInstance','Disconnect-WhatsappInstance','Get-WhatsappQrCode',
        'Get-WhatsappAuthorizationCode','Set-WhatsappProfilePicture',
        'Update-WhatsappApiToken','Get-WhatsappWaAccountInfo','Send-WhatsappPoll',
        'Send-WhatsappForwardedMessage','Send-WhatsappInteractiveButtons',
        'Send-WhatsappTypingNotification','Get-WhatsappChatMessage',
        'Get-WhatsappMessagesCount','Get-WhatsappMessagesQueue',
        'Clear-WhatsappMessagesQueue','Get-WhatsappWebhooksCount',
        'Clear-WhatsappWebhooksQueue','New-WhatsappGroup','Set-WhatsappGroupName',
        'Get-WhatsappGroupData','Add-WhatsappGroupParticipant',
        'Remove-WhatsappGroupParticipant','Set-WhatsappGroupAdmin',
        'Remove-WhatsappGroupAdmin','Set-WhatsappGroupPicture','Exit-WhatsappGroup',
        'Send-WhatsappVoiceStatus','Send-WhatsappMediaStatus',
        'Get-LocalChatHistory','Save-LocalChatMessage'
    )
    CmdletsToExport   = @()
    VariablesToExport = @()
    AliasesToExport   = @()
    PrivateData = @{
        PSData = @{
            Tags         = @('GreenAPI','Messaging','Automation','PowerShell','WindowsForms')
            LicenseUri   = 'https://github.com/PieterHattinghZA/PHKustomWhatsapp/blob/main/LICENSE.md'
            ProjectUri   = 'https://github.com/PieterHattinghZA/PHKustomWhatsapp'
            ReleaseNotes = '4.0.0: protected credentials, secured local data, resilient API client, active-chat GUI, media support, tests and CI.'
        }
    }
}
