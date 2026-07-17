Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# Import the module
Import-Module .\PHKustomWhatsapp.psd1 -Force

# --- Form Configuration ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "PHKustom-Whatsapp Chat Monitor"
$form.Size = New-Object System.Drawing.Size(650, 550)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#1E1E1E")
$form.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#D4D4D4")
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

# --- Global States ---
$script:activeChatId = $null
$script:activeSenderName = ""

# --- Title Header Panel ---
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = "Top"
$pnlHeader.Height = 50
$pnlHeader.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#252526")

$lblActiveChat = New-Object System.Windows.Forms.Label
$lblActiveChat.Text = "Active Chat: None (Waiting for incoming message...)"
$lblActiveChat.Location = New-Object System.Drawing.Point(15, 15)
$lblActiveChat.AutoSize = $true
$lblActiveChat.Font = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
$pnlHeader.Controls.Add($lblActiveChat)
$form.Controls.Add($pnlHeader)

# --- Bottom Input Panel ---
$pnlInput = New-Object System.Windows.Forms.Panel
$pnlInput.Dock = "Bottom"
$pnlInput.Height = 65
$pnlInput.Padding = New-Object System.Windows.Forms.Padding(10)
$pnlInput.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#252526")

$txtInput = New-Object System.Windows.Forms.TextBox
$txtInput.Location = New-Object System.Drawing.Point(15, 15)
$txtInput.Width = 480
$txtInput.Height = 30
$txtInput.Anchor = "Top, Left, Right"
$txtInput.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#2D2D2D")
$txtInput.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#F1F1F1")
$txtInput.BorderStyle = "FixedSingle"
$txtInput.Enabled = $false

$btnSend = New-Object System.Windows.Forms.Button
$btnSend.Text = "Send"
$btnSend.Location = New-Object System.Drawing.Point(510, 13)
$btnSend.Width = 100
$btnSend.Height = 28
$btnSend.Anchor = "Top, Right"
$btnSend.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0E639C")
$btnSend.ForeColor = [System.Drawing.Color]::White
$btnSend.FlatStyle = "Flat"
$btnSend.FlatAppearance.BorderSize = 0
$btnSend.Enabled = $false

$pnlInput.Controls.Add($txtInput)
$pnlInput.Controls.Add($btnSend)
$form.Controls.Add($pnlInput)

# --- History RichTextBox Panel ---
$rtbHistory = New-Object System.Windows.Forms.RichTextBox
$rtbHistory.Dock = "Fill"
$rtbHistory.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#1E1E1E")
$rtbHistory.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#D4D4D4")
$rtbHistory.BorderStyle = "None"
$rtbHistory.ReadOnly = $true
$rtbHistory.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$form.Controls.Add($rtbHistory)

# --- Status Bar ---
$statusBar = New-Object System.Windows.Forms.StatusStrip
$statusBar.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#007ACC")
$statusBar.ForeColor = [System.Drawing.Color]::White

$lblStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStatus.Text = "Listening for messages... "

$lblLastCheck = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblLastCheck.Text = " Last check: None"
$lblLastCheck.Alignment = "Right"

$statusBar.Items.Add($lblStatus) | Out-Null
$statusBar.Items.Add($lblLastCheck) | Out-Null
$form.Controls.Add($statusBar)

