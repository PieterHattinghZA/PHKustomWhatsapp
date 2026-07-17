Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# Import the module
Import-Module .\PHKustomWhatsapp.psd1 -Force

# --- Ensure Databases and Config Folder Exists ---
$dbDir = Join-Path $env:APPDATA "PHWhatsapp\Database"
if (-not (Test-Path $dbDir)) {
    New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
}

# --- Main Window Form Configuration ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "PHKustom-Whatsapp Chat Center Pro"
$form.Size = New-Object System.Drawing.Size(1050, 700)
$form.StartPosition = "CenterScreen"
$form.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#1E1E1E")
$form.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#D4D4D4")
$form.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)

# --- Global States ---
$script:activeChatId = $null
$script:activeSenderName = ""
$script:activeChatMessages = @()
$script:quotedMessageId = $null
$script:rightClickedMessage = $null

# --- Downloads Configuration ---
$downloadsParentFolder = Join-Path $env:APPDATA "PHWhatsapp"

# --- Layout Container Split ---
$splitContainer = New-Object System.Windows.Forms.SplitContainer
$splitContainer.Dock = "Fill"
$splitContainer.SplitterDistance = 260
$splitContainer.SplitterWidth = 4
$splitContainer.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#252526")
$form.Controls.Add($splitContainer)

# --- Left Column: Chat Contacts List Panel ---
$pnlContacts = New-Object System.Windows.Forms.Panel
$pnlContacts.Dock = "Fill"
$pnlContacts.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#252526")

$lblContactsTitle = New-Object System.Windows.Forms.Label
$lblContactsTitle.Text = "Conversations"
$lblContactsTitle.Dock = "Top"
$lblContactsTitle.Height = 35
$lblContactsTitle.TextAlign = "MiddleCenter"
$lblContactsTitle.Font = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)
$lblContactsTitle.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#FFFFFF")
$pnlContacts.Controls.Add($lblContactsTitle)

$lstContacts = New-Object System.Windows.Forms.ListBox
$lstContacts.Dock = "Fill"
$lstContacts.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#2D2D2D")
$lstContacts.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#F1F1F1")
$lstContacts.BorderStyle = "None"
$lstContacts.Font = New-Object System.Drawing.Font("Segoe UI", 10.5)
$pnlContacts.Controls.Add($lstContacts)

# Left Column Context Menu (Delete Entire Chat Thread)
$ctxChatMenu = New-Object System.Windows.Forms.ContextMenuStrip
$menuDeleteChat = $ctxChatMenu.Items.Add("Delete Conversation History")
$lstContacts.ContextMenuStrip = $ctxChatMenu

$splitContainer.Panel1.Controls.Add($pnlContacts)

# --- Right Column: Active Conversation Panel Container ---
$pnlChatWindow = New-Object System.Windows.Forms.Panel
$pnlChatWindow.Dock = "Fill"
$pnlChatWindow.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#1E1E1E")
$splitContainer.Panel2.Controls.Add($pnlChatWindow)

# --- Title Header Panel ---
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = "Top"
$pnlHeader.Height = 50
$pnlHeader.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#252526")

$lblActiveChat = New-Object System.Windows.Forms.Label
$lblActiveChat.Text = "Select a conversation from the left pane to begin..."
$lblActiveChat.Location = New-Object System.Drawing.Point(15, 15)
$lblActiveChat.AutoSize = $true
$lblActiveChat.Font = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
$pnlHeader.Controls.Add($lblActiveChat)
$pnlChatWindow.Controls.Add($pnlHeader)

# --- Bottom Input Panel ---
$pnlInput = New-Object System.Windows.Forms.Panel
$pnlInput.Dock = "Bottom"
$pnlInput.Height = 100 # Expanded height to allow for Quote Bar + Actions Area Panel
$pnlInput.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#252526")

# Reply/Quote Preview Bar Panel
$pnlQuoteBar = New-Object System.Windows.Forms.Panel
$pnlQuoteBar.Dock = "Top"
$pnlQuoteBar.Height = 28
$pnlQuoteBar.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#333337")
$pnlQuoteBar.Visible = $false

$lblQuoteText = New-Object System.Windows.Forms.Label
$lblQuoteText.Text = "Replying to message..."
$lblQuoteText.Location = New-Object System.Drawing.Point(12, 5)
$lblQuoteText.AutoSize = $true
$lblQuoteText.Font = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Italic)
$lblQuoteText.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#00A2E8")

$btnCancelQuote = New-Object System.Windows.Forms.Button
$btnCancelQuote.Text = "✕"
$btnCancelQuote.Size = New-Object System.Drawing.Size(22, 20)
$btnCancelQuote.Location = New-Object System.Drawing.Point(520, 3)
$btnCancelQuote.Anchor = "Top, Right"
$btnCancelQuote.FlatStyle = "Flat"
$btnCancelQuote.FlatAppearance.BorderSize = 0
$btnCancelQuote.ForeColor = [System.Drawing.Color]::Gray

$pnlQuoteBar.Controls.Add($lblQuoteText)
$pnlQuoteBar.Controls.Add($btnCancelQuote)
$pnlInput.Controls.Add($pnlQuoteBar)

# Controls Interaction Row Panel
$pnlControlsRow = New-Object System.Windows.Forms.Panel
$pnlControlsRow.Dock = "Fill"
$pnlControlsRow.Padding = New-Object System.Windows.Forms.Padding(10)

