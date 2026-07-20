<#
.SYNOPSIS
WhatsApp automation and reporting toolkit using Green API.
Author: Pieter Hattingh
Version: 4.1.0
Description: PowerShell module for WhatsApp messaging, media, status, and contact management via Green API.
             All config variables are loaded from an external JSON file ($env:APPDATA\PHWhatsapp\config.json).
             Robust error handling and clear error messages included.
             Includes: TLS 1.2 enforcement, variable clearing at script start.
#>

# --- Global Configuration Variables (Loaded from external file) ---
$global:InstanceId = $null
$global:Token = $null
$global:BaseUrl = $null

# --- Dynamic config path (per-user, not hardcoded) ---
$script:ConfigDir = Join-Path $env:APPDATA 'PHWhatsapp'
$script:ConfigFilePath = Join-Path $script:ConfigDir 'config.json'
$script:LogDir = Join-Path $script:ConfigDir 'Logs'

# --- Ensure TLS 1.2 for secure communication ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12

# --- Load private implementation files ---
$privateFiles = @('Configuration.ps1', 'ApiClient.ps1')
foreach ($privateFile in $privateFiles) {
    $privatePath = Join-Path (Join-Path $PSScriptRoot 'Private') $privateFile
    if (-not (Test-Path -LiteralPath $privatePath -PathType Leaf)) {
        throw "Required private module file not found: $privatePath"
    }
    . $privatePath
}
Initialize-WhatsappDataDirectory

function Clear-WhatsappFunctions {
    <#
    .SYNOPSIS
    Removes all functions defined in this module from the current session.
    .DESCRIPTION
    This function removes all WhatsApp-related functions from the session to allow for a clean reload or update.
    #>
    $functionNames = @( 
        'New-WhatsappConfigFile',
        'Clear-WhatsappLocalData',
        'Get-WhatsappConfig',
        'Get-WhatsappContactInfo',
        'Export-WhatsappChat',
        'Save-WhatsappChatMedia',
        'Format-WhatsappNumber',
        'Format-PlainNumber',
        'Send-Whatsapp',
        'Send-WhatsappFileByUpload',
        'Send-WhatsappFileByUrl',
        'Send-WhatsappLocation',
        'Send-WhatsappContact',
        'Get-LastIncomingMessages',
        'Get-LastOutgoingMessages',
        'Get-ChatHistory',
        'Set-ChatRead',
        'Get-WhatsappFile',
        'Get-Contacts',
        'Test-WhatsappAvailability',
        'Get-WhatsappInstanceStatus',
        'Get-WhatsappMessageStatus',
        'Receive-WhatsappNotification',
        'Remove-WhatsappNotification',
        'Get-WhatsappSettings',
        'Set-WhatsappSettings',
        'Get-WhatsappInstanceState',
        'Restart-WhatsappInstance',
        'Disconnect-WhatsappInstance',
        'Get-WhatsappQrCode',
        'Get-WhatsappAuthorizationCode',
        'Set-WhatsappProfilePicture',
        'Update-WhatsappApiToken',
        'Get-WhatsappWaAccountInfo',
        'Send-WhatsappPoll',
        'Send-WhatsappForwardedMessage',
        'Send-WhatsappInteractiveButtons',
        'Send-WhatsappTypingNotification',
        'Get-WhatsappChatMessage',
        'Get-WhatsappMessagesCount',
        'Get-WhatsappMessagesQueue',
        'Clear-WhatsappMessagesQueue',
        'Get-WhatsappWebhooksCount',
        'Clear-WhatsappWebhooksQueue',
        'New-WhatsappGroup',
        'Set-WhatsappGroupName',
        'Get-WhatsappGroupData',
        'Add-WhatsappGroupParticipant',
        'Remove-WhatsappGroupParticipant',
        'Set-WhatsappGroupAdmin',
        'Remove-WhatsappGroupAdmin',
        'Set-WhatsappGroupPicture',
        'Exit-WhatsappGroup',
        'Send-WhatsappVoiceStatus',
        'Send-WhatsappMediaStatus',
        'Get-LocalChatHistory',
        'Save-LocalChatMessage'
    )
    foreach ($fn in $functionNames) {
        if (Get-Command $fn -ErrorAction SilentlyContinue) {
            Remove-Item "function:$fn" -ErrorAction SilentlyContinue
        }
    }
    Write-Host "All WhatsApp functions have been removed from memory." -ForegroundColor Yellow
}

# Load protected configuration when the module is imported.
if ($MyInvocation.InvocationName -ne '.') {
    Get-WhatsappConfig | Out-Null
}

function Format-WhatsappNumber {
    <#
    .SYNOPSIS
    Formats a phone number into the Green API's chatId format (e.g., 27731234567@c.us).
    .DESCRIPTION
    This function takes a phone number as input and cleans it by removing non-numeric characters.
    It then prefixes it with "27" if it starts with "0" or if it's a 9-digit number without an international prefix.
    Finally, it appends "@c.us" to create the Green API chatId.
    An optional -ReturnChatId parameter allows returning just the plain formatted number without "@c.us".
    .PARAMETER Number
    The phone number to format (e.g., "0737443501", "27737443501").
    .PARAMETER ReturnChatId
    If $true (default), returns the full chatId (e.g., "27737443501@c.us").
    If $false, returns only the plain formatted number (e.g., "27737443501").
    .EXAMPLE
    Format-WhatsappNumber -Number "0737443501"
    # Returns: "27737443501@c.us"

    .EXAMPLE
    Format-WhatsappNumber -Number "27737443501" -ReturnChatId $false
    # Returns: "27737443501"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$Number,

        [Parameter(Mandatory = $false)]
        [bool]$ReturnChatId = $true
    )

    $cleanedNumber = $Number -replace '[^0-9]', ''

    # Check for South African specific formatting (starts with 0 or is 9 digits without 27)
    if ($cleanedNumber.StartsWith("0")) {
        $cleanedNumber = "27" + $cleanedNumber.Substring(1)
    } elseif ($cleanedNumber.Length -eq 9 -and -not $cleanedNumber.StartsWith("27")) {
        # Assuming 9 digits implies a missing '0' and needs '27' prefix for SA numbers
        $cleanedNumber = "27" + $cleanedNumber
    }
    # If it's already 27... or other international format, leave it as is.

    if ($ReturnChatId) {
        return "$cleanedNumber@c.us"
    } else {
        return $cleanedNumber
    }
}

function Format-PlainNumber {
    <#
    .SYNOPSIS
    Normalizes a phone input to a plain international number for WhatsApp API calls
    (NO '@c.us' suffix ever).

    .DESCRIPTION
    - Strips '@c.us'/'@g.us' if present.
    - Removes spaces, dashes, brackets, and '+'.
    - Converts '00' international prefix to plain digits.
    - If number starts with a local '0', replaces it with -DefaultCountryCode (default: 27).

    .PARAMETER Number
    The input (e.g. "073 123 4567", "+27 73 123 4567", "27731234567@c.us").

    .PARAMETER DefaultCountryCode
    Country code to apply when a local leading '0' is detected. Default = '27'.

    .EXAMPLE
    ConvertTo-WhatsappNumber -Number "073 123 4567"
    # -> 27731234567

    .EXAMPLE
    ConvertTo-WhatsappNumber -Number "27731234567@c.us"
    # -> 27731234567

    .EXAMPLE
    ConvertTo-WhatsappNumber -Number "+27 (73) 123-4567"
    # -> 27731234567
    #>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory=$true)]
        [string]$Number,

        [ValidatePattern('^\d+$')]
        [string]$DefaultCountryCode = '27'
    )

    # Trim & remove chat/group suffixes
    $n = $Number.Trim()
    $n = $n -replace '@c\.us$','' -replace '@g\.us$',''

    # Keep digits and plus only, then normalize prefixes
    $n = $n -replace '[^\d\+]',''      # remove spaces, dashes, (), etc.
    if ($n.StartsWith('+')) { $n = $n.Substring(1) }
    if ($n.StartsWith('00')) { $n = $n.Substring(2) }

    # If it starts with a local leading zero, swap it with the default country code
    if ($n -match '^[0]\d+$') {
        $n = $DefaultCountryCode + $n.Substring(1)
    }

    # Final sanity: digits only
    $n = $n -replace '[^\d]',''

    if (-not $n) {
        throw "Unable to normalize phone number from input: '$Number'"
    }

    return $n
}

function Send-Whatsapp {
<#
    .SYNOPSIS
    Sends a WhatsApp text message.
    .DESCRIPTION
    This function sends a plain text message to a specified WhatsApp contact or group chat.
    It automatically formats the phone number to the Green API's chatId format.
    .PARAMETER Number
    The recipient's phone number (e.g., "0731234567").
    .PARAMETER ChatId
    The recipient's chat ID (e.g., "27731234567@c.us" or "group_id@g.us").
    One of -Number or -ChatId is mandatory. If both are provided, -ChatId takes precedence.
    .PARAMETER Message
    The text content of the message to send.
    .EXAMPLE
    Send-Whatsapp -Number "0731234567" -Message "Hello from PowerShell!"
    .EXAMPLE
    Send-Whatsapp -ChatId "27731234567@c.us" -Message "Hello again!"
    #>
param(
        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$Number,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ChatId,

        [Parameter(Mandatory = $true)]
        [string]$Message
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $Number
    } else {
        $targetChatId = $ChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid number or chat ID provided."
        return $null
    }

    $Body = @{
        chatId = $targetChatId
        message = $Message
    }
    return Invoke-WhatsappApi -Endpoint "sendMessage" -Body $Body

}

