
# Fetch the next notification from the queue
$notification = Receive-WhatsappNotification

if ($notification -and $notification.body) {
    $receiptId = $notification.receiptId
    $messageData = $notification.body

    # Check if it is an incoming message
    if ($messageData.typeWebhook -eq 'incomingMessageReceived') {
        $senderId = $messageData.senderData.sender
        $text = $messageData.messageData.textMessageData.textMessage
        
        Write-Host "Received message from $senderId : $text" -ForegroundColor Green
    }

    # IMPORTANT: Remove the notification from the queue so it is not processed again
    Remove-WhatsappNotification -ReceiptId $receiptId | Out-Null
} else {
    Write-Host "No new notifications." -ForegroundColor Yellow
}
