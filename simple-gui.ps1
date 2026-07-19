Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# Import the module and load configurations
Import-Module .\PHKustomWhatsapp.psd1 -Force
Get-WhatsappConfig | Out-Null

# --- Load SQLite library ---
$sqliteDll = "c:\Scripts\PHKustom-Whatsapp\SQLite\System.Data.SQLite.dll"
if (-not (Test-Path $sqliteDll)) {
    Write-Error "System.Data.SQLite.dll not found. Please verify the setup under $sqliteDll"
    exit
}
Add-Type -Path $sqliteDll

# --- Ensure Databases and Config Folder Exists ---
$dbDir = Join-Path $env:APPDATA "PHWhatsapp\Database"
if (-not (Test-Path $dbDir)) {
    New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
}
# --- Design Palette Constants ---
$script:colorMainBg      = [System.Drawing.ColorTranslator]::FromHtml("#111B21")
$script:colorSidebarBg   = [System.Drawing.ColorTranslator]::FromHtml("#18191a")
$script:colorHeaderBg    = [System.Drawing.ColorTranslator]::FromHtml("#202C33")
$script:colorChatBg      = [System.Drawing.ColorTranslator]::FromHtml("#222e35")
$script:colorInputBg     = [System.Drawing.ColorTranslator]::FromHtml("#202C33")
$script:colorTextMain    = [System.Drawing.ColorTranslator]::FromHtml("#E9EDEF")
$script:colorTextMuted   = [System.Drawing.ColorTranslator]::FromHtml("#8696A0")
$script:colorAccent      = [System.Drawing.ColorTranslator]::FromHtml("#00c278")
$script:colorSelectBg    = [System.Drawing.ColorTranslator]::FromHtml("#2a3942")
$script:colorBubbleIn    = [System.Drawing.ColorTranslator]::FromHtml("#202C33")
$script:colorBubbleOut   = [System.Drawing.ColorTranslator]::FromHtml("#005C4B")

$script:fontSegoeRegular = New-Object System.Drawing.Font("Segoe UI", 9.5)

# --- Global States ---
$script:activeChatId = $null
$script:activeSenderName = ""
$script:contactsMapping = @{}     # DisplayName -> ChatId
$script:contactsCache = @{}       # ChatId -> Contact Details Object
$script:allContacts = @()         # Full list of WhatsApp contacts from API/Cache

# --- Circle Initials-based Avatar Color Palette ---
$script:avatarColors = @(
    "#26A69A", "#5C6BC0", "#26C6DA", "#29B6F6", "#78909C",
    "#AB47BC", "#EC407A", "#7E57C2", "#FFA726", "#26A69A"
)

# --- Helper: Get deterministic color based on name hash ---
function Get-AvatarColor {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) { return [System.Drawing.Color]::Gray }
    $hash = 0
    foreach ($char in $Name.ToCharArray()) {
        $hash += [int]$char
    }
    $colorIndex = $hash % $script:avatarColors.Length
    return [System.Drawing.ColorTranslator]::FromHtml($script:avatarColors[$colorIndex])
}

# --- Helper: Get 1 or 2 letter initials ---
function Get-Initials {
    param([string]$Name)
    if ([string]::IsNullOrEmpty($Name)) { return "?" }
    $parts = $Name.Split(' ', [System.StringSplitOptions]::RemoveEmptyEntries)
    if ($parts.Length -eq 1) {
        return $parts[0].Substring(0, [Math]::Min(2, $parts[0].Length)).ToUpper()
    }
    elseif ($parts.Length -ge 2) {
        return ($parts[0].Substring(0, 1) + $parts[1].Substring(0, 1)).ToUpper()
    }
    return "?"
}

# --- Initialize SQL Database ---
function Initialize-Database {
    $dbPath = Join-Path $env:APPDATA "PHWhatsapp\whatsapp.db"
    $script:conn = New-Object System.Data.SQLite.SQLiteConnection("Data Source=$dbPath")
    $script:conn.Open()
    
    $cmd = $script:conn.CreateCommand()
    $cmd.CommandText = @"
CREATE TABLE IF NOT EXISTS messages (
    idMessage TEXT PRIMARY KEY,
    chatId TEXT,
    timestamp INTEGER,
    type TEXT,
    senderId TEXT,
    senderName TEXT,
    typeMessage TEXT,
    textMessage TEXT,
    caption TEXT,
    fileName TEXT,
    fileBytes BLOB
);
"@
    $cmd.ExecuteNonQuery() | Out-Null
    $cmd.Dispose()
}