function Send-WhatsappFileByUpload {
<#
    .SYNOPSIS
    Sends a WhatsApp media message by uploading a local file.
    .DESCRIPTION
    This function sends an image, video, document, or audio file from a local path
    to a specified WhatsApp contact or group chat.
    .PARAMETER Number
    The recipient's phone number (e.g., "0731234567").
    .PARAMETER ChatId
    The recipient's chat ID (e.g., "27731234567@c.us" or "group_id@g.us").
    One of -Number or -ChatId is mandatory. If both are provided, -ChatId takes precedence.
    .PARAMETER FilePath
    The full path to the local media file to upload.
    .PARAMETER Caption
    Optional caption for the media file.
    .EXAMPLE
    Send-WhatsappFileByUpload -Number "0731234567" -FilePath "C:\path\to\image.jpg" -Caption "My image"
    #>
param(
        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$Number,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ChatId,

        [Parameter(Mandatory = $true)]
        [string]$FilePath,

        [Parameter(Mandatory = $false)]
        [string]$Caption
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $Number
    } else {
        $targetChatId = $ChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid number or chat ID provided."
        return $null
    }

    if (-not (Test-Path $FilePath -PathType Leaf)) {
        Write-Error "File not found at '$FilePath'."
        return $null
    }

    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $base64File = [System.Convert]::ToBase64String($fileBytes)
    $fileName = [System.IO.Path]::GetFileName($FilePath)

    $Body = @{
        chatId = $targetChatId
        fileName = $fileName
        body = $base64File
    }
    if ($Caption) {
        $Body.caption = $Caption
    }
    return Invoke-WhatsappApi -Endpoint "sendFileByUpload" -Body $Body

}

function Send-WhatsappFileByUrl {
<#
    .SYNOPSIS
    Sends a WhatsApp media message by providing a URL to the file.
    .DESCRIPTION
    This function sends an image, video, document, or audio file located at a public URL
    to a specified WhatsApp contact or group chat.
    .PARAMETER Number
    The recipient's phone number (e.g., "0731234567").
    .PARAMETER ChatId
    The recipient's chat ID (e.g., "27731234567@c.us" or "group_id@g.us").
    One of -Number or -ChatId is mandatory. If both are provided, -ChatId takes precedence.
    .PARAMETER FileUrl
    The public URL of the media file.
    .PARAMETER FileName
    The name to give the file in WhatsApp (e.g., "my_document.pdf").
    .PARAMETER Caption
    Optional caption for the media file.
    .EXAMPLE
    Send-WhatsappFileByUrl -Number "0731234567" -FileUrl "https://example.com/image.png" -FileName "example.png" -Caption "Online image"
    #>
param(
        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$Number,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ChatId,

        [Parameter(Mandatory = $true)]
        [string]$FileUrl,

        [Parameter(Mandatory = $true)]
        [string]$FileName,

        [Parameter(Mandatory = $false)]
        [string]$Caption
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $Number
    } else {
        $targetChatId = $ChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid number or chat ID provided."
        return $null
    }

    $Body = @{
        chatId = $targetChatId
        urlFile = $FileUrl
        fileName = $FileName
    }
    if ($Caption) {
        $Body.caption = $Caption
    }
    return Invoke-WhatsappApi -Endpoint "sendFileByUrl" -Body $Body

}

function Send-WhatsappLocation {
<#
    .SYNOPSIS
    Sends a WhatsApp location message.
    .DESCRIPTION
    This function sends a geographical location to a specified WhatsApp contact.
    .PARAMETER Number
    The recipient's phone number (e.g., "0731234567").
    .PARAMETER ChatId
    The recipient's chat ID (e.g., "27731234567@c.us" or "group_id@g.us").
    One of -Number or -ChatId is mandatory. If both are provided, -ChatId takes precedence.
    .PARAMETER Latitude
    The latitude of the location.
    .PARAMETER Longitude
    The longitude of the location.
    .PARAMETER Name
    Optional name for the location (e.g., "My Office").
    .PARAMETER Address
    Optional address for the location.
    .EXAMPLE
    Send-WhatsappLocation -Number "0731234567" -Latitude -25.747868 -Longitude 28.229271 -Name "Pretoria" -Address "Gauteng, South Africa"
    #>
param(
        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$Number,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ChatId,

        [Parameter(Mandatory = $true)]
        [double]$Latitude,

        [Parameter(Mandatory = $true)]
        [double]$Longitude,

        [Parameter(Mandatory = $false)]
        [string]$Name,

        [Parameter(Mandatory = $false)]
        [string]$Address
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $Number
    } else {
        $targetChatId = $ChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid number or chat ID provided."
        return $null
    }

    $Body = @{
        chatId = $targetChatId
        latitude = $Latitude
        longitude = $Longitude
    }
    if ($Name) { $Body.nameLocation = $Name }
    if ($Address) { $Body.address = $Address }
    return Invoke-WhatsappApi -Endpoint "sendLocation" -Body $Body

}

function Send-WhatsappContact {
<#
    .SYNOPSIS
    Sends a WhatsApp contact card (vCard).
    .DESCRIPTION
    This function sends a contact card to a specified WhatsApp contact.
    .PARAMETER Number
    The recipient's phone number (e.g., "0731234567").
    .PARAMETER ChatId
    The recipient's chat ID (e.g., "27731234567@c.us" or "group_id@g.us").
    One of -Number or -ChatId is mandatory. If both are provided, -ChatId takes precedence.
    .PARAMETER ContactNumber
    The phone number of the contact to send (e.g., "27821234567").
    .PARAMETER ContactName
    Optional name for the contact to send.
    .EXAMPLE
    Send-WhatsappContact -Number "0731234567" -ContactNumber "27821234567" -ContactName "John Doe"
    #>
param(
        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$Number,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ChatId,

        [Parameter(Mandatory = $true)]
        [string]$ContactNumber,

        [Parameter(Mandatory = $false)]
        [string]$ContactName
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $Number
    } else {
        $targetChatId = $ChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid number or chat ID provided."
        return $null
    }

    $Body = @{
        chatId = $targetChatId
        contact = $ContactNumber
    }
    if ($ContactName) { $Body.name = $ContactName }
    return Invoke-WhatsappApi -Endpoint "sendContact" -Body $Body

}

function Get-LastIncomingMessages {
<#
    .SYNOPSIS
    Retrieves recent incoming WhatsApp messages.
    .DESCRIPTION
    This function fetches incoming messages from the last specified number of minutes.
    Requires incoming webhook settings to be enabled on your Green API instance.
    .PARAMETER Minutes
    The number of minutes back to retrieve messages from.
    .EXAMPLE
    Get-LastIncomingMessages -Minutes 5
    #>
param(
        [Parameter(Mandatory = $true)]
        [int]$Minutes
    )

    return Invoke-WhatsappApi -Endpoint "lastIncomingMessages" -Method "GET" -QueryParams @{ minutes = $Minutes }

}

function Get-LastOutgoingMessages {
<#
    .SYNOPSIS
    Retrieves recent outgoing WhatsApp messages.
    .DESCRIPTION
    This function fetches outgoing messages from the last specified number of minutes.
    Requires outgoing webhook settings to be enabled on your Green API instance.
    .PARAMETER Minutes
    The number of minutes back to retrieve messages from.
    .EXAMPLE
    Get-LastOutgoingMessages -Minutes 5
    #>
param(
        [Parameter(Mandatory = $true)]
        [int]$Minutes
    )

    return Invoke-WhatsappApi -Endpoint "lastOutgoingMessages" -Method "GET" -QueryParams @{ minutes = $Minutes }

}

function Get-ChatHistory {
<#
    .SYNOPSIS
    Retrieves chat history for a specific WhatsApp chat.
    .DESCRIPTION
    This function fetches a specified number of recent messages from a chat's history.
    .PARAMETER Number
    The phone number of the chat (e.g., "0731234567").
    .PARAMETER ChatId
    The chat ID (e.g., "27731234567@c.us" or "group_id@g.us").
    One of -Number or -ChatId is mandatory. If both are provided, -ChatId takes precedence.
    .PARAMETER Count
    The maximum number of messages to retrieve.
    .EXAMPLE
    Get-ChatHistory -Number "0731234567" -Count 10
    #>
param(
        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$Number,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ChatId,

        [Parameter(Mandatory = $true)]
        [int]$Count
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $Number
    } else {
        $targetChatId = $ChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid number or chat ID provided."
        return $null
    }

    $Body = @{
        chatId = $targetChatId
        count = $Count
    }
    return Invoke-WhatsappApi -Endpoint "getChatHistory" -Body $Body

}