# --- Update Chat History Function ---
function Update-ChatHistoryView {
    if (-not $script:activeChatId) { return }
    
    # Retrieve last 10 messages from the chat
    $history = Get-ChatHistory -ChatId $script:activeChatId -Count 10
    if ($history) {
        $sorted = $history | Sort-Object timestamp
        
        $rtbHistory.Invoke([Action]{
            $rtbHistory.Clear()
            
            foreach ($msg in $sorted) {
                $time = [DateTimeOffset]::FromUnixTimeSeconds($msg.timestamp).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                if ($msg.type -eq 'outgoing') {
                    $sender = "Me"
                    $senderColor = [System.Drawing.ColorTranslator]::FromHtml("#569CD6") # Sleek Blue
                } else {
                    $sender = $msg.senderName
                    if ([string]::IsNullOrEmpty($sender)) {
                        $sender = $msg.senderId.Split('@')[0]
                    }
                    $senderColor = [System.Drawing.ColorTranslator]::FromHtml("#4EC9B0") # Sleek Green
                }
                
                # Append Time
                $rtbHistory.SelectionStart = $rtbHistory.TextLength
                $rtbHistory.SelectionLength = 0
                $rtbHistory.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml("#808080")
                $rtbHistory.AppendText("[$time] ")
                
                # Append Sender Name
                $rtbHistory.SelectionStart = $rtbHistory.TextLength
                $rtbHistory.SelectionColor = $senderColor
                $rtbHistory.SelectionFont = New-Object System.Drawing.Font($rtbHistory.Font, [System.Drawing.FontStyle]::Bold)
                $rtbHistory.AppendText("$sender: ")
                
                # Append Message Text
                $rtbHistory.SelectionStart = $rtbHistory.TextLength
                $rtbHistory.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml("#E0E0E0")
                $rtbHistory.SelectionFont = New-Object System.Drawing.Font($rtbHistory.Font, [System.Drawing.FontStyle]::Regular)
                $rtbHistory.AppendText("$($hMsgText = $msg.textMessage)`r`n")
            }
            
            # Auto scroll to bottom
            $rtbHistory.SelectionStart = $rtbHistory.TextLength
            $rtbHistory.ScrollToCaret()
        })
    }
}

# --- Timer Polling Logic ---
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000 # Poll every 2 seconds

$timer.Add_Tick({
    $timer.Stop() # Stop during network calls
    
    try {
        $notification = Receive-WhatsappNotification
        
        if ($notification -and $notification.body) {
            $receiptId = $notification.receiptId
            $messageData = $notification.body
            
            # Immediately delete processed webhook
            Remove-WhatsappNotification -ReceiptId $receiptId | Out-Null
            
            if ($messageData.typeWebhook -eq 'incomingMessageReceived' -and $messageData.messageData.typeMessage -eq 'textMessage') {
                $script:activeChatId = $messageData.senderData.chatId
                $script:activeSenderName = $messageData.senderData.senderName
                if ([string]::IsNullOrEmpty($script:activeSenderName)) {
                    $script:activeSenderName = $messageData.senderData.sender.Split('@')[0]
                }
                
                $lblActiveChat.Text = "Active Chat: $script:activeSenderName ($($messageData.senderData.sender))"
                $txtInput.Enabled = $true
                $btnSend.Enabled = $true
                
                Update-ChatHistoryView
                
                # Play alert sound
                [System.Media.SystemSounds]::Asterisk.Play()
                $lblStatus.Text = "New message received from $script:activeSenderName"
            }
        } else {
            $lblStatus.Text = "Listening for messages... (No new updates)"
        }
    } catch {
        $lblStatus.Text = "Polling Error: $_"
    }
    
    $lblLastCheck.Text = "Last check: $((Get-Date).ToString('HH:mm:ss'))"
    $timer.Start()
})

# --- Send Message Action ---
$SendMessageAction = {
    $text = $txtInput.Text.Trim()
    if ($text -and $script:activeChatId) {
        $txtInput.Text = ""
        $lblStatus.Text = "Sending message..."
        
        # Disable inputs briefly
        $txtInput.Enabled = $false
        $btnSend.Enabled = $false
        
        try {
            $response = Send-Whatsapp -ChatId $script:activeChatId -Message $text
            if ($response -and $response.idMessage) {
                $lblStatus.Text = "Message sent successfully!"
                Update-ChatHistoryView
            } else {
                $lblStatus.Text = "Failed to send message."
            }
        } catch {
            $lblStatus.Text = "Send Error: $_"
        }
        
        $txtInput.Enabled = $true
        $btnSend.Enabled = $true
        $txtInput.Focus()
    }
}

# --- Event Binding ---
$btnSend.Add_Click($SendMessageAction)
$txtInput.Add_KeyDown({
    if ($_.KeyCode -eq "Enter") {
        $SendMessageAction.Invoke()
        $_.SuppressKeyPress = $true
    }
})

$form.Add_Load({
    $timer.Start()
})

$form.Add_FormClosing({
    $timer.Stop()
})

# Run the form
$form.ShowDialog() | Out-Null