# --- Save Message to SQL with Binary BLOB Attachments ---
function Save-ChatMessageToSql {
    param(
        [PSCustomObject]$msg
    )
    
    # 1. Download attachment bytes if media
    $bytes = $null
    $mediaTypes = @('imageMessage', 'videoMessage', 'documentMessage', 'audioMessage')
    if ($mediaTypes -contains $msg.typeMessage) {
        if ($msg.fileBytes) {
            $bytes = $msg.fileBytes
        }
        else {
            # Try to download the file directly from Green API using temporary storage
            $tempPath = [System.IO.Path]::GetTempFileName()
            try {
                $success = Get-WhatsappFile -ChatId $msg.chatId -MessageId $msg.idMessage -SavePath $tempPath
                if ($success -and (Test-Path $tempPath)) {
                    $bytes = [System.IO.File]::ReadAllBytes($tempPath)
                }
            }
            catch {}
            finally {
                if (Test-Path $tempPath) { Remove-Item $tempPath -Force }
            }
        }
    }
    
    # 2. Insert into SQLite table
    $cmd = $script:conn.CreateCommand()
    $cmd.CommandText = @"
INSERT OR REPLACE INTO messages 
(idMessage, chatId, timestamp, type, senderId, senderName, typeMessage, textMessage, caption, fileName, fileBytes)
VALUES 
(@idMessage, @chatId, @timestamp, @type, @senderId, @senderName, @typeMessage, @textMessage, @caption, @fileName, @fileBytes)
"@
    $cmd.Parameters.AddWithValue("@idMessage", $msg.idMessage) | Out-Null
    $cmd.Parameters.AddWithValue("@chatId", $msg.chatId) | Out-Null
    $cmd.Parameters.AddWithValue("@timestamp", [int64]$msg.timestamp) | Out-Null
    $cmd.Parameters.AddWithValue("@type", $msg.type) | Out-Null
    $cmd.Parameters.AddWithValue("@senderId", $msg.senderId) | Out-Null
    $cmd.Parameters.AddWithValue("@senderName", $msg.senderName) | Out-Null
    $cmd.Parameters.AddWithValue("@typeMessage", $msg.typeMessage) | Out-Null
    $cmd.Parameters.AddWithValue("@textMessage", $msg.textMessage) | Out-Null
    $cmd.Parameters.AddWithValue("@caption", $msg.caption) | Out-Null
    $cmd.Parameters.AddWithValue("@fileName", $msg.fileName) | Out-Null
    
    $blobParam = New-Object System.Data.SQLite.SQLiteParameter("@fileBytes", [System.Data.DbType]::Binary)
    if ($bytes) {
        $blobParam.Value = $bytes
    } else {
        $blobParam.Value = [System.DBNull]::Value
    }
    $cmd.Parameters.Add($blobParam) | Out-Null
    
    $cmd.ExecuteNonQuery() | Out-Null
    $cmd.Dispose()
}

# --- Fetch Chat History from SQL ---
function Get-ChatHistoryFromSql {
    param(
        [string]$chatId
    )
    $cmd = $script:conn.CreateCommand()
    $cmd.CommandText = "SELECT * FROM messages WHERE chatId = @chatId ORDER BY timestamp ASC"
    $cmd.Parameters.AddWithValue("@chatId", $chatId) | Out-Null
    
    $reader = $cmd.ExecuteReader()
    $history = @()
    while ($reader.Read()) {
        $fileBytes = $null
        if (-not $reader.IsDBNull($reader.GetOrdinal("fileBytes"))) {
            $fileBytes = $reader.GetValue($reader.GetOrdinal("fileBytes"))
        }
        
        $history += [PSCustomObject]@{
            idMessage   = $reader.GetString($reader.GetOrdinal("idMessage"))
            chatId      = $reader.GetString($reader.GetOrdinal("chatId"))
            timestamp   = $reader.GetInt64($reader.GetOrdinal("timestamp"))
            type        = $reader.GetString($reader.GetOrdinal("type"))
            senderId    = if ($reader.IsDBNull($reader.GetOrdinal("senderId"))) { $null } else { $reader.GetString($reader.GetOrdinal("senderId")) }
            senderName  = if ($reader.IsDBNull($reader.GetOrdinal("senderName"))) { $null } else { $reader.GetString($reader.GetOrdinal("senderName")) }
            typeMessage = $reader.GetString($reader.GetOrdinal("typeMessage"))
            textMessage = if ($reader.IsDBNull($reader.GetOrdinal("textMessage"))) { $null } else { $reader.GetString($reader.GetOrdinal("textMessage")) }
            caption     = if ($reader.IsDBNull($reader.GetOrdinal("caption"))) { $null } else { $reader.GetString($reader.GetOrdinal("caption")) }
            fileName    = if ($reader.IsDBNull($reader.GetOrdinal("fileName"))) { $null } else { $reader.GetString($reader.GetOrdinal("fileName")) }
            fileBytes   = $fileBytes
        }
    }
    $reader.Close()
    $cmd.Dispose()
    return $history
}

# --- Fetch Active Chats list from SQL ---
function Get-ActiveChatsFromSql {
    $cmd = $script:conn.CreateCommand()
    $cmd.CommandText = @"
SELECT m.chatId, m.senderName, m.textMessage, m.caption, m.typeMessage, m.timestamp 
FROM messages m
INNER JOIN (
    SELECT chatId, MAX(timestamp) as max_ts 
    FROM messages 
    GROUP BY chatId
) t ON m.chatId = t.chatId AND m.timestamp = t.max_ts
ORDER BY m.timestamp DESC
"@
    $reader = $cmd.ExecuteReader()
    $chats = @()
    while ($reader.Read()) {
        $chatId = $reader.GetString($reader.GetOrdinal("chatId"))
        $senderName = if ($reader.IsDBNull($reader.GetOrdinal("senderName"))) { $null } else { $reader.GetString($reader.GetOrdinal("senderName")) }
        $textMessage = if ($reader.IsDBNull($reader.GetOrdinal("textMessage"))) { $null } else { $reader.GetString($reader.GetOrdinal("textMessage")) }
        $caption = if ($reader.IsDBNull($reader.GetOrdinal("caption"))) { $null } else { $reader.GetString($reader.GetOrdinal("caption")) }
        $typeMessage = $reader.GetString($reader.GetOrdinal("typeMessage"))
        $timestamp = $reader.GetInt64($reader.GetOrdinal("timestamp"))
        
        $displayName = $senderName
        if ([string]::IsNullOrEmpty($displayName)) {
            $displayName = $chatId.Split('@')[0]
        }
        
        $lastText = "Click to chat..."
        if ($typeMessage -eq 'textMessage') {
            $lastText = $textMessage
        } elseif ($caption) {
            $lastText = $caption
        } else {
            $lastText = "[$typeMessage]"
        }
        
        # Convert timestamp to human-readable string
        $timeStr = ""
        $localTime = [DateTimeOffset]::FromUnixTimeSeconds($timestamp).LocalDateTime
        if ($localTime.Date -eq [DateTime]::Today) {
            $timeStr = $localTime.ToString("HH:mm")
        } elseif ($localTime.Date -eq [DateTime]::Today.AddDays(-1)) {
            $timeStr = "Yesterday"
        } else {
            $timeStr = $localTime.ToString("yyyy-MM-dd")
        }
        
        $chats += [PSCustomObject]@{
            ChatId      = $chatId
            DisplayName = $displayName
            LastText    = $lastText
            TimeStr     = $timeStr
            Timestamp   = $timestamp
        }
    }
    $reader.Close()
    $cmd.Dispose()
    return $chats
}