function Export-WhatsappChat {
<#
    .SYNOPSIS
    Exports a chat history to a UTF-8 CSV file.

    .PARAMETER ChatId
    Chat identifier to export.

    .PARAMETER Path
    Full destination CSV path.

    .PARAMETER Count
    Maximum number of messages to request from Green API.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ChatId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$Path,
        [ValidateRange(1, 10000)][int]$Count = 1000
    )

    $destination = [IO.Path]::GetFullPath($Path)
    if ([IO.Path]::GetExtension($destination) -ne '.csv') {
        $destination += '.csv'
    }

    $directory = Split-Path -Parent $destination
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }

    $epoch = [DateTime]::SpecifyKind(
        [DateTime]::ParseExact('1970-01-01', 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture),
        [DateTimeKind]::Utc
    )

    $history = @(Get-ChatHistory -ChatId $ChatId -Count $Count)
    $rows = foreach ($message in ($history | Sort-Object { [int64]$_.timestamp })) {
        $messageTime = $null
        try { $messageTime = $epoch.AddSeconds([int64]$message.timestamp).ToLocalTime() }
        catch { Write-WhatsappLog -Level WARN -Message ('Invalid timestamp on message {0}: {1}' -f $message.idMessage, $_.Exception.Message) }

        [PSCustomObject][ordered]@{
            DateTime         = if ($messageTime) { $messageTime.ToString('yyyy-MM-dd HH:mm:ss') } else { '' }
            Direction        = [string]$message.type
            ChatId           = [string]$message.chatId
            SenderId         = [string]$message.senderId
            SenderName       = if ($message.senderContactName) { [string]$message.senderContactName } else { [string]$message.senderName }
            MessageId        = [string]$message.idMessage
            MessageType      = [string]$message.typeMessage
            Status           = [string]$message.statusMessage
            Text             = [string]$message.textMessage
            Caption          = [string]$message.caption
            FileName         = [string]$message.fileName
            MimeType         = [string]$message.mimeType
            DownloadUrl      = [string]$message.downloadUrl
            IsDeleted        = [bool]$message.isDeleted
            IsEdited         = [bool]$message.isEdited
        }
    }

    $rows | Export-Csv -LiteralPath $destination -NoTypeInformation -Encoding UTF8 -Force
    Write-WhatsappLog -Message ('Exported {0} messages from {1} to {2}.' -f @($rows).Count, $ChatId, $destination)
    return Get-Item -LiteralPath $destination
}

function Save-WhatsappChatMedia {
<#
    .SYNOPSIS
    Downloads every available media attachment from a chat history.

    .PARAMETER ChatId
    Chat identifier whose media should be downloaded.

    .PARAMETER DestinationPath
    Directory in which media files are saved.

    .PARAMETER Count
    Maximum number of messages to request from Green API.

    .PARAMETER Force
    Replaces existing files instead of skipping them.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$ChatId,
        [Parameter(Mandatory = $true)][ValidateNotNullOrEmpty()][string]$DestinationPath,
        [ValidateRange(1, 10000)][int]$Count = 1000,
        [switch]$Force
    )

    $destination = [IO.Path]::GetFullPath($DestinationPath)
    if (-not (Test-Path -LiteralPath $destination)) {
        New-Item -Path $destination -ItemType Directory -Force | Out-Null
    }

    $mediaTypes = @('imageMessage','videoMessage','documentMessage','audioMessage','stickerMessage')
    $history = @(Get-ChatHistory -ChatId $ChatId -Count $Count)
    $results = New-Object Collections.ArrayList

    foreach ($message in ($history | Where-Object { $mediaTypes -contains [string]$_.typeMessage })) {
        $downloadUrl = [string]$message.downloadUrl

        $extension = [IO.Path]::GetExtension([string]$message.fileName)
        if (-not $extension) {
            switch -Regex ([string]$message.mimeType) {
                '^image/jpeg' { $extension = '.jpg'; break }
                '^image/png'  { $extension = '.png'; break }
                '^image/gif'  { $extension = '.gif'; break }
                '^image/webp' { $extension = '.webp'; break }
                '^video/mp4'        { $extension = '.mp4'; break }
                '^video/quicktime'  { $extension = '.mov'; break }
                '^video/x-msvideo'  { $extension = '.avi'; break }
                '^video/x-matroska' { $extension = '.mkv'; break }
                '^video/webm'       { $extension = '.webm'; break }
                '^video/3gpp'       { $extension = '.3gp'; break }
                '^video/3gpp2'      { $extension = '.3g2'; break }
                '^audio/ogg'        { $extension = '.ogg'; break }
                '^audio/mpeg' { $extension = '.mp3'; break }
                default       { $extension = '.bin' }
            }
        }

        $originalName = [string]$message.fileName
        if ([string]::IsNullOrWhiteSpace($originalName)) { $originalName = 'media' + $extension }
        foreach ($invalidCharacter in [IO.Path]::GetInvalidFileNameChars()) {
            $originalName = $originalName.Replace([string]$invalidCharacter, '_')
        }
        $safeMessageId = [string]$message.idMessage
        foreach ($invalidCharacter in [IO.Path]::GetInvalidFileNameChars()) {
            $safeMessageId = $safeMessageId.Replace([string]$invalidCharacter, '_')
        }
        $fileName = '{0}_{1}' -f $safeMessageId, $originalName

        $filePath = Join-Path $destination $fileName
        if ((Test-Path -LiteralPath $filePath) -and -not $Force) {
            [void]$results.Add([PSCustomObject]@{
                MessageId = [string]$message.idMessage
                Path      = $filePath
                Status    = 'SkippedExisting'
                Error     = $null
            })
            continue
        }

        try {
            if (-not [string]::IsNullOrWhiteSpace($downloadUrl)) {
                Start-FileDownload -Uri $downloadUrl -OutFile $filePath -Description ('Downloading {0}' -f $fileName)
            }
            else {
                Get-WhatsappFile -ChatId $ChatId -MessageId ([string]$message.idMessage) -SavePath $filePath | Out-Null
            }
            [void]$results.Add([PSCustomObject]@{
                MessageId = [string]$message.idMessage
                Path      = $filePath
                Status    = 'Downloaded'
                Error     = $null
            })
        }
        catch {
            Write-WhatsappLog -Level ERROR -Message ('Media download failed for {0}: {1}' -f $message.idMessage, $_.Exception.Message)
            [void]$results.Add([PSCustomObject]@{
                MessageId = [string]$message.idMessage
                Path      = $filePath
                Status    = 'Failed'
                Error     = $_.Exception.Message
            })
        }
    }

    Write-WhatsappLog -Message ('Processed {0} media items from {1} into {2}.' -f $results.Count, $ChatId, $destination)
    return @($results)
}

function Set-ChatRead {
<#
    .SYNOPSIS
    Marks a WhatsApp chat as read.
    .DESCRIPTION
    This function sets the read status for a specified chat.
    .PARAMETER Number
    The phone number of the chat (e.g., "0731234567").
    .PARAMETER ChatId
    The chat ID (e.g., "27731234567@c.us" or "group_id@g.us").
    One of -Number or -ChatId is mandatory. If both are provided, -ChatId takes precedence.
    .EXAMPLE
    Set-ChatRead -Number "0731234567"
    #>
param(
        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$Number,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ChatId
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $Number
    } else {
        $targetChatId = $ChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid number or chat ID provided."
        return $null
    }

    return Invoke-WhatsappApi -Endpoint "readChat" -Body @{ chatId = $targetChatId }

}

function Start-FileDownload {
    param(
        [string]$Uri,
        [string]$OutFile,
        [string]$Description = "Downloading file"
    )

    $client = New-Object System.Net.Http.HttpClient
    try {
        $response = $client.GetAsync($Uri, [System.Net.Http.HttpCompletionOption]::ResponseHeadersRead).GetAwaiter().GetResult()
        if (-not $response.IsSuccessStatusCode) {
            throw "Failed to download ${Uri}: $($response.StatusCode) ($($response.ReasonPhrase))"
        }

        $totalBytes = $response.Content.Headers.ContentLength
        if ($null -eq $totalBytes) {
            $totalBytes = 0
        }

        $inputStream = $response.Content.ReadAsStreamAsync().GetAwaiter().GetResult()
        $outputStream = [System.IO.File]::Create($OutFile)
        $buffer = New-Object byte[] 65536
        $bytesRead = 0
        $totalRead = 0

        $localProgressPreference = if (Test-Path "variable:ProgressPreference") { $ProgressPreference } else { "Continue" }
        $ProgressPreference = "Continue"

        try {
            while (($bytesRead = $inputStream.Read($buffer, 0, $buffer.Length)) -gt 0) {
                $outputStream.Write($buffer, 0, $bytesRead)
                $totalRead += $bytesRead
                if ($totalBytes -gt 0) {
                    $percent = [Math]::Round(($totalRead / $totalBytes) * 100)
                    Write-Progress -Activity $Description -Status "$percent% complete ($([Math]::Round($totalRead / 1MB, 2)) MB of $([Math]::Round($totalBytes / 1MB, 2)) MB)" -PercentComplete $percent
                } else {
                    Write-Progress -Activity $Description -Status "Downloaded $([Math]::Round($totalRead / 1MB, 2)) MB (unknown total size)"
                }
            }
        } finally {
            Write-Progress -Activity $Description -Completed
            $ProgressPreference = $localProgressPreference
            $outputStream.Dispose()
            $inputStream.Dispose()
        }
    } finally {
        $client.Dispose()
    }
}

