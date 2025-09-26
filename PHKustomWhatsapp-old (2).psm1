<#
.SYNOPSIS
WhatsApp automation and reporting toolkit using Green API.
Author: Pieter Hattingh
Version: 3.4
Previous Change: 2025-07-28 22:30 (Completed the script, ensuring all functions are present and correctly implemented)
Current Change: 2025-07-28 22:37 (Ensured full completion of the script, fixing truncation and verifying all functions are intact.)
Description: PowerShell module for WhatsApp messaging, media, status, and contact management via Green API.
             All config variables are loaded from an external JSON file (c:\Programdata\PHWhatsapp\config.json).
             Robust error handling and clear error messages included.
             Includes: TLS 1.2 enforcement, self-elevation, Clear-Host, and variable clearing at script start.
#>

# --- Global Configuration Variables (Loaded from external file) ---
$global:InstanceId = $null
$global:Token = $null
$global:BaseUrl = $null

# --- Dynamic config path (per-user, not hardcoded) ---
$script:ConfigDir = Join-Path $env:APPDATA 'PHWhatsapp'
$script:ConfigFilePath = Join-Path $script:ConfigDir 'config.json'

# --- Ensure TLS 1.2 for secure communication ---
[Net.ServicePointManager]::SecurityProtocol = [Net.SecurityProtocolType]::Tls12
# --- Utility: Clear all functions from memory ---
function Clear-WhatsappFunctions {
    <#
    .SYNOPSIS
    Removes all functions defined in this module from the current session.
    .DESCRIPTION
    This function removes all WhatsApp-related functions from the session to allow for a clean reload or update.
    #>
    $functionNames = @( 
        'Load-WhatsappConfig',
        'Format-WhatsappNumber',
        'Invoke-WhatsappApi',
        'Send-Whatsapp',
        'Send-WhatsappFileByUpload',
        'Send-WhatsappFileByUrl',
        'Send-WhatsappLocation',
        'Send-WhatsappContact',
        'Get-LastIncomingMessages',
        'Get-LastOutgoingMessages',
        'Get-ChatHistory',
        'Set-ChatRead',
        'Download-WhatsappFile',
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
        'Forward-WhatsappMessage',
        'Send-WhatsappInteractiveButtons',
        'Send-WhatsappTypingNotification',
        'Get-WhatsappChatMessage',
        'Get-WhatsappMessagesCount',
        'Get-WhatsappMessagesQueue',
        'Clear-WhatsappMessagesQueue',
        'Get-WhatsappWebhooksCount',
        'Clear-WhatsappWebhooksQueue',
        'New-WhatsappGroup',
        'Set-WhatsappGroupName'
    )
    foreach ($fn in $functionNames) {
        if (Get-Command $fn -ErrorAction SilentlyContinue) {
            Remove-Item "function:$fn" -ErrorAction SilentlyContinue
        }
    }
    Write-Host "All WhatsApp functions have been removed from memory." -ForegroundColor Yellow
}