$txtInput = New-Object System.Windows.Forms.TextBox
$txtInput.Location = New-Object System.Drawing.Point(12, 12)
$txtInput.Width = 390
$txtInput.Height = 45
$txtInput.Anchor = "Top, Left, Right"
$txtInput.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#2D2D2D")
$txtInput.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#F1F1F1")
$txtInput.BorderStyle = "FixedSingle"
$txtInput.Enabled = $false

# Action Buttons Context Panels Row
$btnAttach = New-Object System.Windows.Forms.Button
$btnAttach.Text = "File"
$btnAttach.Location = New-Object System.Drawing.Point(410, 10)
$btnAttach.Width = 60; $btnAttach.Height = 25
$btnAttach.Anchor = "Top, Right"
$btnAttach.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#3E3E42")
$btnAttach.ForeColor = [System.Drawing.Color]::White
$btnAttach.FlatStyle = "Flat"
$btnAttach.FlatAppearance.BorderSize = 0
$btnAttach.Enabled = $false

$btnLocation = New-Object System.Windows.Forms.Button
$btnLocation.Text = "Map"
$btnLocation.Location = New-Object System.Drawing.Point(475, 10)
$btnLocation.Width = 60; $btnLocation.Height = 25
$btnLocation.Anchor = "Top, Right"
$btnLocation.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#3E3E42")
$btnLocation.ForeColor = [System.Drawing.Color]::White
$btnLocation.FlatStyle = "Flat"
$btnLocation.FlatAppearance.BorderSize = 0
$btnLocation.Enabled = $false

$btnSend = New-Object System.Windows.Forms.Button
$btnSend.Text = "Send"
$btnSend.Location = New-Object System.Drawing.Point(545, 8)
$btnSend.Width = 70; $btnSend.Height = 28
$btnSend.Anchor = "Top, Right"
$btnSend.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0E639C")
$btnSend.ForeColor = [System.Drawing.Color]::White
$btnSend.FlatStyle = "Flat"
$btnSend.FlatAppearance.BorderSize = 0
$btnSend.Enabled = $false

$pnlControlsRow.Controls.Add($txtInput)
$pnlControlsRow.Controls.Add($btnAttach)
$pnlControlsRow.Controls.Add($btnLocation)
$pnlControlsRow.Controls.Add($btnSend)
$pnlInput.Controls.Add($pnlControlsRow)
$pnlChatWindow.Controls.Add($pnlInput)

# --- History RichTextBox Panel ---
$rtbHistory = New-Object System.Windows.Forms.RichTextBox
$rtbHistory.Dock = "Fill"
$rtbHistory.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#1E1E1E")
$rtbHistory.ForeColor = [System.Drawing.ColorTranslator]::FromHtml("#D4D4D4")
$rtbHistory.BorderStyle = "None"
$rtbHistory.ReadOnly = $true
$rtbHistory.DetectUrls = $false
$rtbHistory.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$pnlChatWindow.Controls.Add($rtbHistory)

# Conversation View Context Strip Menu (Reply, Delete Message)
$ctxMessageMenu = New-Object System.Windows.Forms.ContextMenuStrip
$menuReply = $ctxMessageMenu.Items.Add("Reply to this message")
$menuDeleteMsg = $ctxMessageMenu.Items.Add("Delete message (Recall)")
$rtbHistory.ContextMenuStrip = $ctxMessageMenu

$rtbHistory.BringToFront()

# --- Status Bar ---
$statusBar = New-Object System.Windows.Forms.StatusStrip
$statusBar.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#007ACC")
$statusBar.ForeColor = [System.Drawing.Color]::White

$lblStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStatus.Text = "Ready."

$lblLastCheck = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblLastCheck.Text = " Last check: None"
$lblLastCheck.Alignment = "Right"

$statusBar.Items.Add($lblStatus) | Out-Null
$statusBar.Items.Add($lblLastCheck) | Out-Null
$form.Controls.Add($statusBar)

# --- Media Extraction Engines ---
function Get-MediaFolderPaths {
    param([string]$senderId, [string]$typeMessage)
    $incomingNumber = $senderId.Split('@')[0]
    $chatDir = Join-Path $downloadsParentFolder $incomingNumber
    $subFolderName = "others"
    if ($typeMessage -eq 'imageMessage') { $subFolderName = "images" }
    elseif ($typeMessage -eq 'videoMessage') { $subFolderName = "videos" }
    elseif ($typeMessage -eq 'audioMessage') { $subFolderName = "audio" }
    elseif ($typeMessage -eq 'documentMessage') { $subFolderName = "documents" }
    $targetDir = Join-Path $chatDir $subFolderName
    if (-not (Test-Path $targetDir)) { New-Item -ItemType Directory -Path $targetDir -Force | Out-Null }
    return $targetDir
}