function Get-WhatsappFile {
<#
    .SYNOPSIS
    Gets a file from an incoming WhatsApp message.
    .DESCRIPTION
    This function gets a file (e.g., image, video, document) associated with a specific message ID
    to a local path.
    .PARAMETER ChatId
    The ID of the chat containing the file to get.
    .PARAMETER MessageId
    The ID of the message containing the file to get.
    .PARAMETER SavePath
    The full path including filename where the file should be saved (e.g., "C:\downloads\myimage.jpg").
    .EXAMPLE
    Get-WhatsappFile -ChatId "27731234567@c.us" -MessageId "ABCD12345" -SavePath "C:\temp\downloaded_file.jpg"
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$ChatId,

        [Parameter(Mandatory = $true)]
        [string]$MessageId,

        [Parameter(Mandatory = $true)]
        [string]$SavePath
    )

    $body = @{
        chatId = $ChatId
        idMessage = $MessageId
    }

    $response = Invoke-WhatsappApi -Endpoint "downloadFile" -Method "POST" -Body $body
    if ($response -and $response.downloadUrl) {
        Start-FileDownload -Uri $response.downloadUrl -OutFile $SavePath -Description "Downloading WhatsApp attachment"
        return $true
    } else {
        throw "Failed to retrieve download URL from Green API response: $($response | ConvertTo-Json -Depth 2 -Compress)"
    }

}

function Get-WhatsappChats {
<#
    .SYNOPSIS
    Retrieves the most recently active chats for the Green API instance.

    .DESCRIPTION
    Calls the Green API getChats service method. Results are returned in chat
    activity order and include the chat ID, name, type and archive state.

    .PARAMETER Count
    Maximum number of active chats to return.

    .EXAMPLE
    Get-WhatsappChats -Count 100
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 500)]
        [int]$Count = 100
    )

    return Invoke-WhatsappApi -Endpoint "getChats" -Method "GET" -QueryParams @{ count = $Count }
}

function Get-WhatsappContactInfo {
<#
    .SYNOPSIS
    Retrieves profile and avatar information for a contact or group chat.

    .PARAMETER ChatId
    Green API chat identifier such as 27821234567@c.us.
#>
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$ChatId
    )

    return Invoke-WhatsappApi -Endpoint "getContactInfo" -Body @{ chatId = $ChatId }
}

function Get-Contacts {
<#
    .SYNOPSIS
    Retrieves all WhatsApp contacts for the instance.
    .DESCRIPTION
    This function fetches a list of all contacts associated with the Green API instance.
    .EXAMPLE
    Get-Contacts
    #>


    return Invoke-WhatsappApi -Endpoint "getContacts" -Method "GET"

}

function Test-WhatsappAvailability {
<#
    .SYNOPSIS
    Checks if a phone number is registered on WhatsApp.

    .DESCRIPTION
    Uses Green API's checkWhatsapp endpoint.
    Sends POST JSON: { "phoneNumber": <digits> } to:
      {BaseUrl}/checkWhatsapp/{Token}

    .NOTES
    Author  : Pieter
    Date    : 09/08/2025
    Version : 1.3 (PS 5.1; dd/MM/yyyy)

    .PARAMETER Number
    The phone number to check (e.g., "0731234567", "27731234567", "+27 73 123 4567").

    .EXAMPLE
    Test-WhatsappAvailability -Number "0731234567"
    #>
[CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Number
    )

    $normalized = Format-PlainNumber -Number $Number
    if (-not $normalized) {
        Write-Error "Invalid phone number provided."
        return $null
    }
    return Invoke-WhatsappApi -Endpoint "checkWhatsapp" -Body @{ phoneNumber = $normalized }

}

function Get-WhatsappInstanceStatus {
<#
    .SYNOPSIS
    Gets the current operational status of the Green API instance.
    .DESCRIPTION
    This function retrieves the authorization state and overall health of the Green API instance.
    .EXAMPLE
    Get-WhatsappInstanceStatus
    #>


    return Invoke-WhatsappApi -Endpoint "getStatusInstance" -Method "GET"

}

function Get-WhatsappMessageStatus {
<#
    .SYNOPSIS
    Gets the delivery and read status of an outgoing WhatsApp message.
    .DESCRIPTION
    This function retrieves the status (sent, delivered, read) of a specific outgoing message.
    .PARAMETER MessageId
    The ID of the message to check status for.
    .EXAMPLE
    Get-WhatsappMessageStatus -MessageId "ABCD12345"
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$MessageId
    )

    return Invoke-WhatsappApi -Endpoint "getMessageStatus" -Method "GET" -QueryParams @{ idMessage = $MessageId }

}

function Receive-WhatsappNotification {
<#
    .SYNOPSIS
    Fetches the next available notification from the incoming queue.
    .DESCRIPTION
    This function retrieves the next webhook notification from the Green API's queue.
    You will typically need to call Remove-WhatsappNotification after processing.
    .EXAMPLE
    Receive-WhatsappNotification
    #>


    return Invoke-WhatsappApi -Endpoint "receiveNotification" -Method "GET"

}

function Remove-WhatsappNotification {
<#
    .SYNOPSIS
    Deletes a specific notification from the queue.
    .DESCRIPTION
    This function removes a processed notification from the Green API's incoming queue
    using its receipt ID.
    .PARAMETER ReceiptId
    The receipt ID of the notification to delete.
    .EXAMPLE
    Remove-WhatsappNotification -ReceiptId "RECEIPT_XYZ"
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$ReceiptId
    )

    return Invoke-WhatsappApi -Endpoint "deleteNotification/$ReceiptId" -Method "DELETE"

}

function Get-WhatsappSettings {
<#
    .SYNOPSIS
    Retrieve the current settings of the instance.
    .DESCRIPTION
    This function fetches the current configuration settings of the Green API instance,
    including webhook URLs and message delays.
    .EXAMPLE
    Get-WhatsappSettings
    #>


    return Invoke-WhatsappApi -Endpoint "getSettings" -Method "GET"

}