# --- Helper: Get flat list of message objects from nested JSON ---
function Get-FlatMessages {
    param($obj)
    $results = @()
    if ($obj -is [System.Collections.IEnumerable] -and $obj -isnot [string]) {
        foreach ($item in $obj) {
            $results += Get-FlatMessages $item
        }
    }
    elseif ($obj.value) {
        $results += Get-FlatMessages $obj.value
    }
    elseif ($obj.idMessage) {
        $results += $obj
    }
    return $results
}

# --- Sync Local JSON file history to SQL DB initially ---
function Sync-JsonHistoryToSql {
    $historyFiles = Get-ChildItem -Path $dbDir -Filter "history_*.json"
    foreach ($file in $historyFiles) {
        if ($file.BaseName -match '^history_(.+)$') {
            $rawId = $Matches[1]
            $fullChatId = if ($rawId -match '@') { $rawId } else { "$rawId@c.us" }
            
            try {
                $rawContent = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
                if ($rawContent) {
                    $json = ConvertFrom-Json $rawContent
                    $messages = @(Get-FlatMessages $json)
                    foreach ($m in $messages) {
                        $checkCmd = $script:conn.CreateCommand()
                        $checkCmd.CommandText = "SELECT COUNT(*) FROM messages WHERE idMessage = @id"
                        $checkCmd.Parameters.AddWithValue("@id", $m.idMessage) | Out-Null
                        $count = $checkCmd.ExecuteScalar()
                        $checkCmd.Dispose()
                        
                        if ($count -eq 0) {
                            $msgObj = [PSCustomObject]@{
                                idMessage   = $m.idMessage
                                chatId      = if ($m.chatId) { $m.chatId } else { $fullChatId }
                                timestamp   = $m.timestamp
                                type        = $m.type
                                senderId    = $m.senderId
                                senderName  = if ($m.senderName) { $m.senderName } else { $rawId }
                                typeMessage = if ($m.typeMessage) { $m.typeMessage } else { "textMessage" }
                                textMessage = $m.textMessage
                                caption     = $m.caption
                                fileName    = $m.fileName
                                fileBytes   = $null
                            }
                            Save-ChatMessageToSql -msg $msgObj
                        }
                    }
                }
            } catch {}
        }
    }
}

# --- Main Window Form Configuration ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "WhatsApp Local SQL Media Console"
$form.Size = New-Object System.Drawing.Size(1150, 750)
$form.StartPosition = "CenterScreen"
$form.BackColor = $script:colorMainBg
$form.ForeColor = $script:colorTextMain
$form.Font = $script:fontSegoeRegular

# --- Layout Container Split ---
$splitContainer = New-Object System.Windows.Forms.SplitContainer
$splitContainer.Dock = "Fill"
$splitContainer.SplitterDistance = [int]($form.ClientSize.Width * 0.20)
$splitContainer.BackColor = $script:colorMainBg
$splitContainer.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$form.Controls.Add($splitContainer)

# Left Column Panel
$pnlLeft = $splitContainer.Panel1
$pnlLeft.BackColor = $script:colorSidebarBg

# Right Column Panel
$pnlRight = $splitContainer.Panel2
$pnlRight.BackColor = $script:colorChatBg

# --- Left Column Header Panel (Chats & Add Contact) ---
$pnlLeftHeader = New-Object System.Windows.Forms.Panel
$pnlLeftHeader.Dock = "Top"
$pnlLeftHeader.Height = 60
$pnlLeftHeader.BackColor = $script:colorSidebarBg

$btnNewChat = New-Object System.Windows.Forms.Button
$btnNewChat.Size = New-Object System.Drawing.Size(28, 28)
$btnNewChat.Text = "+"
$btnNewChat.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnNewChat.FlatAppearance.BorderSize = 1
$btnNewChat.FlatAppearance.BorderColor = $script:colorTextMuted
$btnNewChat.BackColor = [System.Drawing.Color]::Transparent
$btnNewChat.ForeColor = $script:colorTextMain
$btnNewChat.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$btnNewChat.Cursor = [System.Windows.Forms.Cursors]::Hand

$pnlLeftHeader.Controls.Add($btnNewChat)

# Handle Left Header resizing and component positions
$pnlLeftHeader.Add_Resize({
    $btnNewChat.Location = New-Object System.Drawing.Point(($pnlLeftHeader.Width - $btnNewChat.Width - 15), 16)
})

