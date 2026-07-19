Import-Module .\PHKustomWhatsapp.psd1 -Force

# --- Setup Native File Targets ---
$dbDir = Join-Path $env:APPDATA "PHWhatsapp\Database"
if (-not (Test-Path $dbDir)) {
    New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
}

Write-Host "Initializing Full Cloud-to-Local Database Extraction (Paced Mode)..." -ForegroundColor Cyan

# 1. Fetch all available contacts from account journal
Write-Host "Retrieving WhatsApp Contacts list..." -ForegroundColor Gray
$contacts = Get-Contacts

if (-not $contacts) {
    Write-Error "Failed to pull contacts. Please ensure your Green API instance is online and active."
    Exit
}

Write-Host "Found $($contacts.Count) active contact channels. Starting paced backup journal creation...`n" -ForegroundColor Green

# 2. Iterate through contacts and write raw JSON history files
$count = 0
foreach ($contact in $contacts) {
    $chatId = $contact.id
    $chatName = $contact.name
    if ([string]::IsNullOrEmpty($chatName)) {
        $chatName = $chatId.Split('@')[0]
    }

    $count++
    if ($chatId -eq '0@c.us') {
        Write-Host "[$count/$($contacts.Count)] Skipping system channel: $chatName ($chatId)..." -ForegroundColor Gray
        continue
    }

    Write-Host "[$count/$($contacts.Count)] Syncing target thread: $chatName ($chatId)..." -ForegroundColor Yellow

    try {
        # Fetch deep history log from cloud container node
        $cloudHistory = Get-ChatHistory -ChatId $chatId -Count 100 -ErrorAction Stop
        
        if ($cloudHistory) {
            $sortedCloud = $cloudHistory | Sort-Object timestamp
            $savedMessagesCount = 0
            
            foreach ($cMsg in $sortedCloud) {
                # Map payload parameters structurally to match layout engine specifications
                $dbPayload = [PSCustomObject]@{
                    idMessage     = $cMsg.idMessage
                    timestamp     = $cMsg.timestamp
                    type          = $cMsg.type
                    chatId        = $chatId
                    senderId      = $cMsg.senderId
                    senderName    = $chatName
                    typeMessage   = $cMsg.typeMessage
                    textMessage   = $cMsg.textMessage
                    caption       = $cMsg.caption
                    fileName      = $cMsg.fileName
                    jpegThumbnail = $cMsg.jpegThumbnail
                }

                # Parse embedded data nodes for file assets
                if ($cMsg.typeMessage -eq 'imageMessage' -and $cMsg.imageMessageData) {
                    $dbPayload.caption = $cMsg.imageMessageData.caption
                    $dbPayload.jpegThumbnail = $cMsg.imageMessageData.jpegThumbnail
                } elseif ($cMsg.typeMessage -eq 'videoMessage' -and $cMsg.videoMessageData) {
                    $dbPayload.caption = $cMsg.videoMessageData.caption
                } elseif ($cMsg.typeMessage -eq 'documentMessage' -and $cMsg.documentMessageData) {
                    $dbPayload.caption = $cMsg.documentMessageData.caption
                    $dbPayload.fileName = $cMsg.documentMessageData.fileName
                }

                # Commit entry natively into file structures
                Save-LocalChatMessage -ChatId $chatId -MessageObj $dbPayload
                $savedMessagesCount++
            }
            Write-Host "   -> Successfully backed up $savedMessagesCount messages to local JSON database log." -ForegroundColor Green
        } else {
            Write-Host "   -> Conversation thread is clean (0 active cloud entries recorded)." -ForegroundColor Gray
        }
    } catch {
        Write-Host "   -> Skipping thread link context loop due to error: $_" -ForegroundColor DarkGray
    }

    # MANDATORY PROTECTIVE DELAY: Pauses execution for 2 seconds to respect API rate limits
    Start-Sleep -Seconds 2
}

Write-Host "`nDatabase generation cycle finished. All logs are permanently written out to: $dbDir" -ForegroundColor Cyan