function Set-WhatsappSettings {
<#
    .SYNOPSIS
    Configure instance settings.
    .DESCRIPTION
    This function allows modification of various instance settings.
    Note: Invoking this method triggers a reboot of the instance, and new settings
    are applied within five minutes. At least one parameter must be provided.
    .PARAMETER WebhookUrl
    The URL to send incoming webhooks to.
    .PARAMETER DelaySendMessagesMilliseconds
    Delay in milliseconds between sending messages.
    .PARAMETER OutgoingWebhook
    Boolean to enable/disable outgoing message webhooks.
    .PARAMETER IncomingWebhook
    Boolean to enable/disable incoming message webhooks.
    .PARAMETER StateWebhook
    Boolean to enable/disable instance state change webhooks.
    .PARAMETER IncomingMessageWebhook
    Boolean to enable/disable incoming message webhooks (more specific).
    .PARAMETER OutgoingAPIMessageWebhook
    Boolean to enable/disable outgoing API message webhooks.
    .PARAMETER OutgoingMessageWebhook
    Boolean to enable/disable all outgoing message webhooks.
    .PARAMETER IncomingCallWebhook
    Boolean to enable/disable incoming call webhooks.
    .PARAMETER StatusMessageWebhook
    Boolean to enable/disable status message webhooks.
    .PARAMETER ReadMessagesWebhook
    Boolean to enable/disable read messages webhooks.
    .PARAMETER MessageReceivedWebhook
    Boolean to enable/disable message received webhooks.
    .PARAMETER ClientWebhook
    Boolean to enable/disable client-related webhooks.
    .PARAMETER WebhookUrlToken
    Optional token for webhook URL validation.
    .PARAMETER MarkIncomingMessagesReaded
    Boolean to automatically mark incoming messages as read.
    .PARAMETER MarkIncomingMessagesReadedOnReply
    Boolean to mark incoming messages as read upon reply.
    .PARAMETER SharedLinkWebhook
    Boolean to enable/disable shared link webhooks.
    .PARAMETER NoDeleteMessages
    Boolean to prevent message deletion.
    .PARAMETER NoDeleteMessagesFromMe
    Boolean to prevent deletion of messages sent by me.
    .PARAMETER NoDeleteNotification
    Boolean to prevent deletion of notifications.
    .PARAMETER AutoReply
    Boolean to enable/disable auto-reply.
    .PARAMETER PollMessageWebhook
    Boolean to enable/disable poll message webhooks.
    .PARAMETER DisappearingMessagesWebhook
    Boolean to enable/disable disappearing messages webhooks.
    .PARAMETER DeviceWebhook
    Boolean to enable/disable device-related webhooks.
    .EXAMPLE
    Set-WhatsappSettings -IncomingWebhook $true -OutgoingWebhook $true -DelaySendMessagesMilliseconds 1000
    #>
param(
        [Parameter(Mandatory = $false)] [string]$WebhookUrl,
        [Parameter(Mandatory = $false)] [int]$DelaySendMessagesMilliseconds,
        [Parameter(Mandatory = $false)] [bool]$OutgoingWebhook,
        [Parameter(Mandatory = $false)] [bool]$IncomingWebhook,
        [Parameter(Mandatory = $false)] [bool]$StateWebhook,
        [Parameter(Mandatory = $false)] [bool]$IncomingMessageWebhook,
        [Parameter(Mandatory = $false)] [bool]$OutgoingAPIMessageWebhook,
        [Parameter(Mandatory = $false)] [bool]$OutgoingMessageWebhook,
        [Parameter(Mandatory = $false)] [bool]$IncomingCallWebhook,
        [Parameter(Mandatory = $false)] [bool]$StatusMessageWebhook,
        [Parameter(Mandatory = $false)] [bool]$ReadMessagesWebhook,
        [Parameter(Mandatory = $false)] [bool]$MessageReceivedWebhook,
        [Parameter(Mandatory = $false)] [bool]$ClientWebhook,
        [Parameter(Mandatory = $false)] [string]$WebhookUrlToken,
        [Parameter(Mandatory = $false)] [bool]$MarkIncomingMessagesReaded,
        [Parameter(Mandatory = $false)] [bool]$MarkIncomingMessagesReadedOnReply,
        [Parameter(Mandatory = $false)] [bool]$SharedLinkWebhook,
        [Parameter(Mandatory = $false)] [bool]$NoDeleteMessages,
        [Parameter(Mandatory = $false)] [bool]$NoDeleteMessagesFromMe,
        [Parameter(Mandatory = $false)] [bool]$NoDeleteNotification,
        [Parameter(Mandatory = $false)] [bool]$AutoReply,
        [Parameter(Mandatory = $false)] [bool]$PollMessageWebhook,
        [Parameter(Mandatory = $false)] [bool]$DisappearingMessagesWebhook,
        [Parameter(Mandatory = $false)] [bool]$DeviceWebhook
    )

    $Body = @{}
    if ($PSBoundParameters.ContainsKey('WebhookUrl')) { $Body.webhookUrl = $WebhookUrl }
    if ($PSBoundParameters.ContainsKey('DelaySendMessagesMilliseconds')) { $Body.delaySendMessagesMilliseconds = $DelaySendMessagesMilliseconds }
    if ($PSBoundParameters.ContainsKey('OutgoingWebhook')) { $Body.outgoingWebhook = $OutgoingWebhook }
    if ($PSBoundParameters.ContainsKey('IncomingWebhook')) { $Body.incomingWebhook = $IncomingWebhook }
    if ($PSBoundParameters.ContainsKey('StateWebhook')) { $Body.stateWebhook = $StateWebhook }
    if ($PSBoundParameters.ContainsKey('IncomingMessageWebhook')) { $Body.incomingMessageWebhook = $IncomingMessageWebhook }
    if ($PSBoundParameters.ContainsKey('OutgoingAPIMessageWebhook')) { $Body.outgoingAPIMessageWebhook = $OutgoingAPIMessageWebhook }
    if ($PSBoundParameters.ContainsKey('OutgoingMessageWebhook')) { $Body.outgoingMessageWebhook = $OutgoingMessageWebhook }
    if ($PSBoundParameters.ContainsKey('IncomingCallWebhook')) { $Body.incomingCallWebhook = $IncomingCallWebhook }
    if ($PSBoundParameters.ContainsKey('StatusMessageWebhook')) { $Body.statusMessageWebhook = $StatusMessageWebhook }
    if ($PSBoundParameters.ContainsKey('ReadMessagesWebhook')) { $Body.readMessagesWebhook = $ReadMessagesWebhook }
    if ($PSBoundParameters.ContainsKey('MessageReceivedWebhook')) { $Body.messageReceivedWebhook = $MessageReceivedWebhook }
    if ($PSBoundParameters.ContainsKey('ClientWebhook')) { $Body.clientWebhook = $ClientWebhook }
    if ($PSBoundParameters.ContainsKey('WebhookUrlToken')) { $Body.webhookUrlToken = $WebhookUrlToken }
    if ($PSBoundParameters.ContainsKey('MarkIncomingMessagesReaded')) { $Body.markIncomingMessagesReaded = $MarkIncomingMessagesReaded }
    if ($PSBoundParameters.ContainsKey('MarkIncomingMessagesReadedOnReply')) { $Body.markIncomingMessagesReadedOnReply = $MarkIncomingMessagesReadedOnReply }
    if ($PSBoundParameters.ContainsKey('SharedLinkWebhook')) { $Body.sharedLinkWebhook = $SharedLinkWebhook }
    if ($PSBoundParameters.ContainsKey('NoDeleteMessages')) { $Body.noDeleteMessages = $NoDeleteMessages }
    if ($PSBoundParameters.ContainsKey('NoDeleteMessagesFromMe')) { $Body.noDeleteMessagesFromMe = $NoDeleteMessagesFromMe }
    if ($PSBoundParameters.ContainsKey('NoDeleteNotification')) { $Body.noDeleteNotification = $NoDeleteNotification }
    if ($PSBoundParameters.ContainsKey('AutoReply')) { $Body.autoReply = $AutoReply }
    if ($PSBoundParameters.ContainsKey('PollMessageWebhook')) { $Body.pollMessageWebhook = $PollMessageWebhook }
    if ($PSBoundParameters.ContainsKey('DisappearingMessagesWebhook')) { $Body.disappearingMessagesWebhook = $DisappearingMessagesWebhook }
    if ($PSBoundParameters.ContainsKey('DeviceWebhook')) { $Body.deviceWebhook = $DeviceWebhook }

    if ($Body.Count -eq 0) {
        Write-Error "At least one setting parameter must be provided to Set-WhatsappSettings."
        return $null
    }
    return Invoke-WhatsappApi -Endpoint "setSettings" -Body $Body

}

function Get-WhatsappInstanceState {
<#
    .SYNOPSIS
    Get the current operational state of the instance.
    .DESCRIPTION
    This function retrieves the current operational state of the Green API instance,
    providing insights into its authorization status (e.g., authorized, notAuthorized).
    .EXAMPLE
    Get-WhatsappInstanceState
    #>


    return Invoke-WhatsappApi -Endpoint "getStateInstance" -Method "GET"

}

function Restart-WhatsappInstance {
<#
    .SYNOPSIS
    Reboot the Green API instance.
    .DESCRIPTION
    This function initiates a reboot of the Green API instance. This can be useful
    for resolving instances stuck in an error state or after a yellowCard status.
    .EXAMPLE
    Restart-WhatsappInstance
    #>


    return Invoke-WhatsappApi -Endpoint "reboot" -Method "GET"

}

function Disconnect-WhatsappInstance {
<#
    .SYNOPSIS
    Log out the WhatsApp account from the instance.
    .DESCRIPTION
    This function logs out the WhatsApp account linked to the Green API instance,
    disconnecting it. This is necessary before re-authorizing an instance.
    .EXAMPLE
    Disconnect-WhatsappInstance
    #>


    return Invoke-WhatsappApi -Endpoint "logout" -Method "GET"

}

function Get-WhatsappQrCode {
<#
    .SYNOPSIS
    Get the QR code for instance authorization.
    .DESCRIPTION
    This function retrieves a base64-encoded QR code image, which can be scanned
    with the WhatsApp mobile application to authorize the Green API instance.
    It is recommended to request this method with a 1-second delay, as the QR code
    updates every 20 seconds.
    .EXAMPLE
    Get-WhatsappQrCode
    #>


    return Invoke-WhatsappApi -Endpoint "qr" -Method "GET"

}

function Get-WhatsappAuthorizationCode {
<#
    .SYNOPSIS
    Authorize instance using a phone number and code.
    .DESCRIPTION
    This function allows authorizing an instance using a phone number, as an alternative
    to QR code authorization. The returned code must be entered into the WhatsApp app.
    .PARAMETER PhoneNumber
    The phone number to authorize, in international format (e.g., "27731234567") without '+'.
    .EXAMPLE
    Get-WhatsappAuthorizationCode -PhoneNumber "27731234567"
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$PhoneNumber
    )

    return Invoke-WhatsappApi -Endpoint "getAuthorizationCode" -Body @{ phoneNumber = $PhoneNumber }

}

function Set-WhatsappProfilePicture {
<#
    .SYNOPSIS
    Set the WhatsApp account's profile picture.
    .DESCRIPTION
   
    This function allows setting the profile picture for the WhatsApp account linked
    to the Green API instance.
    .PARAMETER FilePath
    The full path to the JPG image file to use as the profile picture.
    .EXAMPLE
    Set-WhatsappProfilePicture -FilePath "C:\path\to\profile.jpg"
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath -PathType Leaf)) {
        Write-Error "File not found at '$FilePath'."
        return $null
    }
    if ((Get-Item $FilePath).Extension -ne ".jpg") {
        Write-Error "Only JPG images are supported for profile pictures."
        return $null
    }

    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $base64File = [System.Convert]::ToBase64String($fileBytes)

    return Invoke-WhatsappApi -Endpoint "setProfilePicture" -Body @{ file = $base64File }

}

function Update-WhatsappApiToken {
<#
    .SYNOPSIS
    Rotates the Green API token and stores the replacement using Windows DPAPI.
#>
    [CmdletBinding(SupportsShouldProcess = $true, ConfirmImpact = 'High')]
    param()

    if (-not $PSCmdlet.ShouldProcess(('Green API instance {0}' -f $global:InstanceId), 'Rotate API token')) {
        return
    }

    $response = Invoke-WhatsappApi -Endpoint "updateApiToken" -Method "GET"
    $newToken = if ($response.apiTokenInstance) { [string]$response.apiTokenInstance } elseif ($response.apiToken) { [string]$response.apiToken } else { $null }
    if ([string]::IsNullOrWhiteSpace($newToken)) {
        throw 'Green API rotated the token but did not return a replacement token in a recognised field.'
    }

    $secureToken = ConvertTo-WhatsappSecureString -PlainText $newToken
    $existingConfig = Get-Content -LiteralPath $script:ConfigFilePath -Raw | ConvertFrom-Json
    Save-WhatsappProtectedToken -InstanceId $global:InstanceId -SecureToken $secureToken -ApiUrl ([string]$existingConfig.apiUrl)
    $global:Token = $newToken
    Write-WhatsappLog -Message 'Green API token rotated and stored using DPAPI.'
    return $response
}