# --- Function to Create Configuration File ---
function New-WhatsappConfigFile {
    <#
    .SYNOPSIS
    Creates a new config.json file for Green API credentials if it does not exist.
    .DESCRIPTION
    This function checks for the existence of 'c:\Programdata\PHWhatsapp\config.json'.
    If the file or its parent directory does not exist, it prompts the user for
    their Green API Instance ID and API Token. It then creates the directory
    (if necessary) and the config.json file with the provided credentials and a date stamp.
    .EXAMPLE
    New-WhatsappConfigFile
    # This function is typically called internally by Load-WhatsappConfig.
    #>
    Write-Host "Checking for WhatsApp configuration file..." -ForegroundColor DarkYellow

    $ConfigFilePath = $script:ConfigFilePath
    $ConfigDirPath = $script:ConfigDir

    if (Test-Path $ConfigFilePath) {
        Write-Host "Configuration file already exists at '$ConfigFilePath'." -ForegroundColor Green
        return $true
    }

    Write-Host "Configuration file not found. Creating a new one..." -ForegroundColor Cyan

    # Create directory if it doesn't exist
    if (-not (Test-Path $ConfigDirPath)) {
        try {
            New-Item -Path $ConfigDirPath -ItemType Directory -Force | Out-Null
            Write-Host "Created directory: '$ConfigDirPath'" -ForegroundColor Cyan
        } catch {
            Write-Error "Failed to create directory '$ConfigDirPath': $($_.Exception.Message)"
            return $false
        }
    }

    # Prompt for credentials
    $idInstance = Read-Host "Please enter your Green API Instance ID"
    $apiTokenInstance = Read-Host "Please enter your Green API API Token"

    if ([string]::IsNullOrWhiteSpace($idInstance) -or [string]::IsNullOrWhiteSpace($apiTokenInstance)) {
        Write-Error "Instance ID and API Token cannot be empty. Configuration file not created."
        return $false
    }

    # Create the config object with a date stamp
    $ConfigContent = [PSCustomObject]@{
        idInstance     = $idInstance
        apiTokenInstance = $apiTokenInstance
        DateCreated    = (Get-Date -Format "yyyy-MM-dd HH:mm:ss")
    }

    try {
        $ConfigContent | ConvertTo-Json -Depth 4 | Set-Content -Path $ConfigFilePath -Force -Encoding UTF8
        Write-Host "Configuration file created successfully at '$ConfigFilePath'." -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to create configuration file '$ConfigFilePath': $($_.Exception.Message)"
        return $false
    }
}

# --- Function to Load Configuration ---
function Get-WhatsappConfig {
    <#
    .SYNOPSIS
    Gets Green API configuration (InstanceId, Token, BaseUrl) from a JSON file.
    .DESCRIPTION
    This function reads the Green API instance ID, API token, and base URL
    from a JSON configuration file located at 'c:\Programdata\PHWhatsapp\config.json'.
    It sets these values as global variables for use by other functions in the module.
    The BaseUrl is constructed dynamically based on the InstanceId.
    If the config file does not exist, it calls New-WhatsappConfigFile to create it.
    .EXAMPLE
    Get-WhatsappConfig
    #>

    $ConfigFilePath = $script:ConfigFilePath


    if (-not (Test-Path $ConfigFilePath)) {
        Write-Host "WhatsApp configuration file not found. Attempting to create it..." -ForegroundColor Yellow
        if (-not (New-WhatsappConfigFile)) {
            Write-Error "Failed to create or load WhatsApp configuration. Module functions may not work."
            return $false
        }
    }

    try {
        $Config = Get-Content -Path $ConfigFilePath | ConvertFrom-Json
        $global:InstanceId = $Config.idInstance
        $global:Token = $Config.apiTokenInstance

        if (-not $global:InstanceId) {
            Write-Error "Error: 'idInstance' not found in configuration file."
            return $false
        }
        if (-not $global:Token) {
            Write-Error "Error: 'apiTokenInstance' not found in configuration file."
            return $false
        }

        # Dynamically construct BaseUrl based on InstanceId
        # Green API structure: https://<instance_id_prefix>.api.greenapi.com/waInstance<full_instance_id>
        $instanceIdPrefix = $global:InstanceId.Substring(0, 4) # Assuming first 4 digits are the prefix
        $global:BaseUrl = "https://$instanceIdPrefix.api.greenapi.com/waInstance$global:InstanceId"

        Write-Host "Configuration loaded successfully." -ForegroundColor Green
        Write-Host "Instance ID: $($global:InstanceId)" -ForegroundColor Green
        Write-Host "Base URL: $($global:BaseUrl)" -ForegroundColor Green
        return $true
    } catch {
        Write-Error "Failed to load or parse configuration file: $($_.Exception.Message)"
        return $false
    }
}