# Custom Paint event to draw "Chats" title and "SQL Database" badge
$pnlLeftHeader.Add_Paint({
    param($evtSender, $e)
    $graphics = $e.Graphics
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    
    # Draw "Chats" Text
    $chatsFont = New-Object System.Drawing.Font("Segoe UI", 18, [System.Drawing.FontStyle]::Bold)
    $chatsBrush = New-Object System.Drawing.SolidBrush($script:colorTextMain)
    $graphics.DrawString("Chats", $chatsFont, $chatsBrush, 15, 12)
    
    # Draw "SQL DB" Badge Background
    $badgeFont = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
    $badgeText = "SQL DB"
    $badgeSize = $graphics.MeasureString($badgeText, $badgeFont)
    
    $badgeRect = [System.Drawing.Rectangle]::new(95, 21, [int]($badgeSize.Width + 12), [int]($badgeSize.Height + 4))
    $badgeBgBrush = New-Object System.Drawing.SolidBrush([System.Drawing.ColorTranslator]::FromHtml("#102d1d"))
    
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $radius = 6
    $path.AddArc($badgeRect.X, $badgeRect.Y, $radius, $radius, 180, 90)
    $path.AddArc(($badgeRect.Right - $radius), $badgeRect.Y, $radius, $radius, 270, 90)
    $path.AddArc(($badgeRect.Right - $radius), ($badgeRect.Bottom - $radius), $radius, $radius, 0, 90)
    $path.AddArc($badgeRect.X, ($badgeRect.Bottom - $radius), $radius, $radius, 90, 90)
    $path.CloseAllFigures()
    
    $graphics.FillPath($badgeBgBrush, $path)
    
    # Draw Badge Text
    $badgeTextBrush = New-Object System.Drawing.SolidBrush($script:colorAccent)
    $graphics.DrawString($badgeText, $badgeFont, $badgeTextBrush, ($badgeRect.X + 6), ($badgeRect.Y + 2))
    
    # Cleanup resources
    $chatsFont.Dispose()
    $chatsBrush.Dispose()
    $badgeFont.Dispose()
    $badgeBgBrush.Dispose()
    $badgeTextBrush.Dispose()
    $path.Dispose()
})

$pnlLeft.Controls.Add($pnlLeftHeader)

# Contact ListBox (Owner Drawn - Displays only contacts with active chats in SQL)
$lstContacts = New-Object System.Windows.Forms.ListBox
$lstContacts.Dock = "Fill"
$lstContacts.BackColor = $script:colorSidebarBg
$lstContacts.ForeColor = $script:colorTextMain
$lstContacts.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$lstContacts.Font = New-Object System.Drawing.Font("Segoe UI", 10.5)
$lstContacts.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$lstContacts.ItemHeight = 45
$pnlLeft.Controls.Add($lstContacts)

# --- Right Column Panels Layout ---

# Active Chat Header Panel
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = "Top"
$pnlHeader.Height = 60
$pnlHeader.BackColor = $script:colorHeaderBg

$lblActiveContact = New-Object System.Windows.Forms.Label
$lblActiveContact.Location = New-Object System.Drawing.Point(70, 12)
$lblActiveContact.Size = New-Object System.Drawing.Size(600, 20)
$lblActiveContact.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$lblActiveContact.ForeColor = $script:colorTextMain
$lblActiveContact.Text = "Select an active chat"

$lblActiveStatus = New-Object System.Windows.Forms.Label
$lblActiveStatus.Location = New-Object System.Drawing.Point(70, 32)
$lblActiveStatus.Size = New-Object System.Drawing.Size(600, 15)
$lblActiveStatus.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblActiveStatus.ForeColor = $script:colorTextMuted
$lblActiveStatus.Text = ""

$pnlHeader.Controls.AddRange(@($lblActiveContact, $lblActiveStatus))
$pnlRight.Controls.Add($pnlHeader)

# Message History Scrollable Panel (renders custom controls for text, images, and videos)
$pnlChatLogs = New-Object System.Windows.Forms.Panel
$pnlChatLogs.Dock = "Fill"
$pnlChatLogs.BackColor = $script:colorMainBg
$pnlChatLogs.AutoScroll = $true
$pnlRight.Controls.Add($pnlChatLogs)
$pnlChatLogs.BringToFront()

# Bottom Input Control Panel
$pnlInput = New-Object System.Windows.Forms.Panel
$pnlInput.Dock = "Bottom"
$pnlInput.Height = 60
$pnlInput.BackColor = $script:colorHeaderBg

$txtInput = New-Object System.Windows.Forms.TextBox
$txtInput.Location = New-Object System.Drawing.Point(15, 14)
$txtInput.Size = New-Object System.Drawing.Size(710, 30)
$txtInput.BackColor = $script:colorMainBg
$txtInput.ForeColor = $script:colorTextMain
$txtInput.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtInput.Font = New-Object System.Drawing.Font("Segoe UI", 10.5)

$btnSend = New-Object System.Windows.Forms.Button
$btnSend.Location = New-Object System.Drawing.Point(740, 12)
$btnSend.Size = New-Object System.Drawing.Size(42, 36)
$btnSend.Text = ">"
$btnSend.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSend.FlatAppearance.BorderSize = 0
$btnSend.BackColor = $script:colorAccent
$btnSend.ForeColor = [System.Drawing.Color]::White
$btnSend.Font = New-Object System.Drawing.Font("Segoe UI", 12)

$pnlInput.Controls.AddRange(@($txtInput, $btnSend))
$pnlRight.Controls.Add($pnlInput)

# --- Right Column splash Screen panel (GREEN-API Branded style) ---
$pnlSplash = New-Object System.Windows.Forms.Panel
$pnlSplash.Dock = "Fill"
$pnlSplash.BackColor = $script:colorChatBg
$pnlSplash.Visible = $true

$pnlSplashContent = New-Object System.Windows.Forms.Panel
$pnlSplashContent.Size = New-Object System.Drawing.Size(600, 300)
$pnlSplashContent.Location = New-Object System.Drawing.Point(100, 150)
$pnlSplashContent.BackColor = [System.Drawing.Color]::Transparent

# Text description below logo
$lblSplashFootnote = New-Object System.Windows.Forms.Label
$lblSplashFootnote.Text = "GREEN-API SQL Local Media Repository"
$lblSplashFootnote.Font = New-Object System.Drawing.Font("Segoe UI", 16)
$lblSplashFootnote.ForeColor = $script:colorTextMain
$lblSplashFootnote.Size = New-Object System.Drawing.Size(600, 45)
$lblSplashFootnote.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblSplashFootnote.Location = New-Object System.Drawing.Point(0, 180)

$pnlSplashContent.Controls.Add($lblSplashFootnote)
$pnlSplash.Controls.Add($pnlSplashContent)
$pnlRight.Controls.Add($pnlSplash)
$pnlSplash.BringToFront()