function Get-WhatsappWaAccountInfo {
<#
    .SYNOPSIS
    Retrieve detailed WhatsApp account information.
    .DESCRIPTION
    This function fetches detailed information about the WhatsApp account linked
    to the Green API instance, including avatar URL, phone number, and instance state.
    .EXAMPLE
    Get-WhatsappWaAccountInfo
    #>


    return Invoke-WhatsappApi -Endpoint "getWaSettings" -Method "GET"

}

function Send-WhatsappPoll {
<#
    .SYNOPSIS
    Send a WhatsApp poll message.
    .DESCRIPTION
    This function sends a poll message to either a personal or group chat.
    Polls must have between 2 and 12 unique answer options.
    .PARAMETER Number
    The recipient's phone number.
    .PARAMETER ChatId
    The recipient's chat ID. One of -Number or -ChatId is mandatory.
    .PARAMETER Message
    The poll question (max 255 characters).
    .PARAMETER Options
    An array of strings representing the poll choices (min 2, max 12).
    .PARAMETER MultipleAnswers
    If $true, allows recipients to select multiple answers.
    .PARAMETER QuotedMessageId
    Optional ID of a message to quote in the poll.
    .EXAMPLE
    Send-WhatsappPoll -Number "0731234567" -Message "What's your favorite color?" -Options @("Red", "Blue", "Green") -MultipleAnswers $false
    #>
param(
        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$Number,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ChatId,

        [Parameter(Mandatory = $true)]
        [string]$Message,

        [Parameter(Mandatory = $true)]
        [string[]]$Options, # Corrected type to string[]

        [Parameter(Mandatory = $false)]
        [bool]$MultipleAnswers = $false,

        [Parameter(Mandatory = $false)]
        [string]$QuotedMessageId
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $Number
    } else {
        $targetChatId = $ChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid number or chat ID provided."
        return $null
    }
    if ($Options.Count -lt 2 -or $Options.Count -gt 12) {
        Write-Error "Poll must have between 2 and 12 options."
        return $null
    }
    if ($Message.Length -gt 255) {
        Write-Error "Poll message length cannot exceed 255 characters."
        return $null
    }

    $Body = @{
        chatId = $targetChatId
        message = $Message
        options = $Options
        multipleAnswers = $MultipleAnswers
    }
    if ($QuotedMessageId) { $Body.quotedMessageId = $QuotedMessageId }
    return Invoke-WhatsappApi -Endpoint "sendPoll" -Body $Body

}

function Send-WhatsappForwardedMessage {
<#
    .SYNOPSIS
    Send one or more forwarded messages to a chat.
    .DESCRIPTION
    This function sends existing messages from a source chat to a new recipient chat.
    .PARAMETER ChatId
    The recipient's chat ID (e.g., "27731234567@c.us" or "group_id@g.us").
    .PARAMETER ChatIdFrom
    The source chat ID from which messages are being forwarded.
    .PARAMETER Messages
    An array of message IDs to forward.
    .PARAMETER TypingTime
    Optional time in seconds to simulate typing activity before forwarding.
    .EXAMPLE
    Send-WhatsappForwardedMessage -ChatId "27731234567@c.us" -ChatIdFrom "27821234567@c.us" -Messages @("MSG1", "MSG2")
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$ChatId,

        [Parameter(Mandatory = $true)]
        [string]$ChatIdFrom,

        [Parameter(Mandatory = $true)]
        [string[]]$Messages, # Corrected type to string[]

        [Parameter(Mandatory = $false)]
        [int]$TypingTime
    )

    $Body = @{
        chatId = $ChatId
        chatIdFrom = $ChatIdFrom
        messages = $Messages
    }
    if ($TypingTime) { $Body.typingTime = $TypingTime }
    return Invoke-WhatsappApi -Endpoint "forwardMessages" -Body $Body

}

function Send-WhatsappInteractiveButtons {
<#
    .SYNOPSIS
    Send a message with interactive buttons.
    .DESCRIPTION
    This function sends a message containing interactive buttons (copy, call, URL).
    Currently in beta mode. Max 3 buttons per message.
    .PARAMETER Number
    The recipient's phone number.
    .PARAMETER ChatId
    The recipient's chat ID. One of -Number or -ChatId is mandatory.
    .PARAMETER Body
    The main text content of the message.
    .PARAMETER Buttons
    An array of hashtables, each representing a button.
    Each hashtable must have 'type' ('copy', 'call', 'url'), 'buttonId', 'buttonText',
    and type-specific parameters (e.g., 'copyCode', 'phoneNumber', 'url').
    .PARAMETER Header
    Optional header text for the message.
    .PARAMETER Footer
    Optional footer text for the message.
    .EXAMPLE
    $buttons = @(
        @{ type = "copy"; buttonId = "copy_code"; buttonText = "Copy Code"; copyCode = "12345" },
        @{ type = "call"; buttonId = "call_support"; buttonText = "Call Support"; phoneNumber = "27821234567" }
    )
    Send-WhatsappInteractiveButtons -Number "0731234567" -Body "Please choose an option:" -Buttons $buttons -Header "Action Required"
    #>
param(
        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$Number,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ChatId,

        [Parameter(Mandatory = $true)]
        [string]$Body,

        [Parameter(Mandatory = $true)]
        [hashtable[]]$Buttons, # Corrected type to hashtable[]

        [Parameter(Mandatory = $false)]
        [string]$Header,

        [Parameter(Mandatory = $false)]
        [string]$Footer
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $Number
    } else {
        $targetChatId = $ChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid number or chat ID provided."
        return $null
    }
    if ($Buttons.Count -gt 3) {
        Write-Error "Maximum of 3 interactive buttons allowed."
        return $null
    }

    $BodyPayload = @{
        chatId = $targetChatId
        body = $Body
        buttons = $Buttons
    }
    if ($Header) { $BodyPayload.header = $Header }
    if ($Footer) { $BodyPayload.footer = $Footer }
    return Invoke-WhatsappApi -Endpoint "sendInteractiveButtons" -Body $BodyPayload

}

function Send-WhatsappTypingNotification {
<#
    .SYNOPSIS
    Send a typing or recording notification to a chat.
    .DESCRIPTION
    This function simulates typing or recording activity in a chat.
    Currently in beta mode.
    .PARAMETER Number
    The recipient's phone number.
    .PARAMETER ChatId
    The recipient's chat ID. One of -Number or -ChatId is mandatory.
    .PARAMETER TypingTime
    Optional time in seconds to simulate typing/recording (1 to 20 seconds, default 1).
    .PARAMETER TypingType
    Type of notification: "typing" (default) or "recording".
    .EXAMPLE
    Send-WhatsappTypingNotification -Number "0731234567" -TypingTime 5 -TypingType "typing"
    #>
param(
        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$Number,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ChatId,

        [Parameter(Mandatory = $false)]
        [ValidateRange(1, 20)]
        [int]$TypingTime = 1,

        [Parameter(Mandatory = $false)]
        [ValidateSet("typing", "recording")]
        [string]$TypingType = "typing"
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $Number
    } else {
        $targetChatId = $ChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid number or chat ID provided."
        return $null
    }

    $Body = @{
        chatId = $targetChatId
        typingTime = $TypingTime
        typingType = $TypingType
    }
    return Invoke-WhatsappApi -Endpoint "sendTyping" -Body $Body

}

function Get-WhatsappChatMessage {
<#
    .SYNOPSIS
    Retrieve a specific message by ID from a chat.
    .DESCRIPTION
    This function fetches details of a specific message from a chat's history using its ID.
    Message appearance in the journal may take up to 2 minutes.
    .PARAMETER Number
    The phone number of the chat.
    .PARAMETER ChatId
    The chat ID. One of -Number or -ChatId is mandatory.
    .PARAMETER IdMessage
    The ID of the message to retrieve.
    .EXAMPLE
    Get-WhatsappChatMessage -Number "0731234567" -IdMessage "MESSAGE_ID_ABC"
    #>
param(
        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$Number,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ChatId,

        [Parameter(Mandatory = $true)]
        [string]$IdMessage
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $Number
    } else {
        $targetChatId = $ChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid number or chat ID provided."
        return $null
    }

    $Body = @{
        chatId = $targetChatId
        idMessage = $IdMessage
    }
    return Invoke-WhatsappApi -Endpoint "getMessage" -Body $Body

}

function Get-WhatsappMessagesCount {
<#
    .SYNOPSIS
    Get the number of messages in the sending queue.
    .DESCRIPTION
    This function retrieves the current count of messages waiting in the Green API's
    outbound sending queue. Information is updated every 10 seconds.
    .EXAMPLE
    Get-WhatsappMessagesCount
    #>


    return Invoke-WhatsappApi -Endpoint "getMessagesCount" -Method "GET"

}

function Get-WhatsappMessagesQueue {
<#
    .SYNOPSIS
    Show details of messages currently in the sending queue.
    .DESCRIPTION
    This function provides a detailed view of messages currently in the sending queue,
    including their type and full payload.
    .EXAMPLE
    Get-WhatsappMessagesQueue
    #>


    return Invoke-WhatsappApi -Endpoint "showMessagesQueue" -Method "GET"

}

