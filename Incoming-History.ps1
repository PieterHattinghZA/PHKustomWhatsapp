Import-Module .\PHKustomWhatsapp.psd1 -Force

# Retrieve incoming messages from the last 50 minutes
$messages = Get-LastIncomingMessages -Minutes 50

if ($messages) {
    foreach ($msg in $messages) {
        $time = [DateTimeOffset]::FromUnixTimeSeconds($msg.timestamp).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
        Write-Host "[$time] From: $($msg.senderName) ($($msg.senderId)) | Message: $($msg.textMessage)" -ForegroundColor Green
    }
} else {
    Write-Host "No incoming messages in the last 50 minutes." -ForegroundColor Yellow
}