# Load configuration when the module is imported (not executed directly)
if ($MyInvocation.InvocationName -eq '.') {
    # Dot-sourced, skip auto-load
} else {
    Get-WhatsappConfig | Out-Null
}
# Export only primary functions for module users
Export-ModuleMember -Function \
    Send-Whatsapp,
    Send-WhatsappFileByUpload,
    Send-WhatsappFileByUrl,
    Send-WhatsappLocation,
    Send-WhatsappContact,
    Get-LastIncomingMessages,
    Get-LastOutgoingMessages,
    Get-ChatHistory,
    Set-ChatRead,
    Get-WhatsappFile,
    Get-Contacts,
    Test-WhatsappAvailability,
    Get-WhatsappInstanceStatus,
    Get-WhatsappMessageStatus,
    Receive-WhatsappNotification,
    Remove-WhatsappNotification,
    Get-WhatsappSettings,
    Set-WhatsappSettings,
    Get-WhatsappInstanceState,
    Restart-WhatsappInstance,
    Disconnect-WhatsappInstance,
    Get-WhatsappQrCode,
    Get-WhatsappAuthorizationCode,
    Set-WhatsappProfilePicture,
    Update-WhatsappApiToken,
    Get-WhatsappWaAccountInfo,
    Send-WhatsappPoll,
    Send-WhatsappForwardedMessage,
    Send-WhatsappInteractiveButtons,
    Send-WhatsappTypingNotification,
    Get-WhatsappChatMessage,
    Get-WhatsappMessagesCount,
    Get-WhatsappMessagesQueue,
    Clear-WhatsappMessagesQueue,
    Get-WhatsappWebhooksCount,
    Clear-WhatsappWebhooksQueue,
    New-WhatsappGroup,
    Set-WhatsappGroupName,
    Get-WhatsappGroupData,
    Add-WhatsappGroupParticipant,
    Remove-WhatsappGroupParticipant,
    Set-WhatsappGroupAdmin,
    Remove-WhatsappGroupAdmin,
    Set-WhatsappGroupPicture,
    Exit-WhatsappGroup,
    Send-WhatsappTextStatus,
    Send-WhatsappVoiceStatus,
    Send-WhatsappMediaStatus
# --- Helper Function for Number Formatting ---
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

# --- Messaging Functions ---

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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Get-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "sendMessage"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        chatId = $targetChatId
        message = $Message
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    if (-not (Test-Path $FilePath -PathType Leaf)) {
        Write-Error "File not found at '$FilePath'."
        return $null
    }

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

    $fileBytes = [System.IO.File]::ReadAllBytes($FilePath)
    $base64File = [System.Convert]::ToBase64String($fileBytes)
    $fileName = [System.IO.Path]::GetFileName($FilePath)

    $Endpoint = "sendFileByUpload"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        chatId = $targetChatId
        fileName = $fileName
        body = $base64File
    }
    if ($Caption) {
        $Body.caption = $Caption
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "sendFileByUrl"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        chatId = $targetChatId
        urlFile = $FileUrl
        fileName = $FileName
    }
    if ($Caption) {
        $Body.caption = $Caption
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "sendLocation"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        chatId = $targetChatId
        latitude = $Latitude
        longitude = $Longitude
    }
    if ($Name) { $Body.nameLocation = $Name }
    if ($Address) { $Body.address = $Address }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "sendContact"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        chatId = $targetChatId
        contact = $ContactNumber
    }
    if ($ContactName) { $Body.name = $ContactName }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "lastIncomingMessages"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $QueryParams = @{ minutes = $Minutes }
    $queryString = ($QueryParams.Keys | ForEach-Object { "$_=$($QueryParams.$_)" }) -join '&'
    $Url += "?$queryString"
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "lastOutgoingMessages"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $QueryParams = @{ minutes = $Minutes }
    $queryString = ($QueryParams.Keys | ForEach-Object { "$_=$($QueryParams.$_)" }) -join '&'
    $Url += "?$queryString"
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "getChatHistory"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        chatId = $targetChatId
        count = $Count
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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
    [Parameter(Mandatory = $true)]
    [string]$Number
)

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $targetChatId = Format-WhatsappNumber -Number $Number
    
    if (-not $targetChatId) {
        Write-Error "Invalid number or chat ID provided."
        return $null
    }

    $Endpoint = "readChat"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        chatId = $targetChatId
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
}