function Clear-WhatsappMessagesQueue {
<#
    .SYNOPSIS
    Clear all messages from the sending queue.
    .DESCRIPTION
    This function removes all messages from the Green API's outbound sending queue.
    Use with caution, as this action cannot be undone.
    .EXAMPLE
    Clear-WhatsappMessagesQueue
    #>


    return Invoke-WhatsappApi -Endpoint "clearMessagesQueue" -Method "GET"

}

function Get-WhatsappWebhooksCount {
<#
    .SYNOPSIS
    Get the number of webhooks in the incoming queue.
    .DESCRIPTION
    This function retrieves the number of incoming notifications (webhooks) currently
    present in the Green API's queue. Information is updated every 10 seconds.
    .EXAMPLE
    Get-WhatsappWebhooksCount
    #>
param()

    return Invoke-WhatsappApi -Endpoint "getWebhooksCount" -Method "GET"

}

function Clear-WhatsappWebhooksQueue {
<#
    .SYNOPSIS
    Clear all webhooks from the incoming queue.
    .DESCRIPTION
    This function removes all notifications from the Green API's incoming webhooks queue.
    This method has a rate limit of once per minute.
    .EXAMPLE
    Clear-WhatsappWebhooksQueue
    #>
param()

    return Invoke-WhatsappApi -Endpoint "clearWebhooksQueue" -Method "DELETE"

}

function New-WhatsappGroup {
<#
    .SYNOPSIS
    Create a new WhatsApp group chat.
    .DESCRIPTION
    This function creates a new WhatsApp group with a specified name and initial participants.
    Group creation should be no more often than once every 5 minutes.
    .PARAMETER GroupName
    The name for the new group (max 100 characters).
    .PARAMETER ParticipantNumbers
    An array of phone numbers (e.g., "0731234567") to add as initial participants.
    .PARAMETER ParticipantChatIds
    An array of chat IDs (e.g., "27731234567@c.us") to add as initial participants.
    One of -ParticipantNumbers or -ParticipantChatIds is mandatory.
    .EXAMPLE
    New-WhatsappGroup -GroupName "My New Team" -ParticipantNumbers @("0731234567", "0749876543")
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$GroupName,

        [Parameter(ParameterSetName='ByNumbers', Mandatory = $true)]
        [string[]]$ParticipantNumbers,

        [Parameter(ParameterSetName='ByChatIds', Mandatory = $true)]
        [string[]]$ParticipantChatIds
    )

    if ($GroupName.Length -gt 100) {
        Write-Error "Group name cannot exceed 100 characters."
        return $null
    }

    $targetChatIds = @()
    if ($PSCmdlet.ParameterSetName -eq 'ByNumbers') {
        foreach ($num in $ParticipantNumbers) {
            $targetChatIds += Format-WhatsappNumber -Number $num
        }
    } else {
        $targetChatIds = $ParticipantChatIds
    }

    if ($targetChatIds.Count -eq 0) {
        Write-Error "No valid participants provided for the new group."
        return $null
    }

    $Body = @{
        groupName = $GroupName
        chatIds = $targetChatIds
    }
    return Invoke-WhatsappApi -Endpoint "createGroup" -Body $Body

}

function Set-WhatsappGroupName {
<#
    .SYNOPSIS
    Change the name of a group chat.
    .DESCRIPTION
    This function updates the name of an existing WhatsApp group.
    .PARAMETER GroupId
    The chat ID of the group (e.g., "1234567890-123456@g.us").
    .PARAMETER NewGroupName
    The new name for the group (max 100 characters).
    .EXAMPLE
    Set-WhatsappGroupName -GroupId "1234567890-123456@g.us" -NewGroupName "Updated Team Name"
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(Mandatory = $true)]
        [string]$NewGroupName
    )

    if ($NewGroupName.Length -gt 100) {
        Write-Error "New group name cannot exceed 100 characters."
        return $null
    }

    $Body = @{
        groupId = $GroupId
        groupName = $NewGroupName
    }
    return Invoke-WhatsappApi -Endpoint "updateGroupName" -Body $Body

}

function Get-WhatsappGroupData {
<#
    .SYNOPSIS
    Retrieve detailed data for a specific group chat.
    .DESCRIPTION
    This function fetches comprehensive information about a WhatsApp group,
    including its members, owner, and invite link.
    .PARAMETER GroupId
    The chat ID of the group (e.g., "1234567890-123456@g.us").
    .EXAMPLE
    Get-WhatsappGroupData -GroupId "1234567890-123456@g.us"
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId
    )

    return Invoke-WhatsappApi -Endpoint "getGroupData" -Body @{ groupId = $GroupId }

}

function Add-WhatsappGroupParticipant {
<#
    .SYNOPSIS
    Add a participant to a group chat.
    .DESCRIPTION
    This function adds a new member to an existing WhatsApp group.
    The user performing this action must be a group administrator, and the participant's
    number must be saved in their phonebook.
    .PARAMETER GroupId
    The chat ID of the group.
    .PARAMETER ParticipantNumber
    The phone number of the participant to add (e.g., "0731234567").
    .PARAMETER ParticipantChatId
    The chat ID of the participant to add (e.g., "27731234567@c.us").
    One of -ParticipantNumber or -ParticipantChatId is mandatory.
    .EXAMPLE
    Add-WhatsappGroupParticipant -GroupId "1234567890-123456@g.us" -ParticipantNumber "0731234567"
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$ParticipantNumber,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ParticipantChatId
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $ParticipantNumber
    } else {
        $targetChatId = $ParticipantChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid participant number or chat ID provided."
        return $null
    }

    $Body = @{
        groupId = $GroupId
        participantChatId = $targetChatId
    }
    return Invoke-WhatsappApi -Endpoint "addGroupParticipant" -Body $Body

}

function Remove-WhatsappGroupParticipant {
<#
    .SYNOPSIS
    Remove a participant from a group chat.
    .DESCRIPTION
    This function removes a specified member from a WhatsApp group.
    .PARAMETER GroupId
    The chat ID of the group.
    .PARAMETER ParticipantNumber
    The phone number of the participant to remove.
    .PARAMETER ParticipantChatId
    The chat ID of the participant to remove.
    One of -ParticipantNumber or -ParticipantChatId is mandatory.
    .EXAMPLE
    Remove-WhatsappGroupParticipant -GroupId "1234567890-123456@g.us" -ParticipantNumber "0731234567"
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$ParticipantNumber,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ParticipantChatId
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $ParticipantNumber
    } else {
        $targetChatId = $ParticipantChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid participant number or chat ID provided."
        return $null
    }

    $Body = @{
        groupId = $GroupId
        participantChatId = $targetChatId
    }
    return Invoke-WhatsappApi -Endpoint "removeGroupParticipant" -Body $Body

}

function Set-WhatsappGroupAdmin {
<#
    .SYNOPSIS
    Grant administrator rights to a group participant.
    .DESCRIPTION
    This function elevates a specified participant to an administrator role within a group chat.
    .PARAMETER GroupId
    The chat ID of the group.
    .PARAMETER ParticipantNumber
    The phone number of the participant to make admin.
    .PARAMETER ParticipantChatId
    The chat ID of the participant to make admin.
    One of -ParticipantNumber or -ParticipantChatId is mandatory.
    .EXAMPLE
    Set-WhatsappGroupAdmin -GroupId "1234567890-123456@g.us" -ParticipantNumber "0731234567"
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$ParticipantNumber,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ParticipantChatId
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $ParticipantNumber
    } else {
        $targetChatId = $ParticipantChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid participant number or chat ID provided."
        return $null
    }

    $Body = @{
        groupId = $GroupId
        participantChatId = $targetChatId
    }
    return Invoke-WhatsappApi -Endpoint "setGroupAdmin" -Body $Body

}

function Remove-WhatsappGroupAdmin {
<#
    .SYNOPSIS
    Remove administrator rights from a group participant.
    .DESCRIPTION
    This function revokes administrator privileges from a specified group participant.
    .PARAMETER GroupId
    The chat ID of the group.
    .PARAMETER ParticipantNumber
    The phone number of the participant to remove admin rights from.
    .PARAMETER ParticipantChatId
    The chat ID of the participant to remove admin rights from.
    One of -ParticipantNumber or -ParticipantChatId is mandatory.
    .EXAMPLE
    Remove-WhatsappGroupAdmin -GroupId "1234567890-123456@g.us" -ParticipantNumber "0731234567"
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(ParameterSetName='ByNumber', Mandatory = $true)]
        [string]$ParticipantNumber,

        [Parameter(ParameterSetName='ByChatId', Mandatory = $true)]
        [string]$ParticipantChatId
    )

    $targetChatId = $null
    if ($PSCmdlet.ParameterSetName -eq 'ByNumber') {
        $targetChatId = Format-WhatsappNumber -Number $ParticipantNumber
    } else {
        $targetChatId = $ParticipantChatId
    }

    if (-not $targetChatId) {
        Write-Error "Invalid participant number or chat ID provided."
        return $null
    }

    $Body = @{
        groupId = $GroupId
        participantChatId = $targetChatId
    }
    return Invoke-WhatsappApi -Endpoint "removeAdmin" -Body $Body

}

