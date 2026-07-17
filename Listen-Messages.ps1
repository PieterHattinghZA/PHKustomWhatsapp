Import-Module .\PHKustomWhatsapp.psd1 -Force

Write-Host "Monitoring WhatsApp for new incoming messages... Press Ctrl+C to stop." -ForegroundColor Cyan

while ($true) {
    try {
        # Check for a new notification in the queue
        $notification = Receive-WhatsappNotification

        if ($notification -and $notification.body) {
            $receiptId = $notification.receiptId
            $messageData = $notification.body

            # Immediately remove the notification from the queue so it is not processed again
            Remove-WhatsappNotification -ReceiptId $receiptId | Out-Null

            # We only process incoming text messages
            if ($messageData.typeWebhook -eq 'incomingMessageReceived' -and $messageData.messageData.typeMessage -eq 'textMessage') {
                $chatId = $messageData.senderData.chatId
                $senderName = $messageData.senderData.senderName
                $senderNumber = $messageData.senderData.sender
                $newMsgText = $messageData.messageData.textMessageData.textMessage
                $newMsgTime = [DateTimeOffset]::FromUnixTimeSeconds($notification.body.timestamp).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")

                Write-Host "`n==================================================" -ForegroundColor Yellow
                Write-Host "🔔 NEW MESSAGE RECEIVED AT $newMsgTime" -ForegroundColor Yellow
                Write-Host "Sender: $senderName ($senderNumber)" -ForegroundColor Yellow
                Write-Host "Message: $newMsgText" -ForegroundColor Yellow
                Write-Host "==================================================" -ForegroundColor Yellow
                Write-Host "Fetching previous chat history..." -ForegroundColor Gray

                # Fetch history for this chat (Count 6: the new message + 5 previous ones)
                $history = Get-ChatHistory -ChatId $chatId -Count 6

                if ($history) {
                    # Sort oldest to newest for natural reading order
                    $sortedHistory = $history | Sort-Object timestamp
                    
                    Write-Host "`n--- Recent Conversation History ---" -ForegroundColor Blue
                    foreach ($hMsg in $sortedHistory) {
                        $hTime = [DateTimeOffset]::FromUnixTimeSeconds($hMsg.timestamp).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                        
                        # Determine sender name to display
                        if ($hMsg.type -eq 'outgoing') {
                            $displayName = "Me"
                            $color = "Cyan"
                        } else {
                            $displayName = $hMsg.senderName
                            if ([string]::IsNullOrEmpty($displayName)) {
                                $displayName = $hMsg.senderId.Split('@')[0]
                            }
                            $color = "Green"
                        }
                        
                        # Highlight the brand new message we just received
                        if ($hMsg.idMessage -eq $messageData.idMessage) {
                            Write-Host "[$hTime] [$displayName] (NEW): $($hMsg.textMessage)" -ForegroundColor Magenta
                        } else {
                            Write-Host "[$hTime] [$displayName]: $($hMsg.textMessage)" -ForegroundColor $color
                        }
                    }
                    Write-Host "----------------------------------`n" -ForegroundColor Blue
                } else {
                    Write-Host "No chat history found." -ForegroundColor DarkGray
                }
            }
        }
    } catch {
        Write-Error "Error in listener loop: $_"
    }

    # Short delay to prevent hammering the API too aggressively
    Start-Sleep -Seconds 2
}