# Align splash panel dynamically
$pnlSplash.Add_Resize({
    $pnlSplashContent.Location = New-Object System.Drawing.Point(
        [Math]::Max(0, ($pnlSplash.Width - $pnlSplashContent.Width) / 2),
        [Math]::Max(0, ($pnlSplash.Height - $pnlSplashContent.Height) / 2)
    )
})

# Custom Paint to draw GREEN-API Logo
$pnlSplashContent.Add_Paint({
    param($evtSender, $e)
    $graphics = $e.Graphics
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    
    # 1. Draw Green Chat Bubble Shape
    $bubbleRect = [System.Drawing.Rectangle]::new(50, 20, 90, 85)
    $bubbleBrush = New-Object System.Drawing.SolidBrush($script:colorAccent)
    
    $path = New-Object System.Drawing.Drawing2D.GraphicsPath
    $radius = 12
    $path.AddArc($bubbleRect.X, $bubbleRect.Y, $radius, $radius, 180, 90)
    $path.AddArc(($bubbleRect.Right - $radius), $bubbleRect.Y, $radius, $radius, 270, 90)
    $path.AddArc(($bubbleRect.Right - $radius), ($bubbleRect.Bottom - $radius), $radius, $radius, 0, 90)
    
    # Bottom Left Corner details
    $path.AddLine(($bubbleRect.X + $radius), $bubbleRect.Bottom, ($bubbleRect.X - 5), ($bubbleRect.Bottom + 12))
    $path.AddLine(($bubbleRect.X - 5), ($bubbleRect.Bottom + 12), ($bubbleRect.X + 2), ($bubbleRect.Bottom - 8))
    
    $path.AddArc($bubbleRect.X, ($bubbleRect.Bottom - $radius), $radius, $radius, 90, 90)
    $path.CloseAllFigures()
    
    $graphics.FillPath($bubbleBrush, $path)
    
    # 2. Draw Bold White letter "G" inside the bubble
    $gFont = New-Object System.Drawing.Font("Segoe UI", 48, [System.Drawing.FontStyle]::Bold)
    $gBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
    $graphics.DrawString("G", $gFont, $gBrush, ($bubbleRect.X + 11), ($bubbleRect.Y + 2))
    
    # 3. Draw "GREEN-API" text next to the bubble logo
    $logoFont = New-Object System.Drawing.Font("Segoe UI", 48, [System.Drawing.FontStyle]::Bold)
    $logoBrush = New-Object System.Drawing.SolidBrush($script:colorAccent)
    $graphics.DrawString("GREEN-API", $logoFont, $logoBrush, 155, 18)
    
    # Cleanup resources
    $bubbleBrush.Dispose()
    $path.Dispose()
    $gFont.Dispose()
    $gBrush.Dispose()
    $logoFont.Dispose()
    $logoBrush.Dispose()
})

# Bottom Status Strip
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.BackColor = $script:colorHeaderBg
$lblStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStatus.ForeColor = $script:colorTextMuted
$lblStatus.Text = "System active."
$statusStrip.Items.Add($lblStatus) | Out-Null
$form.Controls.Add($statusStrip)

# --- UI Update Action: Populate Contact List with ACTIVE Chats ---
function Update-ContactsListMenu {
    $lstContacts.Items.Clear()
    $script:contactsMapping.Clear()
    $script:contactsCache.Clear()
    
    # Get active chats directly from SQL Database
    $activeChats = Get-ActiveChatsFromSql
    
    foreach ($chat in $activeChats) {
        $lstContacts.Items.Add($chat.DisplayName) | Out-Null
        $script:contactsMapping[$chat.DisplayName] = $chat.ChatId
        $script:contactsCache[$chat.ChatId] = $chat
    }
}

# --- Owner-Drawn Contacts List Drawing Hook ---
$lstContacts.Add_DrawItem({
    param($evtSender, $e)
    if ($e.Index -lt 0 -or $e.Index -ge $evtSender.Items.Count) { return }
    $graphics = $e.Graphics
    $itemText = $evtSender.Items[$e.Index]
    
    $isSelected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected
    $backColor = if ($isSelected) { $script:colorSelectBg } else { $script:colorSidebarBg }
    $backBrush = New-Object System.Drawing.SolidBrush($backColor)
    $graphics.FillRectangle($backBrush, $e.Bounds)
    
    # Render ONLY the sender/display name
    $nameFont = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
    $nameBrush = New-Object System.Drawing.SolidBrush($script:colorTextMain)
    
    $textSize = $graphics.MeasureString($itemText, $nameFont)
    $textY = $e.Bounds.Y + ($e.Bounds.Height - $textSize.Height) / 2
    $graphics.DrawString($itemText, $nameFont, $nameBrush, 15, $textY)
    
    # Bottom separator divider border line
    $borderPen = New-Object System.Drawing.Pen([System.Drawing.ColorTranslator]::FromHtml("#222d34"), 1)
    $graphics.DrawLine($borderPen, 0, ($e.Bounds.Bottom - 1), $e.Bounds.Right, ($e.Bounds.Bottom - 1))
    
    # Cleanup resources
    $borderPen.Dispose()
    $nameFont.Dispose()
    $nameBrush.Dispose()
    $backBrush.Dispose()
})