function Set-WhatsappGroupPicture {
<#
    .SYNOPSIS
    Set the profile picture for a group chat.
    .DESCRIPTION
    This function allows setting or changing the profile picture for a WhatsApp group.
    .PARAMETER GroupId
    The chat ID of the group.
    .PARAMETER FilePath
    The full path to the JPG image file to use as the group picture.
    .EXAMPLE
    Set-WhatsappGroupPicture -GroupId "1234567890-123456@g.us" -FilePath "C:\path\to\group_pic.jpg"
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId,

        [Parameter(Mandatory = $true)]
        [string]$FilePath
    )

    if (-not (Test-Path $FilePath -PathType Leaf)) {
        Write-Error "File not found at '$FilePath'."
        return $null
    }
    if ((Get-Item $FilePath).Extension -ne ".jpg") {
        Write-Error "Only JPG images are supported for group pictures."
        return $null
    }

    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $base64File = [System.Convert]::ToBase64String($fileBytes)

    $Body = @{
        groupId = $GroupId
        file = $base64File
    }
    return Invoke-WhatsappApi -Endpoint "setGroupPicture" -Body $Body

}

function Exit-WhatsappGroup {
<#
    .SYNOPSIS
    Exit a group chat.
    .DESCRIPTION
    This function allows the instance to exit a specified WhatsApp group chat.
    .PARAMETER GroupId
    The chat ID of the group to exit.
    .EXAMPLE
    Exit-WhatsappGroup -GroupId "1234567890-123456@g.us"
    #>
param(
        [Parameter(Mandatory = $true)]
        [string]$GroupId
    )

    return Invoke-WhatsappApi -Endpoint "leaveGroup" -Body @{ groupId = $GroupId }

}

function Send-WhatsappVoiceStatus {
<#
    .SYNOPSIS
    Sends a voice note as a WhatsApp status (beta feature).
    .PARAMETER FileUrl
    Publicly accessible URL to an audio file (mp3/wav).
    .PARAMETER FileName
    File name to display.
    .PARAMETER ParticipantNumbers
    Optional phone numbers allowed to view this status. Specify only one of ParticipantNumbers or ParticipantChatIds.
    .PARAMETER ParticipantChatIds
    Optional chat IDs allowed to view this status. Specify only one of ParticipantNumbers or ParticipantChatIds.
    #>
[CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileUrl,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName,

        [Parameter(Mandatory = $false)]
        [string[]]$ParticipantNumbers,

        [Parameter(Mandatory = $false)]
        [string[]]$ParticipantChatIds
    )

    if ($ParticipantNumbers -and $ParticipantChatIds) {
        throw "Specify only one of -ParticipantNumbers or -ParticipantChatIds, not both."
    }

    $Body = @{
        fileUrl = $FileUrl
        fileName = $FileName
    }
    if ($ParticipantNumbers) { $body.participantNumbers = $ParticipantNumbers }
    if ($ParticipantChatIds) { $body.participantChatIds = $ParticipantChatIds }

    return Invoke-WhatsappApi -Endpoint "sendStatusAudio" -Body $Body

}

function Send-WhatsappMediaStatus {
<#
    .SYNOPSIS
    Sends an image or video as a WhatsApp status (beta feature).
    .PARAMETER FileUrl
    Public URL to media (png/jpg/mp4).
    .PARAMETER FileName
    Media file name.
    .PARAMETER Caption
    Optional caption text.
    .PARAMETER ParticipantNumbers
    Optional phone numbers allowed to view this status. Specify only one of ParticipantNumbers or ParticipantChatIds.
    .PARAMETER ParticipantChatIds
    Optional chat IDs allowed to view this status. Specify only one of ParticipantNumbers or ParticipantChatIds.
    #>
[CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileUrl,

        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$FileName,

        [Parameter(Mandatory = $false)]
        [string]$Caption,

        [Parameter(Mandatory = $false)]
        [string[]]$ParticipantNumbers,

        [Parameter(Mandatory = $false)]
        [string[]]$ParticipantChatIds
    )

    if ($ParticipantNumbers -and $ParticipantChatIds) {
        throw "Specify only one of -ParticipantNumbers or -ParticipantChatIds, not both."
    }

    $Body = @{
        fileUrl  = $FileUrl
        fileName = $FileName
    }
    if ($Caption) { $body.caption = $Caption }
    if ($ParticipantNumbers) { $body.participantNumbers = $ParticipantNumbers }
    if ($ParticipantChatIds) { $body.participantChatIds = $ParticipantChatIds }

    return Invoke-WhatsappApi -Endpoint "sendStatusMedia" -Body $Body

}

# --- JSON Database Functions ---

function Get-LocalChatHistory {
    <#
    .SYNOPSIS
    Retrieves the local JSON-journaled chat history for a specific ChatId.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ChatId,

        [Parameter(Mandatory = $false)]
        [int]$Count = 50
    )

    $dbDir = Join-Path $env:APPDATA "PHWhatsapp\Database"
    $dbPath = Join-Path $dbDir "history_$($ChatId.Split('@')[0]).json"

    if (-not (Test-Path $dbPath)) {
        return @()
    }

    try {
        $history = Get-Content -Path $dbPath -Raw -ErrorAction SilentlyContinue | ConvertFrom-Json
        if (-not $history) { return @() }
        
        # Sort oldest to newest and return the requested count from the tail
        $sorted = $history | Sort-Object timestamp
        $selected = $sorted | Select-Object -Last $Count

        # Normalize legacy records by ensuring typeMessage and textMessage properties exist
        foreach ($msg in $selected) {
            if ($null -eq $msg.psobject.Properties['typeMessage']) {
                $msg | Add-Member -NotePropertyName 'typeMessage' -NotePropertyValue $null
            }
            if ($null -eq $msg.psobject.Properties['textMessage']) {
                $msg | Add-Member -NotePropertyName 'textMessage' -NotePropertyValue $null
            }
        }
        return $selected
    } catch {
        Write-Error "Failed to read local chat database: $_"
        return @()
    }
}

function Save-LocalChatMessage {
    <#
    .SYNOPSIS
    Saves or updates a message in the local JSON database file.
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$ChatId,

        [Parameter(Mandatory = $true)]
        [object]$MessageObj
    )

    $dbDir = Join-Path $env:APPDATA "PHWhatsapp\Database"
    if (-not (Test-Path $dbDir)) {
        New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
    }

    $dbPath = Join-Path $dbDir "history_$($ChatId.Split('@')[0]).json"
    $history = @()

    if (Test-Path $dbPath) {
        try {
            $raw = Get-Content -Path $dbPath -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $history = @(ConvertFrom-Json $raw)
            }
        } catch {
            Write-WhatsappLog -Level WARN -Message ('Could not read local chat history {0}: {1}' -f $dbPath, $_.Exception.Message)
        }
    }

    # Avoid adding duplicate message IDs
    $exists = $history | Where-Object { $_.idMessage -eq $MessageObj.idMessage }
    if ($exists) {
        return
    }

    $history += $MessageObj

    # Keep a maximum buffer of 200 messages per contact to ensure instant sub-millisecond IO times
    if ($history.Count -gt 200) {
        $history = $history | Sort-Object timestamp | Select-Object -Last 200
    }

    try {
        $history | ConvertTo-Json -Depth 5 | Set-Content -Path $dbPath -Force -Encoding UTF8
    } catch {
        Write-Error "Failed to write local database: $_"
    }
}

# Export only primary functions
Export-ModuleMember -Function `
    New-WhatsappConfigFile,Get-WhatsappConfig,Clear-WhatsappLocalData,Send-Whatsapp,Send-WhatsappFileByUpload,Send-WhatsappFileByUrl,Send-WhatsappLocation,Send-WhatsappContact,Get-LastIncomingMessages,Get-LastOutgoingMessages,Get-ChatHistory,Export-WhatsappChat,Save-WhatsappChatMedia,Set-ChatRead,Get-WhatsappFile,Get-WhatsappChats,Get-WhatsappContactInfo,Get-Contacts,Test-WhatsappAvailability,Get-WhatsappInstanceStatus,Get-WhatsappMessageStatus,Receive-WhatsappNotification,Remove-WhatsappNotification,Get-WhatsappSettings,Set-WhatsappSettings,Get-WhatsappInstanceState,Restart-WhatsappInstance,Disconnect-WhatsappInstance,Get-WhatsappQrCode,Get-WhatsappAuthorizationCode,Set-WhatsappProfilePicture,Update-WhatsappApiToken,Get-WhatsappWaAccountInfo,Send-WhatsappPoll,Send-WhatsappForwardedMessage,Send-WhatsappInteractiveButtons,Send-WhatsappTypingNotification,Get-WhatsappChatMessage,Get-WhatsappMessagesCount,Get-WhatsappMessagesQueue,Clear-WhatsappMessagesQueue,Get-WhatsappWebhooksCount,Clear-WhatsappWebhooksQueue,New-WhatsappGroup,Set-WhatsappGroupName,Get-WhatsappGroupData,Add-WhatsappGroupParticipant,Remove-WhatsappGroupParticipant,Set-WhatsappGroupAdmin,Remove-WhatsappGroupAdmin,Set-WhatsappGroupPicture,Exit-WhatsappGroup,Send-WhatsappVoiceStatus,Send-WhatsappMediaStatus,Get-LocalChatHistory,Save-LocalChatMessage