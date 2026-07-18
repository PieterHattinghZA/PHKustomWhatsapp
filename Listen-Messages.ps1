Import-Module .\PHKustomWhatsapp.psd1 -Force

# --- Ensure Databases and Config Folder Exists ---
$dbDir = Join-Path $env:APPDATA "PHWhatsapp\Database"
if (-not (Test-Path $dbDir)) {
    New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
}

Write-Host "Monitoring WhatsApp for new incoming messages... Press Ctrl+C to stop." -ForegroundColor Cyan

while ($true) {
    try {
        $notification = Receive-WhatsappNotification

        if ($notification -and $notification.body) {
            $receiptId = $notification.receiptId
            $messageData = $notification.body

            Remove-WhatsappNotification -ReceiptId $receiptId | Out-Null

            if ($messageData.typeWebhook -eq 'incomingMessageReceived' -and $messageData.messageData.typeMessage -eq 'textMessage') {
                $chatId = $messageData.senderData.chatId
                $senderName = $messageData.senderData.senderName
                $senderNumber = $messageData.senderData.sender
                $newMsgText = $messageData.messageData.textMessageData.textMessage
                $newMsgTime = [DateTimeOffset]::FromUnixTimeSeconds($notification.body.timestamp).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")

                Write-Host "`n==================================================" -ForegroundColor Yellow
                Write-Host "NEW MESSAGE RECEIVED AT $newMsgTime" -ForegroundColor Yellow
                Write-Host "Sender: $senderName ($senderNumber)" -ForegroundColor Yellow
                Write-Host "Message: $newMsgText" -ForegroundColor Yellow
                Write-Host "==================================================" -ForegroundColor Yellow
                
                # Create Database message record
                $dbPayload = [PSCustomObject]@{
                    idMessage    = $messageData.idMessage
                    timestamp    = $messageData.timestamp
                    type         = "incoming"
                    chatId       = $chatId
                    senderId     = $senderNumber
                    senderName   = $senderName
                    typeMessage  = "textMessage"
                    textMessage  = $newMsgText
                    caption      = $null
                    fileName     = $null
                    jpegThumbnail= $null
                }

                # Journal message to local JSON database file
                Save-LocalChatMessage -ChatId $chatId -MessageObj $dbPayload

                Write-Host "Fetching previous chat history natively..." -ForegroundColor Gray

                # Read from native local JSON file instead of hammering the web API
                $history = Get-LocalChatHistory -ChatId $chatId -Count 6

                if ($history) {
                    $sortedHistory = $history | Sort-Object timestamp
                    
                    Write-Host "`n--- Recent Conversation History (Local Database) ---" -ForegroundColor Blue
                    foreach ($hMsg in $sortedHistory) {
                        # Legacy data structures adapter fallback hooks
                        if ([string]::IsNullOrEmpty($hMsg.typeMessage)) {
                            if ($hMsg.type -eq 'outgoing') {
                                $hMsg.typeMessage = 'textMessage'
                            } else {
                                if ($hMsg.fileName -or $hMsg.jpegThumbnail) {
                                    $hMsg.typeMessage = 'documentMessage'
                                } else {
                                    $hMsg.typeMessage = 'textMessage'
                                }
                            }
                        }
                        
                        if ([string]::IsNullOrEmpty($hMsg.textMessage) -and $hMsg.message) {
                            $hMsg.textMessage = $hMsg.message
                        }
                        if ([string]::IsNullOrEmpty($hMsg.textMessage) -and $hMsg.body) {
                            $hMsg.textMessage = $hMsg.body
                        }

                        $hTime = [DateTimeOffset]::FromUnixTimeSeconds($hMsg.timestamp).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                        
                        if ($hMsg.type -eq 'outgoing') {
                            $displayName = "Me"
                            $color = "Cyan"
                        } else {
                            $displayName = $hMsg.senderName
                            if ([string]::IsNullOrEmpty($displayName)) {
                                if ($hMsg.senderId) {
                                    $displayName = $hMsg.senderId.Split('@')[0]
                                } else {
                                    $displayName = "Unknown"
                                }
                            }
                            $color = "Green"
                        }
                        
                        if ($hMsg.idMessage -eq $messageData.idMessage) {
                            Write-Host "[$hTime] [$displayName] (NEW): $($hMsg.textMessage)" -ForegroundColor Magenta
                        } else {
                            Write-Host "[$hTime] [$displayName]: $($hMsg.textMessage)" -ForegroundColor $color
                        }
                    }
                    Write-Host "----------------------------------------------------`n" -ForegroundColor Blue
                } else {
                    Write-Host "No chat history found." -ForegroundColor DarkGray
                }
            }
        }
    } catch {
        Write-Error "Error in listener loop: $_"
    }

    Start-Sleep -Seconds 2
}