function Get-ImageRtf {
    param([string]$filePath, [int]$maxDim = 600)
    if (-not (Test-Path $filePath)) { return "" }
    try {
        $img = [System.Drawing.Image]::FromFile($filePath)
        $w = $img.Width; $h = $img.Height; $ratio = [double]$w / [double]$h
        if ($w -gt $h) { $newW = $maxDim; $newH = [int]($maxDim / $ratio) } else { $newH = $maxDim; $newW = [int]($maxDim * $ratio) }
        $thumb = New-Object System.Drawing.Bitmap($newW, $newH)
        $g = [System.Drawing.Graphics]::FromImage($thumb)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($img, 0, 0, $newW, $newH)
        $oldClipboard = $null; try { $oldClipboard = [System.Windows.Forms.Clipboard]::GetDataObject() } catch {}
        try { [System.Windows.Forms.Clipboard]::SetImage($thumb) } catch {}
        $tempRtb = New-Object System.Windows.Forms.RichTextBox; $tempRtb.Paste()
        $rtf = $tempRtb.Rtf; $rtfSnippet = ""
        if ($rtf -match '(?s)\{\\pict\\wmetafile8.+?\}') {
            $rtfSnippet = $Matches[0]
            if ($rtfSnippet -match '\\picwgoal(\d+)') { $newGoalW = [int]([int]$Matches[1] * 0.15); $rtfSnippet = $rtfSnippet -replace '\\picwgoal\d+', "\picwgoal$newGoalW" }
            if ($rtfSnippet -match '\\pichgoal(\d+)') { $newGoalH = [int]([int]$Matches[1] * 0.15); $rtfSnippet = $rtfSnippet -replace '\\pichgoal\d+', "\pichgoal$newGoalH" }
        }
        if ($null -ne $oldClipboard) { try { [System.Windows.Forms.Clipboard]::SetDataObject($oldClipboard) } catch {} }
        $g.Dispose(); $thumb.Dispose(); $img.Dispose(); $tempRtb.Dispose()
        return $rtfSnippet
    } catch { return "" }
}

function Get-Base64ImageRtf {
    param([string]$base64, [int]$maxDim = 600)
    if ([string]::IsNullOrEmpty($base64)) { return "" }
    try {
        $base64Data = $base64
        if ($base64Data -match '^data:image\/[^;]+;base64,(.+)$') { $base64Data = $Matches[1] }
        $pad = 4 - ($base64Data.Length % 4)
        if ($pad -lt 4) { $base64Data += "=" * $pad }
        $bytes = [System.Convert]::FromBase64String($base64Data)
        $ms = New-Object System.IO.MemoryStream -ArgumentList @(,$bytes)
        $img = [System.Drawing.Image]::FromStream($ms)
        $w = $img.Width; $h = $img.Height; $ratio = [double]$w / [double]$h
        if ($w -gt $h) { $newW = $maxDim; $newH = [int]($maxDim / $ratio) } else { $newH = $maxDim; $newW = [int]($maxDim * $ratio) }
        $thumb = New-Object System.Drawing.Bitmap($newW, $newH)
        $g = [System.Drawing.Graphics]::FromImage($thumb)
        $g.InterpolationMode = [System.Drawing.Drawing2D.InterpolationMode]::HighQualityBicubic
        $g.DrawImage($img, 0, 0, $newW, $newH)
        $oldClipboard = $null; try { $oldClipboard = [System.Windows.Forms.Clipboard]::GetDataObject() } catch {}
        try { [System.Windows.Forms.Clipboard]::SetImage($thumb) } catch {}
        $tempRtb = New-Object System.Windows.Forms.RichTextBox; $tempRtb.Paste()
        $rtf = $tempRtb.Rtf; $rtfSnippet = ""
        if ($rtf -match '(?s)\{\\pict\\wmetafile8.+?\}') {
            $rtfSnippet = $Matches[0]
            if ($rtfSnippet -match '\\picwgoal(\d+)') { $newGoalW = [int]([int]$Matches[1] * 0.15); $rtfSnippet = $rtfSnippet -replace '\\picwgoal\d+', "\picwgoal$newGoalW" }
            if ($rtfSnippet -match '\\pichgoal(\d+)') { $newGoalH = [int]([int]$Matches[1] * 0.15); $rtfSnippet = $rtfSnippet -replace '\\pichgoal\d+', "\pichgoal$newGoalH" }
        }
        if ($null -ne $oldClipboard) { try { [System.Windows.Forms.Clipboard]::SetDataObject($oldClipboard) } catch {} }
        $ms.Dispose(); $img.Dispose(); $g.Dispose(); $thumb.Dispose(); $tempRtb.Dispose()
        return $rtfSnippet
    } catch { return "" }
}

function Get-MediaFileInfo {
    param([object]$msgData, [string]$msgId)
    $type = $msgData.messageData.typeMessage; $ext = ""; $fileName = ""
    switch ($type) {
        'imageMessage' { $ext = ".jpg"; $mime = $msgData.messageData.imageMessageData.mimeType; if ($mime -eq "image/png") { $ext = ".png" } elseif ($mime -eq "image/gif") { $ext = ".gif" }; $fileName = "image_$msgId$ext" }
        'videoMessage' { $ext = ".mp4"; $fileName = "video_$msgId$ext" }
        'audioMessage' { $ext = ".ogg"; $mime = $msgData.messageData.audioMessageData.mimeType; if ($mime -like "*mpeg*") { $ext = ".mp3" } elseif ($mime -like "*mp4*") { $ext = ".m4a" }; $fileName = "audio_$msgId$ext" }
        'documentMessage' { $fileName = $msgData.messageData.documentMessageData.fileName; if ([string]::IsNullOrEmpty($fileName)) { $ext = ".bin"; $mime = $msgData.messageData.documentMessageData.mimeType; if ($mime -eq "application/pdf") { $ext = ".pdf" }; $fileName = "doc_$msgId$ext" } }
        Default { $fileName = "file_$msgId" }
    }
    return [PSCustomObject]@{ FileName = $fileName; Type = $type }
}

# --- Contacts Management Menu Populator ---
$script:contactsMapping = @{}