# --- Draw Avatar on Active Header ---
$pnlHeader.Add_Paint({
    param($evtSender, $e)
    if ($script:activeSenderName) {
        $graphics = $e.Graphics
        $avatarRect = [System.Drawing.Rectangle]::new(15, 8, 44, 44)
        $avatarColor = Get-AvatarColor -Name $script:activeSenderName
        $avatarBrush = New-Object System.Drawing.SolidBrush($avatarColor)
        
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.FillEllipse($avatarBrush, $avatarRect)
        
        $initials = Get-Initials -Name $script:activeSenderName
        $avatarFont = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
        $initialSize = $graphics.MeasureString($initials, $avatarFont)
        $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $graphics.DrawString(
            $initials,
            $avatarFont,
            $textBrush,
            $avatarRect.X + ($avatarRect.Width - $initialSize.Width) / 2,
            $avatarRect.Y + ($avatarRect.Height - $initialSize.Height) / 2
        )
        $avatarBrush.Dispose()
        $avatarFont.Dispose()
        $textBrush.Dispose()
    }
})

# --- Contact Selection Event: Renders SQL database messages including images and videos ---
$lstContacts.Add_SelectedIndexChanged({
    $selectedName = $lstContacts.SelectedItem
    if ($selectedName) {
        $chatId = $script:contactsMapping[$selectedName]
        $script:activeChatId = $chatId
        $script:activeSenderName = $selectedName
        
        $lblActiveContact.Text = $selectedName
        $lblActiveStatus.Text = $chatId
        
        $pnlSplash.Visible = $false
        
        Update-ChatHistoryView
        $pnlHeader.Invalidate()
    }
})

# --- Active Thread Conversation View Generator (Standard GDI Message Bubbles) ---
function Update-ChatHistoryView {
    if (-not $script:activeChatId) {
        $pnlChatLogs.Controls.Clear()
        return
    }
    
    $pnlChatLogs.SuspendLayout()
    $pnlChatLogs.Controls.Clear()
    
    # Query history with binary BLOBs directly from SQL Database
    $history = Get-ChatHistoryFromSql -chatId $script:activeChatId
    
    $currentY = 15
    $bubbleWidth = [int]($pnlChatLogs.Width * 0.70)
    
    foreach ($msg in $history) {
        $displayName = if ($msg.type -eq 'outgoing') { "Me" } else { $msg.senderName }
        $timeStr = [DateTimeOffset]::FromUnixTimeSeconds($msg.timestamp).LocalDateTime.ToString("yyyy-MM-dd HH:mm")
        
        # Message bubble container
        $pnlBubble = New-Object System.Windows.Forms.Panel
        $pnlBubble.Width = $bubbleWidth
        $pnlBubble.BackColor = if ($msg.type -eq 'outgoing') { $script:colorBubbleOut } else { $script:colorBubbleIn }
        
        # Header Label (Sender Name & Timestamp)
        $lblHeader = New-Object System.Windows.Forms.Label
        $lblHeader.Text = "$displayName  ($timeStr)"
        $lblHeader.Font = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
        $lblHeader.ForeColor = if ($msg.type -eq 'outgoing') { [System.Drawing.ColorTranslator]::FromHtml("#95C6A6") } else { [System.Drawing.ColorTranslator]::FromHtml("#A6B6C6") }
        $lblHeader.Location = New-Object System.Drawing.Point(10, 8)
        $lblHeader.Size = New-Object System.Drawing.Size(($bubbleWidth - 20), 16)
        $pnlBubble.Controls.Add($lblHeader)
        
        $contentY = 28
        
        # Draw Content based on Message Type
        if ($msg.typeMessage -eq 'textMessage' -or $msg.typeMessage -eq 'extendedTextMessage') {
            $lblText = New-Object System.Windows.Forms.Label
            $lblText.Text = $msg.textMessage
            $lblText.Font = $script:fontSegoeRegular
            $lblText.ForeColor = $script:colorTextMain
            $lblText.Location = New-Object System.Drawing.Point(10, $contentY)
            $lblText.Width = $bubbleWidth - 20
            
            # Auto-size text box height based on font layout sizing
            $textSize = [System.Windows.Forms.TextRenderer]::MeasureText(
                $lblText.Text, 
                $lblText.Font, 
                [System.Drawing.Size]::new($lblText.Width, 9999), 
                [System.Windows.Forms.TextFormatFlags]::WordBreak
            )
            $lblText.Height = $textSize.Height + 5
            $pnlBubble.Controls.Add($lblText)
            
            $pnlBubble.Height = $contentY + $lblText.Height + 10
        }
        elseif ($msg.typeMessage -eq 'imageMessage' -and $msg.fileBytes) {
            # Load and render Image directly from database binary BLOB
            $pictureBox = New-Object System.Windows.Forms.PictureBox
            $pictureBox.Location = New-Object System.Drawing.Point(10, $contentY)
            $pictureBox.Size = New-Object System.Drawing.Size(($bubbleWidth - 20), 220)
            $pictureBox.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
            
            try {
                $ms = New-Object System.IO.MemoryStream(,$msg.fileBytes)
                $pictureBox.Image = [System.Drawing.Image]::FromStream($ms)
            }
            catch {
                # Fallback in case of corruption
                $pictureBox.BackColor = [System.Drawing.Color]::DarkGray
            }
            
            $pnlBubble.Controls.Add($pictureBox)
            
            # Image Caption if populated
            if ($msg.caption) {
                $lblCap = New-Object System.Windows.Forms.Label
                $lblCap.Text = $msg.caption
                $lblCap.Font = $script:fontSegoeRegular
                $lblCap.ForeColor = $script:colorTextMain
                $lblCap.Location = New-Object System.Drawing.Point(10, ($contentY + 225))
                $lblCap.Width = $bubbleWidth - 20
                $lblCap.Height = 20
                $pnlBubble.Controls.Add($lblCap)
                $pnlBubble.Height = $contentY + 255
            }
            else {
                $pnlBubble.Height = $contentY + 235
            }
        }
        elseif ($msg.typeMessage -eq 'videoMessage' -and $msg.fileBytes) {
            # Render video layout block with action listener to extract and play video
            $btnPlay = New-Object System.Windows.Forms.Button
            $btnPlay.Text = "Play Video Attachment (Local SQL Blob)"
            $btnPlay.Location = New-Object System.Drawing.Point(10, $contentY)
            $btnPlay.Size = New-Object System.Drawing.Size(($bubbleWidth - 20), 40)
            $btnPlay.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
            $btnPlay.FlatAppearance.BorderSize = 1
            $btnPlay.FlatAppearance.BorderColor = $script:colorAccent
            $btnPlay.BackColor = $script:colorSelectBg
            $btnPlay.ForeColor = $script:colorTextMain
            $btnPlay.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
            $btnPlay.Cursor = [System.Windows.Forms.Cursors]::Hand
            
            # Click action extracts video bytes to temp file and launches the default player
            $btnPlay.Add_Click({
                $tempVideoPath = Join-Path $env:TEMP "whatsapp_video_$($msg.idMessage).mp4"
                if (-not (Test-Path $tempVideoPath)) {
                    [System.IO.File]::WriteAllBytes($tempVideoPath, $msg.fileBytes)
                }
                try {
                    [System.Diagnostics.Process]::Start($tempVideoPath)
                } catch {
                    [System.Windows.Forms.MessageBox]::Show("Could not launch default video player.", "Error")
                }
            })
            
            $pnlBubble.Controls.Add($btnPlay)
            
            # Video Caption if populated
            if ($msg.caption) {
                $lblCap = New-Object System.Windows.Forms.Label
                $lblCap.Text = $msg.caption
                $lblCap.Font = $script:fontSegoeRegular
                $lblCap.ForeColor = $script:colorTextMain
                $lblCap.Location = New-Object System.Drawing.Point(10, ($contentY + 45))
                $lblCap.Width = $bubbleWidth - 20
                $lblCap.Height = 20
                $pnlBubble.Controls.Add($lblCap)
                $pnlBubble.Height = $contentY + 75
            }
            else {
                $pnlBubble.Height = $contentY + 55
            }
        }
        else {
            # Standard Document or other files
            $lblDoc = New-Object System.Windows.Forms.Label
            $lblDoc.Text = if ($msg.fileName) { "Document: $($msg.fileName)" } else { "[$($msg.typeMessage)]" }
            $lblDoc.Font = $script:fontSegoeRegular
            $lblDoc.ForeColor = $script:colorTextMuted
            $lblDoc.Location = New-Object System.Drawing.Point(10, $contentY)
            $lblDoc.Size = New-Object System.Drawing.Size(($bubbleWidth - 20), 20)
            $pnlBubble.Controls.Add($lblDoc)
            
            $pnlBubble.Height = $contentY + 30
        }
        
        # Position bubble alignment (Right for outgoing, Left for incoming)
        if ($msg.type -eq 'outgoing') {
            $pnlBubble.Location = New-Object System.Drawing.Point(($pnlChatLogs.Width - $bubbleWidth - 25), $currentY)
        }
        else {
            $pnlBubble.Location = New-Object System.Drawing.Point(15, $currentY)
        }
        
        $pnlChatLogs.Controls.Add($pnlBubble)
        $currentY += $pnlBubble.Height + 12
    }
    
    # Auto scroll to bottom
    if ($pnlChatLogs.Controls.Count -gt 0) {
        $pnlChatLogs.ScrollControlIntoView($pnlChatLogs.Controls[$pnlChatLogs.Controls.Count - 1])
    }
    
    $pnlChatLogs.ResumeLayout()
}