function Get-WhatsappFile {
    <#
    .SYNOPSIS
    Gets a file from an incoming WhatsApp message.
    .DESCRIPTION
    This function gets a file (e.g., image, video, document) associated with a specific message ID
    to a local path.
    .PARAMETER MessageId
    The ID of the message containing the file to get.
    .PARAMETER SavePath
    The full path including filename where the file should be saved (e.g., "C:\downloads\myimage.jpg").
    .EXAMPLE
    Get-WhatsappFile -MessageId "ABCD12345" -SavePath "C:\temp\downloaded_file.jpg"
    #>
    param(
        [Parameter(Mandatory = $true)]
        [string]$MessageId,

        [Parameter(Mandatory = $true)]
        [string]$SavePath
    )

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "downloadFile"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token?idMessage=$MessageId" # Corrected URL construction (query param for ID)

    try {
        Invoke-RestMethod -Uri $Url -Method $Method -OutFile $SavePath -ErrorAction Stop
        Write-Host "File downloaded successfully to '$SavePath'." -ForegroundColor Green
        return $true
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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
    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "getContacts"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Ensure your config loader has set InstanceId, Token, and BaseUrl."
        return $null
    }

    # Use your existing helper to normalise input (expects digits like '2773...')
    $normalized = Format-PlainNumber -Number $Number
    if (-not $normalized) {
        Write-Error "Invalid phone number provided."
        return $null
    }

    $endpoint = "checkWhatsapp"
    $url = ("{0}/{1}/{2}" -f $global:BaseUrl.TrimEnd('/'),$endpoint, $global:Token)

    $headers = @{
        
        "Content-Type" = "application/json"
    }

    $body = @{ phoneNumber = $normalized } | ConvertTo-Json -Depth 3

    try {
        $response = Invoke-RestMethod -Uri $url -Method Post -Headers $headers -Body $body -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API call to '$endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $rs = $_.Exception.Response.GetResponseStream()
                $reader = New-Object System.IO.StreamReader($rs)
                $errorContent = $reader.ReadToEnd()
                $reader.Close()
                if ($errorContent) {
                    try {
                        $err = $errorContent | ConvertFrom-Json
                        if ($err -and $err.message) {
                            Write-Error "Green API Error: $($err.message) (Code: $($err.code))"
                        } else {
                            Write-Error "Raw Error Response: $errorContent"
                        }
                    } catch {
                        Write-Error "Raw Error Response: $errorContent"
                    }
                }
            } catch { Write-Error "Could not parse detailed API error response." }
        }
        return $null
    }
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
    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "getStatusInstance"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "getMessageStatus"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $QueryParams = @{ idMessage = $MessageId }
    $queryString = ($QueryParams.Keys | ForEach-Object { "$_=$($QueryParams.$_)" }) -join '&'
    $Url += "?$queryString"
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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
    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "receiveNotification"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "deleteNotification"
    $Method = "DELETE"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $QueryParams = @{ receiptId = $ReceiptId }
    $queryString = ($QueryParams.Keys | ForEach-Object { "$_=$($QueryParams.$_)" }) -join '&'
    $Url += "?$queryString"
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
}

# --- Account Management Functions (New) ---

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
    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "getSettings"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "setSettings"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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
    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "getStateInstance"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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
    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "reboot"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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
    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "logout"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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
    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "qr"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "getAuthorizationCode"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{ phoneNumber = $PhoneNumber }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "setProfilePicture"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        file = $base64File
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
}

function Update-WhatsappApiToken {
    <#
    .SYNOPSIS
    Get a new API token for the instance.
    .DESCRIPTION
    This function retrieves a new API token for your Green API instance.
    .EXAMPLE
    Update-WhatsappApiToken
    #>
    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "updateApiToken"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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
    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "getWaSettings"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
}