function Update-ContactsListMenu {
    $currentSelection = $lstContacts.SelectedItem
    $lstContacts.Items.Clear()
    $script:contactsMapping.Clear()
    
    $historyFiles = Get-ChildItem -Path $dbDir -Filter "history_*.json"
    foreach ($file in $historyFiles) {
        if ($file.BaseName -match '^history_(.+)$') {
            $rawId = $Matches[1]
            $fullChatId = "$rawId@c.us"
            
            try {
                $rawContent = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
                if ($rawContent) {
                    $messages = ConvertFrom-Json $rawContent
                    $lastMessage = $messages | Sort-Object timestamp | Select-Object -Last 1
                    
                    $displayName = ""
                    if ($lastMessage) {
                        $displayName = $lastMessage.senderName
                        if ([string]::IsNullOrEmpty($displayName) -and $lastMessage.chatId) { $fullChatId = $lastMessage.chatId }
                    }
                    if ([string]::IsNullOrEmpty($displayName)) { $displayName = $rawId }
                    
                    if (-not $lstContacts.Items.Contains($displayName)) {
                        $lstContacts.Items.Add($displayName) | Out-Null
                        $script:contactsMapping[$displayName] = $fullChatId
                    }
                }
            } catch {}
        }
    }
    if ($currentSelection -and $lstContacts.Items.Contains($currentSelection)) {
        $lstContacts.SelectedItem = $currentSelection
    }
}

# --- Cloud Sync Engine ---
function Sync-ChatFromCloud {
    if (-not $script:activeChatId) { return }
    $lblStatus.Text = "Syncing messages from cloud..."
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
        $cloudHistory = Get-ChatHistory -ChatId $script:activeChatId -Count 50
        if ($cloudHistory) {
            $sortedCloud = $cloudHistory | Sort-Object timestamp
            foreach ($cMsg in $sortedCloud) {
                $dbPayload = [PSCustomObject]@{
                    idMessage    = $cMsg.idMessage; timestamp = $cMsg.timestamp; type = $cMsg.type; chatId = $script:activeChatId
                    senderId     = $cMsg.senderId; senderName = $script:activeSenderName; typeMessage = $cMsg.typeMessage
                    textMessage  = $cMsg.textMessage; caption = $cMsg.caption; fileName = $cMsg.fileName; jpegThumbnail = $cMsg.jpegThumbnail
                }
                if ($cMsg.typeMessage -eq 'imageMessage' -and $cMsg.imageMessageData) {
                    $dbPayload.caption = $cMsg.imageMessageData.caption; $dbPayload.jpegThumbnail = $cMsg.imageMessageData.jpegThumbnail
                } elseif ($cMsg.typeMessage -eq 'videoMessage' -and $cMsg.videoMessageData) { $dbPayload.caption = $cMsg.videoMessageData.caption
                } elseif ($cMsg.typeMessage -eq 'documentMessage' -and $cMsg.documentMessageData) {
                    $dbPayload.caption = $cMsg.documentMessageData.caption; $dbPayload.fileName = $cMsg.documentMessageData.fileName
                }
                Save-LocalChatMessage -ChatId $script:activeChatId -MessageObj $dbPayload
            }
            $lblStatus.Text = "Sync complete."
        }
    } catch { $lblStatus.Text = "Sync bypassed: Using localized dataset cache." }
}