# --- Add Chat Button click event (New chat dialog) ---
$btnNewChat.Add_Click({
    $prompt = New-Object System.Windows.Forms.Form
    $prompt.Size = New-Object System.Drawing.Size(350, 160)
    $prompt.Text = "New Conversation"
    $prompt.StartPosition = "CenterParent"
    $prompt.BackColor = $script:colorHeaderBg
    $prompt.ForeColor = [System.Drawing.Color]::White
    $prompt.FormBorderStyle = "FixedDialog"
    $prompt.MaximizeBox = $false
    $prompt.MinimizeBox = $false

    $lbl = New-Object System.Windows.Forms.Label
    $lbl.Text = "Enter Phone Number (e.g. 27609448896):"
    $lbl.Location = New-Object System.Drawing.Point(20, 20)
    $lbl.Size = New-Object System.Drawing.Size(300, 20)

    $txt = New-Object System.Windows.Forms.TextBox
    $txt.Location = New-Object System.Drawing.Point(20, 45)
    $txt.Size = New-Object System.Drawing.Size(290, 25)
    $txt.BackColor = $script:colorMainBg
    $txt.ForeColor = $script:colorTextMain
    $txt.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle

    $btnOk = New-Object System.Windows.Forms.Button
    $btnOk.Text = "Create"
    $btnOk.Location = New-Object System.Drawing.Point(230, 85)
    $btnOk.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnOk.BackColor = $script:colorAccent
    $btnOk.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
    $btnOk.FlatAppearance.BorderSize = 0

    $prompt.Controls.AddRange(@($lbl, $txt, $btnOk))
    $prompt.AcceptButton = $btnOk

    if ($prompt.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $num = $txt.Text.Trim()
        if ($num) {
            $cleanNum = $num -replace '[^\d]'
            if ($cleanNum) {
                $chatId = "$cleanNum@c.us"
                # Mock a welcome chat record in SQLite to initialize the contact card list
                $welcomeMsg = [PSCustomObject]@{
                    idMessage   = "welcome_$([Guid]::NewGuid().ToString())"
                    chatId      = $chatId
                    timestamp   = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                    type        = "incoming"
                    senderId    = $chatId
                    senderName  = $num
                    typeMessage = "textMessage"
                    textMessage = "System: Conversation started."
                    caption     = $null
                    fileName    = $null
                    fileBytes   = $null
                }
                Save-ChatMessageToSql -msg $welcomeMsg
                Update-ContactsListMenu
                $lstContacts.SelectedItem = $num
            }
        }
    }
    $prompt.Dispose()
})