# --- Sending Advanced Messages Functions (New) ---

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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "sendPoll"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        chatId = $targetChatId
        message = $Message
        options = $Options
        multipleAnswers = $MultipleAnswers
    }
    if ($QuotedMessageId) { $Body.quotedMessageId = $QuotedMessageId }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "forwardMessages"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        chatId = $ChatId
        chatIdFrom = $ChatIdFrom
        messages = $Messages
    }
    if ($TypingTime) { $Body.typingTime = $TypingTime }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "sendInteractiveButtons"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $BodyPayload = @{
        chatId = $targetChatId
        body = $Body
        buttons = $Buttons
    }
    if ($Header) { $BodyPayload.header = $Header }
    if ($Footer) { $BodyPayload.footer = $Footer }
    $JsonBody = $BodyPayload | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "sendTyping"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        chatId = $targetChatId
        typingTime = $TypingTime
        typingType = $TypingType
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
}

# --- Journals and Queues Functions (New) ---



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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "getMessage"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        chatId = $targetChatId
        idMessage = $IdMessage
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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
    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "getMessagesCount"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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
    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "showMessagesQueue"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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
    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "clearMessagesQueue"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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
    param() # No parameters for this function

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "getWebhooksCount"
    $Method = "GET"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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
    param() # No parameters for this function

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "clearWebhooksQueue"
    $Method = "DELETE"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Headers = @{"Accept" = "application/json"}

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
}

# --- Group Management Functions (New) ---

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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "createGroup"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        groupName = $GroupName
        chatIds = $targetChatIds
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    if ($NewGroupName.Length -gt 100) {
        Write-Error "New group name cannot exceed 100 characters."
        return $null
    }

    $Endpoint = "updateGroupName"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        groupId = $GroupId
        groupName = $NewGroupName
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "getGroupData"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{ groupId = $GroupId }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "addGroupParticipant"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        groupId = $GroupId
        participantChatId = $targetChatId
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "removeGroupParticipant"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        groupId = $GroupId
        participantChatId = $targetChatId
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "setGroupAdmin"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        groupId = $GroupId
        participantChatId = $targetChatId
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "removeAdmin"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        groupId = $GroupId
        participantChatId = $targetChatId
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

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

    $Endpoint = "setGroupPicture"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{
        groupId = $GroupId
        file = $base64File
    }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        Write-Error "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
        return $null
    }

    $Endpoint = "leaveGroup"
    $Method = "POST"
    $Url = "$global:BaseUrl/$Endpoint/$global:Token" # Corrected URL construction
    $Body = @{ groupId = $GroupId }
    $JsonBody = $Body | ConvertTo-Json -Compress
    $Headers = @{"Accept" = "application/json"}
    $ContentType = "application/json"

    try {
        $response = Invoke-RestMethod -Uri $Url -Method $Method -Headers $Headers -ContentType $ContentType -Body $JsonBody -ErrorAction Stop
        return $response
    } catch {
        Write-Error "API Call to '$Endpoint' failed: $($_.Exception.Message)"
        if ($_.Exception.Response) {
            try {
                $ErrorResponse = $_.Exception.Response.GetResponseStream()
                $Reader = New-Object System.IO.StreamReader($ErrorResponse)
                $ErrorContent = $Reader.ReadToEnd()
                $ErrorDetails = $ErrorContent | ConvertFrom-Json
                if ($ErrorDetails -and $ErrorDetails.message) {
                    Write-Error "Green API Error Details: $($ErrorDetails.message) (Code: $($ErrorDetails.code))"
                } else {
                    Write-Error "Raw Error Response: $ErrorContent"
                }
            } catch {
                Write-Error "Could not parse detailed API error response from Green API."
            }
        }
        return $null
    }
}