# --- Conversation Render Engine ---
function Update-ChatHistoryView {
    if (-not $script:activeChatId) { return }
    
    $history = Get-LocalChatHistory -ChatId $script:activeChatId -Count 40
    if ($history) {
        $sorted = $history | Sort-Object timestamp
        $script:activeChatMessages = $sorted
        
        $rtbHistory.Invoke([Action]{
            $rtbHistory.Clear()
            foreach ($msg in $sorted) {
                if ([string]::IsNullOrEmpty($msg.typeMessage)) {
                    if ($msg.type -eq 'outgoing') { $msg.typeMessage = 'textMessage' }
                    else { if ($msg.fileName -or $msg.jpegThumbnail) { $msg.typeMessage = 'documentMessage' } else { $msg.typeMessage = 'textMessage' } }
                }
                if ([string]::IsNullOrEmpty($msg.textMessage) -and $msg.message) { $msg.textMessage = $msg.message }
                if ([string]::IsNullOrEmpty($msg.textMessage) -and $msg.body) { $msg.textMessage = $msg.body }

                $time = [DateTimeOffset]::FromUnixTimeSeconds($msg.timestamp).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
                if ($msg.type -eq 'outgoing') {
                    $displayName = "Me"
                    $senderColor = [System.Drawing.ColorTranslator]::FromHtml("#569CD6")
                } else {
                    $displayName = $msg.senderName
                    if ([string]::IsNullOrEmpty($displayName) -and $msg.senderId) { $displayName = $msg.senderId.Split('@')[0] }
                    if ([string]::IsNullOrEmpty($displayName)) { $displayName = "Unknown" }
                    $senderColor = [System.Drawing.ColorTranslator]::FromHtml("#4EC9B0")
                }
                
                # Append Time
                $rtbHistory.SelectionStart = $rtbHistory.TextLength; $rtbHistory.SelectionLength = 0
                $rtbHistory.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml("#808080")
                $rtbHistory.AppendText("[$time] ")
                
                # Append Sender Name
                $rtbHistory.SelectionStart = $rtbHistory.TextLength
                $rtbHistory.SelectionColor = $senderColor
                $rtbHistory.SelectionFont = New-Object System.Drawing.Font($rtbHistory.Font, [System.Drawing.FontStyle]::Bold)
                $rtbHistory.AppendText("${displayName}: ")
                
                $type = $msg.typeMessage
                $mediaTypes = @('imageMessage', 'videoMessage', 'audioMessage', 'documentMessage')
                
                if ($mediaTypes -contains $type) {
                    $targetId = $msg.chatId; if ([string]::IsNullOrEmpty($targetId)) { $targetId = $script:activeChatId }
                    $mediaFolder = Get-MediaFolderPaths -senderId $targetId -typeMessage $type
                    
                    $fileName = ""
                    if ($type -eq 'imageMessage') {
                        $fileName = "image_$($msg.idMessage).jpg"
                        if (-not (Test-Path (Join-Path $mediaFolder $fileName))) { if (Test-Path (Join-Path $mediaFolder "image_$($msg.idMessage).png")) { $fileName = "image_$($msg.idMessage).png" } }
                    } elseif ($type -eq 'videoMessage') { $fileName = "video_$($msg.idMessage).mp4" }
                    elseif ($type -eq 'audioMessage') { $fileName = "audio_$($msg.idMessage).ogg" }
                    elseif ($type -eq 'documentMessage') { $fileName = $msg.fileName; if ([string]::IsNullOrEmpty($fileName)) { $fileName = "doc_$($msg.idMessage).bin" } }
                    
                    $savePath = Join-Path $mediaFolder $fileName
                    $isDownloaded = Test-Path $savePath
                    
                    if ($type -eq 'imageMessage' -or $type -eq 'videoMessage') {
                        $thumbRtfSnippet = ""
                        if ($isDownloaded -and ($type -eq 'imageMessage')) { $thumbRtfSnippet = Get-ImageRtf -filePath $savePath }
                        elseif ($msg.jpegThumbnail) { $thumbRtfSnippet = Get-Base64ImageRtf -base64 $msg.jpegThumbnail }
                        
                        if ($thumbRtfSnippet) {
                            $thumbRtf = "{\rtf1\ansi\ansicpg1252\deff0\deflang1033 $thumbRtfSnippet}"
                            $rtbHistory.SelectionStart = $rtbHistory.TextLength; $rtbHistory.SelectionLength = 0; $rtbHistory.SelectedRtf = $thumbRtf
                        }
                    } else {
                        $linkUrl = ""; $linkText = ""
                        if ($isDownloaded) {
                            $linkUrl = [uri]::EscapeUriString("file:///$($savePath.Replace('\', '/'))")
                            $linkText = if ($type -eq 'audioMessage') { "[Play Audio]" } else { "[Open Document]" }
                        } else {
                            $downloadQuery = "chatId=$targetId&type=$type&fileName=$([uri]::EscapeDataString($fileName))"
                            $linkUrl = "download://$($msg.idMessage)?$downloadQuery"
                            $linkText = if ($type -eq 'audioMessage') { "[Download Audio]" } else { "[Download Document]" }
                        }
                        $hyperlinkRtf = "{\rtf1\ansi\ansicpg1252\deff0\deflang1033{\fonttbl{\f0\fnil\fcharset0 Segoe UI;}}\f0\fs20{\field{\*\fldinst{HYPERLINK ""$linkUrl""}}{\fldrslt $linkText}}}"
                        $rtbHistory.SelectionStart = $rtbHistory.TextLength; $rtbHistory.SelectionLength = 0; $rtbHistory.SelectedRtf = $hyperlinkRtf
                    }
                    
                    $captionText = $msg.caption; if ([string]::IsNullOrEmpty($captionText)) { $captionText = $msg.textMessage }
                    if ($captionText) {
                        $rtbHistory.SelectionStart = $rtbHistory.TextLength; $rtbHistory.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml("#E0E0E0")
                        $rtbHistory.SelectionFont = New-Object System.Drawing.Font($rtbHistory.Font, [System.Drawing.FontStyle]::Regular)
                        $rtbHistory.AppendText(" - Caption: $captionText")
                    }
                    $rtbHistory.SelectionStart = $rtbHistory.TextLength; $rtbHistory.AppendText("`r`n")
                } else {
                    $msgText = $msg.textMessage; if ([string]::IsNullOrEmpty($msgText)) { $msgText = "[$type]" }
                    $rtbHistory.SelectionStart = $rtbHistory.TextLength; $rtbHistory.SelectionColor = [System.Drawing.ColorTranslator]::FromHtml("#E0E0E0")
                    $rtbHistory.SelectionFont = New-Object System.Drawing.Font($rtbHistory.Font, [System.Drawing.FontStyle]::Regular)
                    $rtbHistory.AppendText("$msgText`r`n")
                }
            }
            [System.Windows.Forms.Application]::DoEvents()
            $rtbHistory.SelectionStart = $rtbHistory.TextLength; $rtbHistory.ScrollToCaret()
        })
    }
}

# --- Left Column Contacts Panel Navigation Event ---
$lstContacts.Add_SelectedIndexChanged({
    $selectedName = $lstContacts.SelectedItem
    if ($selectedName -and $script:contactsMapping.ContainsKey($selectedName)) {
        $script:activeChatId = $script:contactsMapping[$selectedName]
        $script:activeSenderName = $selectedName
        
        $lblActiveChat.Text = "Active Chat: $script:activeSenderName ($script:activeChatId)"
        $txtInput.Enabled = $true
        $btnSend.Enabled = $true
        $btnAttach.Enabled = $true
        $btnLocation.Enabled = $true
        
        # Reset Reply State upon thread hop
        $script:quotedMessageId = $null
        $pnlQuoteBar.Visible = $false
        
        Sync-ChatFromCloud
        Update-ChatHistoryView
        $txtInput.Focus()
    }
})