# --- Hook Notification Polling Timer Tick ---
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000

$timer.Add_Tick({
    try {
        $timer.Stop()
        $notification = Receive-WhatsappNotification
        if ($notification -and $notification.body) {
            $receiptId = $notification.receiptId
            $messageData = $notification.body
            
            $null = Remove-WhatsappNotification -ReceiptId $receiptId
            
            if ($messageData.messageData -and $messageData.senderData) {
                $incomingChatId = $messageData.chatId
                
                if ($incomingChatId) {
                    $incomingSenderName = $messageData.senderData.senderName
                    if ([string]::IsNullOrEmpty($incomingSenderName)) {
                        $incomingSenderName = $messageData.senderData.sender.Split('@')[0]
                    }
                    
                    $msgText = ""
                    $mediaTypes = @('imageMessage', 'videoMessage', 'audioMessage', 'documentMessage')
                    
                    $dbPayload = [PSCustomObject]@{
                        idMessage     = $messageData.idMessage
                        timestamp     = $messageData.timestamp
                        type          = "incoming"
                        chatId        = $incomingChatId
                        senderId      = $messageData.senderData.sender
                        senderName    = $incomingSenderName
                        typeMessage   = $messageData.messageData.typeMessage
                        textMessage   = $null
                        caption       = $null
                        fileName      = $null
                        fileBytes     = $null
                    }
                    
                    if ($mediaTypes -contains $messageData.messageData.typeMessage) {
                        $msgText = "[$($messageData.messageData.typeMessage)]"
                        if ($messageData.messageData.typeMessage -eq 'imageMessage') {
                            $dbPayload.caption = $messageData.messageData.imageMessageData.caption
                            if ($dbPayload.caption) { $msgText += " " + $dbPayload.caption }
                        }
                        elseif ($messageData.messageData.typeMessage -eq 'videoMessage') {
                            $dbPayload.caption = $messageData.messageData.videoMessageData.caption
                            if ($dbPayload.caption) { $msgText += " " + $dbPayload.caption }
                        }
                        elseif ($messageData.messageData.typeMessage -eq 'documentMessage') {
                            $dbPayload.caption = $messageData.messageData.documentMessageData.caption
                            $dbPayload.fileName = $messageData.messageData.documentMessageData.fileName
                            if ($dbPayload.caption) { $msgText += " " + $dbPayload.caption }
                        }
                    }
                    elseif ($messageData.messageData.typeMessage -eq 'textMessage') {
                        $msgText = $messageData.messageData.textMessageData.textMessage
                        $dbPayload.textMessage = $msgText
                    }
                    elseif ($messageData.messageData.typeMessage -eq 'extendedTextMessage') {
                        $msgText = $messageData.messageData.extendedTextMessageData.text
                        $dbPayload.textMessage = $msgText
                    }
                    else {
                        $msgText = "[$($messageData.messageData.typeMessage)]"
                    }
                    
                    # Save incoming record to local SQL database with attachment bytes
                    Save-ChatMessageToSql -msg $dbPayload
                    
                    Update-ContactsListMenu
                    
                    if ($incomingChatId -eq $script:activeChatId) {
                        Update-ChatHistoryView
                        $null = Set-ChatRead -ChatId $script:activeChatId
                    }
                    
                    [System.Media.SystemSounds]::Asterisk.Play()
                    $lblStatus.Text = "New message from ${incomingSenderName}: $msgText"
                }
            }
        }
    }
    catch {}
    finally {
        if ($form -and $form.Visible) {
            $timer.Start()
        }
    }
})

# --- Send Outbound Action ---
$SendMessageAction = {
    $text = $txtInput.Text.Trim()
    if ($text -and $script:activeChatId) {
        $txtInput.Text = ""
        $lblStatus.Text = "Sending message..."
        $txtInput.Enabled = $false
        $btnSend.Enabled = $false
        
        try {
            $response = Send-Whatsapp -ChatId $script:activeChatId -Message $text
            
            if ($response -and $response.idMessage) {
                $lblStatus.Text = "Message sent successfully!"
                
                $outgoingPayload = [PSCustomObject]@{
                    idMessage     = $response.idMessage
                    timestamp     = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                    type          = "outgoing"
                    chatId        = $script:activeChatId
                    senderId      = $null
                    senderName    = "Me"
                    typeMessage   = "textMessage"
                    textMessage   = $text
                    caption       = $null
                    fileName      = $null
                    fileBytes     = $null
                }
                # Save outgoing record directly to SQL Database
                Save-ChatMessageToSql -msg $outgoingPayload
                
                Update-ContactsListMenu
                Update-ChatHistoryView
            }
            else {
                $lblStatus.Text = "Failed to send message."
            }
        }
        catch {
            $lblStatus.Text = "Send Error: $_"
        }
        finally {
            $txtInput.Enabled = $true
            $btnSend.Enabled = $true
            $txtInput.Focus()
        }
    }
}

$btnSend.Add_Click($SendMessageAction)
$txtInput.Add_KeyDown({
    if ($_.KeyCode -eq "Enter") {
        $SendMessageAction.Invoke()
        $_.SuppressKeyPress = $true
    }
})

# --- Event Binding ---
$form.Add_Load({
    $lblStatus.Text = "Initializing SQL database..."
    [System.Windows.Forms.Application]::DoEvents()
    
    Initialize-Database
    Sync-JsonHistoryToSql
    
    $lblStatus.Text = "Loading contacts..."
    [System.Windows.Forms.Application]::DoEvents()
    
    Update-ContactsListMenu
    $timer.Start()
    $lblStatus.Text = "Online (SQL Mode)"
})

$form.Add_FormClosing({
    $timer.Stop()
    if ($script:conn) {
        $script:conn.Close()
        $script:conn.Dispose()
    }
})

$form.ShowDialog() | Out-Null