# --- Status Management Functions (Beta) ---
<#
function Send-WhatsappTextStatus {
    <#
    .SYNOPSIS
    Sends a text-based WhatsApp status (beta feature).
    .DESCRIPTION
    Posts a text status update via Green API (if supported by your plan).
    .PARAMETER Message
    The status text (1-500 chars).
    .PARAMETER BackgroundColor
    Optional background color (name or hex).
    .PARAMETER Font
    Optional font name (e.g. "SERIF", "SANSSERIF").
    .PARAMETER ParticipantNumbers
    Optional phone numbers allowed to view this status. Specify only one of ParticipantNumbers or ParticipantChatIds.
    .PARAMETER ParticipantChatIds
    Optional chat IDs allowed to view this status. Specify only one of ParticipantNumbers or ParticipantChatIds.
    .OUTPUTS
    Returns API response or $null if not supported.
    #>
 <#   [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [ValidateNotNullOrEmpty()]
        [string]$Message,

        [Parameter(Mandatory = $false)]
        [string]$BackgroundColor,

        [Parameter(Mandatory = $false)]
        [string]$Font,

        [Parameter(Mandatory = $false)]
        [string[]]$ParticipantNumbers,

        [Parameter(Mandatory = $false)]
        [string[]]$ParticipantChatIds
    )

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        throw "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
    }

    if ($ParticipantNumbers -and $ParticipantChatIds) {
        throw "Specify only one of -ParticipantNumbers or -ParticipantChatIds, not both."
    }

    $endpoint = "sendStatusText"
    $url = "$global:BaseUrl/$endpoint/$global:Token"
    $body = @{ message = $Message }
    if ($BackgroundColor) { $body.backgroundColor = $BackgroundColor }
    if ($Font) { $body.font = $Font }
    if ($ParticipantNumbers) { $body.participantNumbers = $ParticipantNumbers }
    if ($ParticipantChatIds) { $body.participantChatIds = $ParticipantChatIds }

    try {
        $resp = Invoke-RestMethod -Uri $url -Method Post -Headers @{ "Content-Type" = "application/json" } -Body ($body | ConvertTo-Json -Depth 4) -ErrorAction Stop
        return $resp
    } catch {
        Write-Error "Failed to send text status: $($_.Exception.Message)"
        return $null
    }
}#>
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        throw "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
    }
    if ($ParticipantNumbers -and $ParticipantChatIds) {
        throw "Specify only one of -ParticipantNumbers or -ParticipantChatIds, not both."
    }

    $endpoint = "sendStatusAudio"
    $url = "$global:BaseUrl/$endpoint/$global:Token"
    $body = @{
        fileUrl = $FileUrl
        fileName = $FileName
    }
    if ($ParticipantNumbers) { $body.participantNumbers = $ParticipantNumbers }
    if ($ParticipantChatIds) { $body.participantChatIds = $ParticipantChatIds }

    try {
        $resp = Invoke-RestMethod -Uri $url -Method Post -Headers @{ "Content-Type" = "application/json" } -Body ($body | ConvertTo-Json -Depth 4) -ErrorAction Stop
        return $resp
    } catch {
        Write-Error "Failed to send voice status: $($_.Exception.Message)"
        return $null
    }
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

    if (-not $global:InstanceId -or -not $global:Token -or -not $global:BaseUrl) {
        throw "API credentials are not loaded. Please ensure Load-WhatsappConfig runs successfully."
    }
    if ($ParticipantNumbers -and $ParticipantChatIds) {
        throw "Specify only one of -ParticipantNumbers or -ParticipantChatIds, not both."
    }

    $endpoint = "sendStatusMedia"
    $url = "$global:BaseUrl/$endpoint/$global:Token"
    $body = @{
        fileUrl  = $FileUrl
        fileName = $FileName
    }
    if ($Caption) { $body.caption = $Caption }
    if ($ParticipantNumbers) { $body.participantNumbers = $ParticipantNumbers }
    if ($ParticipantChatIds) { $body.participantChatIds = $ParticipantChatIds }

    try {
        $resp = Invoke-RestMethod -Uri $url -Method Post -Headers @{ "Content-Type" = "application/json" } -Body ($body | ConvertTo-Json -Depth 4) -ErrorAction Stop
        return $resp
    } catch {
        Write-Error "Failed to send media status: $($_.Exception.Message)"
        return $null
    }
}