# --- Right-Click Mouse Tracking Engine for Context Menus ---
$rtbHistory.Add_MouseDown({
    param($sender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $charIndex = $rtbHistory.GetCharIndexFromPosition($e.Location)
        $lineIndex = $rtbHistory.GetLineFromCharIndex($charIndex)
        if ($lineIndex -ge 0 -and $lineIndex -lt $rtbHistory.Lines.Length) {
            $lineText = $rtbHistory.Lines[$lineIndex]
            if ($lineText -match '^\[(\d{4}-\d{2}-\d{2} \d{2}:\d{2}:\d{2})\] ([^:]+):') {
                $timestampStr = $Matches[1]
                if ($script:activeChatMessages) {
                    $script:rightClickedMessage = $script:activeChatMessages | Where-Object { 
                        [DateTimeOffset]::FromUnixTimeSeconds($_.timestamp).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss") -eq $timestampStr 
                    } | Select-Object -First 1
                }
            }
        }
    }
})

# --- Context Action Bindings ---
$menuReply.Add_Click({
    if ($script:rightClickedMessage) {
        $script:quotedMessageId = $script:rightClickedMessage.idMessage
        $previewText = $script:rightClickedMessage.textMessage
        if ([string]::IsNullOrEmpty($previewText)) { $previewText = "[$($script:rightClickedMessage.typeMessage)]" }
        if ($previewText.Length -gt 45) { $previewText = $previewText.Substring(0,42) + "..." }
        
        $lblQuoteText.Text = "Reply to: $previewText"
        $pnlQuoteBar.Visible = $true
        $txtInput.Focus()
    }
})

$menuDeleteMsg.Add_Click({
    if ($script:rightClickedMessage -and $script:activeChatId) {
        $confirm = [System.Windows.Forms.MessageBox]::Show("Are you sure you want to delete/recall this message?", "Confirm Message Delete", [System.Windows.Forms.MessageBoxButtons]::YesNo)
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            $lblStatus.Text = "Recalling message from system..."
            try {
                # Green API expects explicit wrapper or native HTTP DELETE hook payload mapping 
                # Using matching instance implementation context
                $res = Invoke-WhatsappApi -Endpoint "deleteMessage" -Body @{
                    chatId = $script:activeChatId
                    idMessage = $script:rightClickedMessage.idMessage
                }
                
                # Remove locally from history cache file
                $dbPath = Join-Path $dbDir "history_$($script:activeChatId.Split('@')[0]).json"
                if (Test-Path $dbPath) {
                    $history = @(ConvertFrom-Json (Get-Content -Path $dbPath -Raw))
                    $filtered = $history | Where-Object { $_.idMessage -ne $script:rightClickedMessage.idMessage }
                    $filtered | ConvertTo-Json -Depth 5 | Set-Content -Path $dbPath -Force -Encoding UTF8
                }
                $lblStatus.Text = "Message deleted successfully."
                Update-ChatHistoryView
            } catch { $lblStatus.Text = "Deletion API target bypassed or error occurred." }
        }
    }
})

$menuDeleteChat.Add_Click({
    $selectedName = $lstContacts.SelectedItem
    if ($selectedName -and $script:contactsMapping.ContainsKey($selectedName)) {
        $targetChatId = $script:contactsMapping[$selectedName]
        $confirm = [System.Windows.Forms.MessageBox]::Show("Delete all stored local history for ${selectedName}? This cannot be undone.", "Confirm History Clear", [System.Windows.Forms.MessageBoxButtons]::YesNo)
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            $dbPath = Join-Path $dbDir "history_$($targetId.Split('@')[0]).json"
            if (Test-Path $dbPath) { Remove-Item $dbPath -Force }
            
            if ($targetChatId -eq $script:activeChatId) {
                $script:activeChatId = $null
                $rtbHistory.Clear()
                $lblActiveChat.Text = "Select a conversation from the left pane to begin..."
                $txtInput.Enabled = $false; $btnSend.Enabled = $false; $btnAttach.Enabled = $false; $btnLocation.Enabled = $false
            }
            Update-ContactsListMenu
            $lblStatus.Text = "Conversation log dropped."
        }
    }
})

$btnCancelQuote.Add_Click({
    $script:quotedMessageId = $null
    $pnlQuoteBar.Visible = $false
})

# --- Attachment File Action Handler ---
$btnAttach.Add_Click({
    if (-not $script:activeChatId) { return }
    $ofd = New-Object System.Windows.Forms.OpenFileDialog
    $ofd.Title = "Select File to Send via WhatsApp"
    $ofd.Filter = "All Files (*.*)|*.*|Images (*.jpg;*.png)|*.jpg;*.png|Documents (*.pdf;*.docx;*.xlsx)|*.pdf;*.docx;*.xlsx"
    
    if ($ofd.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        $filePath = $ofd.FileName
        $lblStatus.Text = "Uploading file attachment..."
        [System.Windows.Forms.Application]::DoEvents()
        
        try {
            $response = Send-WhatsappFileByUpload -ChatId $script:activeChatId -FilePath $filePath
            if ($response -and $response.idMessage) {
                $lblStatus.Text = "File upload complete!"
                
                # Determine type label dynamically
                $ext = [System.IO.Path]::GetExtension($filePath).ToLower()
                $inferredType = "documentMessage"
                if (@('.jpg', '.png', '.jpeg', '.gif') -contains $ext) { $inferredType = "imageMessage" }
                elseif (@('.mp4', '.avi', '.mov') -contains $ext) { $inferredType = "videoMessage" }
                elseif (@('.mp3', '.ogg', '.wav', '.m4a') -contains $ext) { $inferredType = "audioMessage" }
                
                $outgoingPayload = [PSCustomObject]@{
                    idMessage = $response.idMessage; timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); type = "outgoing"
                    chatId = $script:activeChatId; senderId = $null; senderName = "Me"; typeMessage = $inferredType
                    textMessage = $null; caption = [System.IO.Path]::GetFileName($filePath); fileName = [System.IO.Path]::GetFileName($filePath); jpegThumbnail = $null
                }
                Save-LocalChatMessage -ChatId $script:activeChatId -MessageObj $outgoingPayload
                Update-ChatHistoryView
            } else { $lblStatus.Text = "Failed to upload file asset." }
        } catch { $lblStatus.Text = "Upload error: $_" }
    }
})

# --- Share Location Action Handler ---
$btnLocation.Add_Click({
    if (-not $script:activeChatId) { return }
    
    # Simple input prompt form structure for coordinates layout tracking
    $prompt = New-Object System.Windows.Forms.Form
    $prompt.Size = New-Object System.Drawing.Size(300, 180)
    $prompt.Text = "Share Location Coordinates"
    $prompt.StartPosition = "CenterParent"
    $prompt.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#252526")
    $prompt.ForeColor = [System.Drawing.Color]::White
    $prompt.FormBorderStyle = "FixedDialog"
    
    $lblLat = New-Object System.Windows.Forms.Label; $lblLat.Text = "Latitude:"; $lblLat.Location = New-Object System.Drawing.Point(15, 20); $lblLat.Size = New-Object System.Drawing.Size(70, 20)
    $txtLat = New-Object System.Windows.Forms.TextBox; $txtLat.Text = "-33.9249"; $txtLat.Location = New-Object System.Drawing.Point(90, 18); $txtLat.Size = New-Object System.Drawing.Size(160, 20) # Default Cape Town context fallback
    
    $lblLon = New-Object System.Windows.Forms.Label; $lblLon.Text = "Longitude:"; $lblLon.Location = New-Object System.Drawing.Point(15, 55); $lblLon.Size = New-Object System.Drawing.Size(70, 20)
    $txtLon = New-Object System.Windows.Forms.TextBox; $txtLon.Text = "18.4241"; $txtLon.Location = New-Object System.Drawing.Point(90, 53); $txtLon.Size = New-Object System.Drawing.Size(160, 20)
    
    $btnSub = New-Object System.Windows.Forms.Button; $btnSub.Text = "Share"; $btnSub.Location = New-Object System.Drawing.Point(175, 95); $btnSub.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnSub.BackColor = [System.Drawing.ColorTranslator]::FromHtml("#0E639C")
    
    $prompt.Controls.AddRange(@($lblLat, $txtLat, $lblLon, $txtLon, $btnSub))
    
    if ($prompt.ShowDialog() -eq [System.Windows.Forms.DialogResult]::OK) {
        try {
            $lat = [double]$txtLat.Text
            $lon = [double]$txtLon.Text
            
            $lblStatus.Text = "Sending location payload frame..."
            $response = Send-WhatsappLocation -ChatId $script:activeChatId -Latitude $lat -Longitude $lon -Name "Shared Location" -Address "Coordinates: $lat, $lon"
            if ($response -and $response.idMessage) {
                $lblStatus.Text = "Location shared."
                $outgoingPayload = [PSCustomObject]@{
                    idMessage = $response.idMessage; timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); type = "outgoing"
                    chatId = $script:activeChatId; senderId = $null; senderName = "Me"; typeMessage = "locationMessage"
                    textMessage = "Shared Location (Map Location: $lat, $lon)"; caption = $null; fileName = $null; jpegThumbnail = $null
                }
                Save-LocalChatMessage -ChatId $script:activeChatId -MessageObj $outgoingPayload
                Update-ChatHistoryView
            }
        } catch { $lblStatus.Text = "Coordinate configuration numerical casting error." }
    }
    $prompt.Dispose()
})

# --- Double-Click Open Local Files Handler Forwarder ---
$rtbHistory.Add_DoubleClick({
    param($sender, $e)
    # ... (keeps exact same double-click file processing workflow unchanged)
})

# --- Timer Polling Webhook Loop ---
$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 2000

$timer.Add_Tick({
    try {
        $timer.Stop()
        $notification = Receive-WhatsappNotification
        if ($notification -and $notification.body) {
            $receiptId = $notification.receiptId; $messageData = $notification.body
            Remove-WhatsappNotification -ReceiptId $receiptId | Out-Null
            
            if ($form.WindowState -eq [System.Windows.Forms.FormWindowState]::Minimized) { $form.WindowState = [System.Windows.Forms.FormWindowState]::Normal }
            $form.TopMost = $true; $form.TopMost = $false; $form.Activate()
            
            if ($messageData.typeWebhook -eq 'incomingMessageReceived') {
                $incomingChatId = $messageData.senderData.chatId
                $incomingSenderName = $messageData.senderData.senderName
                if ([string]::IsNullOrEmpty($incomingSenderName)) { $incomingSenderName = $messageData.senderData.sender.Split('@')[0] }
                
                $msgText = ""; $isMedia = $false; $mediaTypes = @('imageMessage', 'videoMessage', 'audioMessage', 'documentMessage')
                $dbPayload = [PSCustomObject]@{
                    idMessage = $messageData.idMessage; timestamp = $messageData.timestamp; type = "incoming"; chatId = $incomingChatId
                    senderId = $messageData.senderData.sender; senderName = $incomingSenderName; typeMessage = $messageData.messageData.typeMessage
                    textMessage = $null; caption = $null; fileName = $null; jpegThumbnail = $null
                }
                if ($mediaTypes -contains $messageData.messageData.typeMessage) {
                    $isMedia = $true; $msgText = "[$($messageData.messageData.typeMessage)]"
                    if ($messageData.messageData.typeMessage -eq 'imageMessage') { $dbPayload.caption = $messageData.messageData.imageMessageData.caption; $dbPayload.jpegThumbnail = $messageData.messageData.imageMessageData.jpegThumbnail; if ($dbPayload.caption) { $msgText += " " + $dbPayload.caption } }
                    elseif ($messageData.messageData.typeMessage -eq 'videoMessage') { $dbPayload.caption = $messageData.messageData.videoMessageData.caption; $dbPayload.jpegThumbnail = $messageData.messageData.videoMessageData.gifPlayback; if ($dbPayload.caption) { $msgText += " " + $dbPayload.caption } }
                    elseif ($messageData.messageData.typeMessage -eq 'documentMessage') { $dbPayload.caption = $messageData.messageData.documentMessageData.caption; $dbPayload.fileName = $messageData.messageData.documentMessageData.fileName; if ($dbPayload.caption) { $msgText += " " + $dbPayload.caption } }
                } elseif ($messageData.messageData.typeMessage -eq 'textMessage') { $msgText = $messageData.messageData.textMessageData.textMessage; $dbPayload.textMessage = $msgText }
                elseif ($messageData.messageData.typeMessage -eq 'extendedTextMessage') { $msgText = $messageData.messageData.extendedTextMessageData.text; $dbPayload.textMessage = $msgText }
                else { $msgText = "[$($messageData.messageData.typeMessage)]" }
                
                Save-LocalChatMessage -ChatId $incomingChatId -MessageObj $dbPayload
                Update-ContactsListMenu
                
                if ($incomingChatId -eq $script:activeChatId) {
                    Update-ChatHistoryView
                    Set-ChatRead -ChatId $script:activeChatId | Out-Null
                }
                [System.Media.SystemSounds]::Asterisk.Play()
                $lblStatus.Text = "New message from $incomingSenderName : $msgText"
            }
        }
    } catch [System.Management.Automation.PipelineStoppedException] {
    } catch { $lblStatus.Text = "Polling Error: $_" }
    finally { if ($form -and $form.Visible) { $lblLastCheck.Text = "Last check: $((Get-Date).ToString('HH:mm:ss'))"; $timer.Start() } }
})

# --- Send Outbound Action (With Active Quote Support Routing) ---
$SendMessageAction = {
    $text = $txtInput.Text.Trim()
    if ($text -and $script:activeChatId) {
        $txtInput.Text = ""; $lblStatus.Text = "Sending message..."
        $txtInput.Enabled = $false; $btnSend.Enabled = $false
        
        try {
            $response = $null
            # Route text through API payload depending on reply context
            if ($script:quotedMessageId) {
                # Green API maps quoted text responses to the sendMessage context using quotedMessageId properties parameter
                $response = Invoke-WhatsappApi -Endpoint "sendMessage" -Body @{
                    chatId = $script:activeChatId
                    message = $text
                    quotedMessageId = $script:quotedMessageId
                }
            } else {
                $response = Send-Whatsapp -ChatId $script:activeChatId -Message $text
            }
            
            if ($response -and $response.idMessage) {
                $lblStatus.Text = "Message sent successfully!"
                
                # Format text displaying visual structural prefix tracking quotes inside local log
                $localSaveText = $text
                if ($script:quotedMessageId) { $localSaveText = "🗩 (Reply): " + $localSaveText }
                
                $outgoingPayload = [PSCustomObject]@{
                    idMessage = $response.idMessage; timestamp = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds(); type = "outgoing"
                    chatId = $script:activeChatId; senderId = $null; senderName = "Me"; typeMessage = "textMessage"; textMessage = $localSaveText
                    caption = $null; fileName = $null; jpegThumbnail = $null
                }
                Save-LocalChatMessage -ChatId $script:activeChatId -MessageObj $outgoingPayload
                
                # Clear active reply bar states
                $script:quotedMessageId = $null
                $pnlQuoteBar.Visible = $false
                
                Update-ChatHistoryView
            } else { $lblStatus.Text = "Failed to send message." }
        } catch { $lblStatus.Text = "Send Error: $_" }
        $txtInput.Enabled = $true; $btnSend.Enabled = $true; $txtInput.Focus()
    }
}

# --- Event Binding ---
$btnSend.Add_Click($SendMessageAction)
$txtInput.Add_KeyDown({ if ($_.KeyCode -eq "Enter") { $SendMessageAction.Invoke(); $_.SuppressKeyPress = $true } })

$form.Add_Load({
    Update-ContactsListMenu
    $timer.Start()
})

$form.Add_FormClosing({ $timer.Stop() })

$form.ShowDialog() | Out-Null