Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# Import the module and load configurations
Import-Module .\PHKustomWhatsapp.psd1 -Force
Get-WhatsappConfig | Out-Null

# --- Ensure Databases and Config Folder Exists ---
$dbDir = Join-Path $env:APPDATA "PHWhatsapp\Database"
if (-not (Test-Path $dbDir)) {
    New-Item -ItemType Directory -Path $dbDir -Force | Out-Null
}
$downloadsParentFolder = Join-Path $env:APPDATA "PHWhatsapp"
$contactsCacheFile = Join-Path $env:APPDATA "PHWhatsapp\contacts.json"

# --- Design Palette Constants (WhatsApp Dark Web Style - Script Scoped for Delegate Thread Safety) ---
$script:colorMainBg      = [System.Drawing.ColorTranslator]::FromHtml("#111B21")
$script:colorSidebarBg   = [System.Drawing.ColorTranslator]::FromHtml("#111B21")
$script:colorHeaderBg    = [System.Drawing.ColorTranslator]::FromHtml("#202C33")
$script:colorChatBg      = [System.Drawing.ColorTranslator]::FromHtml("#0B141A")
$script:colorInputBg     = [System.Drawing.ColorTranslator]::FromHtml("#202C33")
$script:colorTextMain    = [System.Drawing.ColorTranslator]::FromHtml("#E9EDEF")
$script:colorTextMuted   = [System.Drawing.ColorTranslator]::FromHtml("#8696A0")
$script:colorAccent      = [System.Drawing.ColorTranslator]::FromHtml("#00A884") # WhatsApp Green
$script:colorSelectBg    = [System.Drawing.ColorTranslator]::FromHtml("#2A3942")
$script:colorBubbleIn    = [System.Drawing.ColorTranslator]::FromHtml("#202C33")
$script:colorBubbleOut   = [System.Drawing.ColorTranslator]::FromHtml("#005C4B")

$script:fontSegoeRegular = New-Object System.Drawing.Font("Segoe UI", 9.5)

# --- Global States ---
$script:activeChatId = $null
$script:activeSenderName = ""
$script:quotedMessageId = $null
$script:rightClickedMessage = $null
$script:contactsMapping = @{}     # DisplayName -> ChatId
$script:contactsCache = @{}       # ChatId -> Contact Details Object
$script:allContacts = @()         # Full list of WhatsApp contacts from API/Cache
$script:lastSyncTimes = @{}       # ChatId -> DateTime
$script:unreadCounts = @{}        # ChatId -> Count

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

# --- Contacts API/Local Loader ---
function Import-AllContacts {
    # 1. Attempt to load from local cache file contacts.json
    if (Test-Path $contactsCacheFile) {
        try {
            $raw = Get-Content -Path $contactsCacheFile -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $script:allContacts = @(ConvertFrom-Json $raw)
            }
        }
        catch {}
    }
    
    # 2. Query all contacts via Get-Contacts if local cache is empty
    if ($script:allContacts.Count -eq 0) {
        try {
            $apiContacts = Get-Contacts
            if ($apiContacts) {
                $script:allContacts = @()
                foreach ($c in $apiContacts) {
                    $name = $c.name
                    if ([string]::IsNullOrEmpty($name)) {
                        $name = $c.id.Split('@')[0]
                    }
                    $script:allContacts += [PSCustomObject]@{
                        id   = $c.id
                        name = $name
                        type = $c.type
                    }
                }
                # Save to cache file
                $script:allContacts | ConvertTo-Json -Depth 5 | Set-Content -Path $contactsCacheFile -Force -Encoding UTF8
            }
        }
        catch {
            Write-Warning "Could not fetch contacts list from Green API: $_"
        }
    }
}

# --- Main Window Form Configuration ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "PHKustom WhatsApp Chat Center"
$form.Size = New-Object System.Drawing.Size(1150, 750)
$form.StartPosition = "CenterScreen"
$form.BackColor = $script:colorMainBg
$form.ForeColor = $script:colorTextMain
$form.Font = $script:fontSegoeRegular

# --- Layout Container Split (20% Left Column / 80% Right Column) ---
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

# --- Left Column Search Box Panel ---
$pnlSearch = New-Object System.Windows.Forms.Panel
$pnlSearch.Dock = "Top"
$pnlSearch.Height = 55
$pnlSearch.BackColor = $script:colorSidebarBg

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(15, 12)
$txtSearch.Size = New-Object System.Drawing.Size(($pnlSearch.Width - 30), 30)
$txtSearch.BackColor = $script:colorInputBg
$txtSearch.ForeColor = $script:colorTextMain
$txtSearch.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtSearch.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$txtSearch.Text = ""

$pnlLeft.Controls.Add($pnlSearch)
$pnlSearch.Controls.Add($txtSearch)

# Handle search box resize dynamically
$pnlSearch.Add_Resize({
    $txtSearch.Width = [Math]::Max(50, ($pnlSearch.Width - 30))
})

# --- Profile / Instance Info Panel ---
$pnlProfile = New-Object System.Windows.Forms.Panel
$pnlProfile.Dock = "Top"
$pnlProfile.Height = 65
$pnlProfile.BackColor = $script:colorHeaderBg

$lblProfileInstance = New-Object System.Windows.Forms.Label
$lblProfileInstance.Location = New-Object System.Drawing.Point(65, 14)
$lblProfileInstance.Size = New-Object System.Drawing.Size(($pnlProfile.Width - 75), 18)
$lblProfileInstance.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$lblProfileInstance.ForeColor = $script:colorTextMain
$lblProfileInstance.Text = "Instance: $($global:InstanceId)"

$lblProfileStatus = New-Object System.Windows.Forms.Label
$lblProfileStatus.Location = New-Object System.Drawing.Point(65, 34)
$lblProfileStatus.Size = New-Object System.Drawing.Size(($pnlProfile.Width - 75), 15)
$lblProfileStatus.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblProfileStatus.ForeColor = $script:colorAccent
$lblProfileStatus.Text = "Status: Authorized"

$pnlProfile.Controls.AddRange(@($lblProfileInstance, $lblProfileStatus))
$pnlLeft.Controls.Add($pnlProfile)
$pnlProfile.BringToFront()

# Handle profile label resizing dynamically
$pnlProfile.Add_Resize({
    $lblProfileInstance.Width = [Math]::Max(50, ($pnlProfile.Width - 75))
    $lblProfileStatus.Width = [Math]::Max(50, ($pnlProfile.Width - 75))
})

$pnlProfile.Add_Paint({
    param($evtSender, $e)
    $graphics = $e.Graphics
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    
    $avatarRect = [System.Drawing.Rectangle]::new(15, 10, 42, 42)
    $avatarBrush = New-Object System.Drawing.SolidBrush($script:colorSelectBg)
    $graphics.FillEllipse($avatarBrush, $avatarRect)
    
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 2)
    $graphics.DrawEllipse($pen, 28, 16, 16, 16)
    $graphics.DrawArc($pen, 21, 36, 30, 20, 180, 180)
    
    $avatarBrush.Dispose()
    $pen.Dispose()
})

# Contact ListBox (Owner Drawn)
$lstContacts = New-Object System.Windows.Forms.ListBox
$lstContacts.Dock = "Fill"
$lstContacts.BackColor = $script:colorSidebarBg
$lstContacts.ForeColor = $script:colorTextMain
$lstContacts.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$lstContacts.Font = New-Object System.Drawing.Font("Segoe UI", 10.5)
$lstContacts.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$lstContacts.ItemHeight = 65
$pnlLeft.Controls.Add($lstContacts)

# Left Column Context Menu (Delete Entire Chat Thread)
$ctxChatMenu = New-Object System.Windows.Forms.ContextMenuStrip
$menuDeleteChat = $ctxChatMenu.Items.Add("Delete Conversation History")
$lstContacts.ContextMenuStrip = $ctxChatMenu

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
$lblActiveContact.Text = "Select a contact to start chat"

$lblActiveStatus = New-Object System.Windows.Forms.Label
$lblActiveStatus.Location = New-Object System.Drawing.Point(70, 32)
$lblActiveStatus.Size = New-Object System.Drawing.Size(600, 15)
$lblActiveStatus.Font = New-Object System.Drawing.Font("Segoe UI", 8.5)
$lblActiveStatus.ForeColor = $script:colorTextMuted
$lblActiveStatus.Text = ""

$pnlHeader.Controls.AddRange(@($lblActiveContact, $lblActiveStatus))
$pnlRight.Controls.Add($pnlHeader)

# Message History RichTextBox
$rtbHistory = New-Object System.Windows.Forms.RichTextBox
$rtbHistory.Dock = "Fill"
$rtbHistory.BackColor = $script:colorChatBg
$rtbHistory.ForeColor = $script:colorTextMain
$rtbHistory.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbHistory.ReadOnly = $true
$rtbHistory.DetectUrls = $true
$pnlRight.Controls.Add($rtbHistory)
$rtbHistory.BringToFront() # Ensures it fills space below header correctly

# Active Quote Bar (Replies)
$pnlQuoteBar = New-Object System.Windows.Forms.Panel
$pnlQuoteBar.Dock = "Bottom"
$pnlQuoteBar.Height = 45
$pnlQuoteBar.BackColor = $script:colorHeaderBg
$pnlQuoteBar.Visible = $false

$lblQuoteText = New-Object System.Windows.Forms.Label
$lblQuoteText.Location = New-Object System.Drawing.Point(15, 12)
$lblQuoteText.Size = New-Object System.Drawing.Size(700, 20)
$lblQuoteText.ForeColor = $script:colorAccent
$lblQuoteText.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Italic)
$lblQuoteText.Text = ""

$btnCancelQuote = New-Object System.Windows.Forms.Button
$btnCancelQuote.Location = New-Object System.Drawing.Point(730, 8)
$btnCancelQuote.Size = New-Object System.Drawing.Size(30, 30)
$btnCancelQuote.Text = "X"
$btnCancelQuote.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCancelQuote.FlatAppearance.BorderSize = 0
$btnCancelQuote.ForeColor = $script:colorTextMuted
$btnCancelQuote.Font = New-Object System.Drawing.Font("Segoe UI", 9, [System.Drawing.FontStyle]::Bold)

$pnlQuoteBar.Controls.AddRange(@($lblQuoteText, $btnCancelQuote))
$pnlRight.Controls.Add($pnlQuoteBar)

# Bottom Input Control Panel
$pnlInput = New-Object System.Windows.Forms.Panel
$pnlInput.Dock = "Bottom"
$pnlInput.Height = 60
$pnlInput.BackColor = $script:colorHeaderBg

$btnAttach = New-Object System.Windows.Forms.Button
$btnAttach.Location = New-Object System.Drawing.Point(12, 12)
$btnAttach.Size = New-Object System.Drawing.Size(42, 36)
$btnAttach.Text = "+"
$btnAttach.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnAttach.FlatAppearance.BorderSize = 0
$btnAttach.BackColor = $script:colorSelectBg
$btnAttach.ForeColor = $script:colorTextMain
$btnAttach.Font = New-Object System.Drawing.Font("Segoe UI", 12)

$btnLocation = New-Object System.Windows.Forms.Button
$btnLocation.Location = New-Object System.Drawing.Point(60, 12)
$btnLocation.Size = New-Object System.Drawing.Size(42, 36)
$btnLocation.Text = "Loc"
$btnLocation.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnLocation.FlatAppearance.BorderSize = 0
$btnLocation.BackColor = $script:colorSelectBg
$btnLocation.ForeColor = $script:colorTextMain
$btnLocation.Font = New-Object System.Drawing.Font("Segoe UI", 10)

$txtInput = New-Object System.Windows.Forms.TextBox
$txtInput.Location = New-Object System.Drawing.Point(115, 14)
$txtInput.Size = New-Object System.Drawing.Size(610, 30)
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

$pnlInput.Controls.AddRange(@($btnAttach, $btnLocation, $txtInput, $btnSend))
$pnlRight.Controls.Add($pnlInput)

# --- Right Column splash Screen panel (WhatsApp Web style) ---
$pnlSplash = New-Object System.Windows.Forms.Panel
$pnlSplash.Dock = "Fill"
$pnlSplash.BackColor = $script:colorChatBg
$pnlSplash.Visible = $true

$pnlSplashContent = New-Object System.Windows.Forms.Panel
$pnlSplashContent.Size = New-Object System.Drawing.Size(500, 350)
$pnlSplashContent.Location = New-Object System.Drawing.Point(150, 150)
$pnlSplashContent.BackColor = [System.Drawing.Color]::Transparent

$lblSplashTitle = New-Object System.Windows.Forms.Label
$lblSplashTitle.Text = "Green API Web Console"
$lblSplashTitle.Font = New-Object System.Drawing.Font("Segoe UI", 20, [System.Drawing.FontStyle]::Bold)
$lblSplashTitle.ForeColor = $script:colorTextMain
$lblSplashTitle.Size = New-Object System.Drawing.Size(500, 45)
$lblSplashTitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblSplashTitle.Location = New-Object System.Drawing.Point(0, 120)

$lblSplashSubtitle = New-Object System.Windows.Forms.Label
$lblSplashSubtitle.Text = "Send and receive messages without keeping your phone online.`r`nSyncs automatically with Green API channels."
$lblSplashSubtitle.Font = New-Object System.Drawing.Font("Segoe UI", 10.5)
$lblSplashSubtitle.ForeColor = $script:colorTextMuted
$lblSplashSubtitle.Size = New-Object System.Drawing.Size(500, 60)
$lblSplashSubtitle.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblSplashSubtitle.Location = New-Object System.Drawing.Point(0, 180)

$lblSplashFootnote = New-Object System.Windows.Forms.Label
$lblSplashFootnote.Text = "[Encrypted] End-to-end encrypted"
$lblSplashFootnote.Font = New-Object System.Drawing.Font("Segoe UI", 9)
$lblSplashFootnote.ForeColor = $script:colorTextMuted
$lblSplashFootnote.Size = New-Object System.Drawing.Size(500, 30)
$lblSplashFootnote.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblSplashFootnote.Location = New-Object System.Drawing.Point(0, 300)

$pnlSplashContent.Controls.AddRange(@($lblSplashTitle, $lblSplashSubtitle, $lblSplashFootnote))
$pnlSplash.Controls.Add($pnlSplashContent)
$pnlRight.Controls.Add($pnlSplash)
$pnlSplash.BringToFront()

$pnlSplash.Add_Resize({
    $pnlSplashContent.Location = New-Object System.Drawing.Point(
        [Math]::Max(0, ($pnlSplash.Width - $pnlSplashContent.Width) / 2),
        [Math]::Max(0, ($pnlSplash.Height - $pnlSplashContent.Height) / 2)
    )
})

$pnlSplashContent.Add_Paint({
    param($evtSender, $e)
    $graphics = $e.Graphics
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    
    $logoRect = [System.Drawing.Rectangle]::new(210, 20, 80, 80)
    $logoBrush = New-Object System.Drawing.SolidBrush($script:colorAccent)
    $graphics.FillEllipse($logoBrush, $logoRect)
    
    $pen = New-Object System.Drawing.Pen([System.Drawing.Color]::White, 4)
    $bubbleRect = [System.Drawing.Rectangle]::new(230, 42, 40, 30)
    $graphics.DrawRectangle($pen, $bubbleRect)
    
    $graphics.DrawLine($pen, 240, 72, 235, 78)
    $graphics.DrawLine($pen, 235, 78, 248, 72)
    
    $logoBrush.Dispose()
    $pen.Dispose()
})

# Bottom Status Strip
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.BackColor = $script:colorHeaderBg
$lblStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStatus.ForeColor = $script:colorTextMuted
$lblStatus.Text = "System active."
$lblLastCheck = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblLastCheck.ForeColor = $script:colorTextMuted
$lblLastCheck.Text = ""
$statusStrip.Items.AddRange(@($lblStatus, $lblLastCheck))
$form.Controls.Add($statusStrip)

# Right-click individual message context actions (Reply & DeleteMsg)
$ctxMsgMenu = New-Object System.Windows.Forms.ContextMenuStrip
$menuReply = $ctxMsgMenu.Items.Add("Reply (Quote)")
$menuDeleteMsg = $ctxMsgMenu.Items.Add("Delete/Recall Message")

# --- UI Update Action: Left Column Contact List populator ---
function Update-ContactsListMenu {
    $currentSelection = $lstContacts.SelectedItem
    $lstContacts.Items.Clear()
    $script:contactsMapping.Clear()
    $script:contactsCache.Clear()
    
    # Load WhatsApp contact database
    if ($script:allContacts.Count -eq 0) {
        Import-AllContacts
    }
    
    # Step 1: Map all known contacts by their ChatId
    $tempContacts = @{}
    foreach ($c in $script:allContacts) {
        $tempContacts[$c.id] = [PSCustomObject]@{
            ChatId      = $c.id
            DisplayName = $c.name
            LastText    = "Click to chat..."
            Timestamp   = 0
            TimeStr     = ""
            Initials    = Get-Initials -Name $c.name
        }
    }
    
    # Step 2: Read local history directory files to overlay recent activity
    $historyFiles = Get-ChildItem -Path $dbDir -Filter "history_*.json"
    foreach ($file in $historyFiles) {
        if ($file.BaseName -match '^history_(.+)$') {
            $rawId = $Matches[1]
            $fullChatId = if ($rawId -match '@') { $rawId } else { "$rawId@c.us" }
            
            try {
                $rawContent = Get-Content -Path $file.FullName -Raw -ErrorAction SilentlyContinue
                if ($rawContent) {
                    $messages = ConvertFrom-Json $rawContent
                    $lastMessage = $messages | Sort-Object timestamp | Select-Object -Last 1
                    
                    if ($lastMessage) {
                        $displayName = $lastMessage.senderName
                        if ([string]::IsNullOrEmpty($displayName)) {
                            # Fallback using contact address book
                            if ($tempContacts.ContainsKey($fullChatId)) {
                                $displayName = $tempContacts[$fullChatId].DisplayName
                            }
                            else {
                                $displayName = $rawId
                            }
                        }
                        
                        $lastText = "Click to chat..."
                        if ($lastMessage.typeMessage -eq 'textMessage') {
                            $lastText = $lastMessage.textMessage
                        }
                        elseif ($lastMessage.typeMessage) {
                            $cleanedType = $lastMessage.typeMessage -replace 'Message', ''
                            $lastText = "[File] $cleanedType"
                        }
                        
                        # Convert timestamp to human-readable string
                        $timeStr = ""
                        $localTime = [DateTimeOffset]::FromUnixTimeSeconds($lastMessage.timestamp).LocalDateTime
                        if ($localTime.Date -eq [DateTime]::Today) {
                            $timeStr = $localTime.ToString("HH:mm")
                        }
                        elseif ($localTime.Date -eq [DateTime]::Today.AddDays(-1)) {
                            $timeStr = "Yesterday"
                        }
                        else {
                            $timeStr = $localTime.ToString("yyyy-MM-dd")
                        }
                        
                        $tempContacts[$fullChatId] = [PSCustomObject]@{
                            ChatId      = $fullChatId
                            DisplayName = $displayName
                            LastText    = $lastText
                            Timestamp   = $lastMessage.timestamp
                            TimeStr     = $timeStr
                            Initials    = Get-Initials -Name $displayName
                        }
                    }
                }
            }
            catch {}
        }
    }
    
    # Step 3: Search Filter and Sort
    $searchText = $txtSearch.Text.Trim()
    $contactsList = @($tempContacts.Values)
    
    if ($searchText) {
        $contactsList = $contactsList | Where-Object {
            $_.DisplayName -like "*$searchText*" -or $_.ChatId -like "*$searchText*"
        }
    }
    
    # Sort hierarchy:
    # 1. Contacts with history (Timestamp > 0) descending by activity timestamp
    # 2. Inactive contacts alphabetically
    $activeContacts = $contactsList | Where-Object { $_.Timestamp -gt 0 } | Sort-Object Timestamp -Descending
    $inactiveContacts = $contactsList | Where-Object { $_.Timestamp -eq 0 } | Sort-Object DisplayName
    
    $sortedContacts = @($activeContacts) + @($inactiveContacts)
    
    # Step 4: Add to ListBox control mapping
    foreach ($contact in $sortedContacts) {
        $lstContacts.Items.Add($contact.DisplayName) | Out-Null
        $script:contactsMapping[$contact.DisplayName] = $contact.ChatId
        $script:contactsCache[$contact.ChatId] = $contact
    }
    
    # Restore selection if it existed
    if ($currentSelection -and $lstContacts.Items.Contains($currentSelection)) {
        $lstContacts.SelectedItem = $currentSelection
    }
}

# --- Owner-Drawn Contacts List Drawing Hook ---
$lstContacts.Add_DrawItem({
    param($evtSender, $e)
    if ($e.Index -lt 0 -or $e.Index -ge $evtSender.Items.Count) { return }
    $graphics = $e.Graphics
    $itemText = $evtSender.Items[$e.Index]
    
    # State flags
    $isSelected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected
    
    # Background brush
    $backColor = if ($isSelected) { $script:colorSelectBg } else { $script:colorSidebarBg }
    $backBrush = New-Object System.Drawing.SolidBrush($backColor)
    $graphics.FillRectangle($backBrush, $e.Bounds)
    
    # Get details
    $mappedId = $script:contactsMapping[$itemText]
    $contact = $script:contactsCache[$mappedId]
    
    if ($contact) {
        $bounds = $e.Bounds
        
        # Circle Avatar bounds
        $avatarRect = [System.Drawing.Rectangle]::new(($bounds.X + 15), ($bounds.Y + 10), 45, 45)
        $avatarColor = Get-AvatarColor -Name $contact.DisplayName
        $avatarBrush = New-Object System.Drawing.SolidBrush($avatarColor)
        
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.FillEllipse($avatarBrush, $avatarRect)
        
        # Initials Text
        $initials = $contact.Initials
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
        
        # Contact Name
        $nameFont = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)
        $nameBrush = New-Object System.Drawing.SolidBrush($script:colorTextMain)
        $graphics.DrawString($contact.DisplayName, $nameFont, $nameBrush, ($bounds.X + 75), ($bounds.Y + 12))
        
        # Last Message Snippet
        $snippetFont = New-Object System.Drawing.Font("Segoe UI", 9.5)
        $snippetBrush = New-Object System.Drawing.SolidBrush($script:colorTextMuted)
        
        $snippetWidthLimit = $bounds.Width - 145
        $truncatedText = $contact.LastText
        $measuredWidth = $graphics.MeasureString($truncatedText, $snippetFont).Width
        if ($measuredWidth -gt $snippetWidthLimit) {
            while ($truncatedText.Length -gt 4 -and $measuredWidth -gt $snippetWidthLimit) {
                $truncatedText = $truncatedText.Substring(0, $truncatedText.Length - 4) + "..."
                $measuredWidth = $graphics.MeasureString($truncatedText, $snippetFont).Width
            }
        }
        $graphics.DrawString($truncatedText, $snippetFont, $snippetBrush, ($bounds.X + 75), ($bounds.Y + 36))
        
        # Time badge
        $timeFont = New-Object System.Drawing.Font("Segoe UI", 8.5)
        $timeBrush = New-Object System.Drawing.SolidBrush($script:colorTextMuted)
        $timeSize = $graphics.MeasureString($contact.TimeStr, $timeFont)
        $graphics.DrawString($contact.TimeStr, $timeFont, $timeBrush, ($bounds.Right - $timeSize.Width - 15), ($bounds.Y + 15))
        
        # Draw unread count badge
        $unreadCount = $script:unreadCounts[$contact.ChatId]
        if ($unreadCount -gt 0) {
            $badgeRect = [System.Drawing.Rectangle]::new(($bounds.Right - 35), ($bounds.Y + 36), 20, 20)
            $badgeBrush = New-Object System.Drawing.SolidBrush($script:colorAccent)
            $graphics.FillEllipse($badgeBrush, $badgeRect)
            
            $badgeFont = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
            $badgeTextBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
            $badgeTextSize = $graphics.MeasureString($unreadCount.ToString(), $badgeFont)
            $graphics.DrawString(
                $unreadCount.ToString(),
                $badgeFont,
                $badgeTextBrush,
                $badgeRect.X + ($badgeRect.Width - $badgeTextSize.Width) / 2,
                $badgeRect.Y + ($badgeRect.Height - $badgeTextSize.Height) / 2
            )
            $badgeBrush.Dispose()
            $badgeFont.Dispose()
            $badgeTextBrush.Dispose()
        }

        # Clean resources
        $backBrush.Dispose()
        $avatarBrush.Dispose()
        $avatarFont.Dispose()
        $textBrush.Dispose()
        $nameFont.Dispose()
        $nameBrush.Dispose()
        $snippetFont.Dispose()
        $snippetBrush.Dispose()
        $timeFont.Dispose()
        $timeBrush.Dispose()
    }
    else {
        $backBrush.Dispose()
    }
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
        
        # Draw initials
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

# --- Left Column Contacts Panel Navigation Event ---
$lstContacts.Add_SelectedIndexChanged({
    $selectedName = $lstContacts.SelectedItem
    if ($selectedName) {
        $chatId = $script:contactsMapping[$selectedName]
        $script:activeChatId = $chatId
        $script:activeSenderName = $selectedName
        
        $lblActiveContact.Text = $selectedName
        $lblActiveStatus.Text = $chatId
        $lblStatus.Text = "Loading chat conversation..."
        
        # Hide splash panel
        $pnlSplash.Visible = $false
        
        # Clear unread count state
        $script:unreadCounts[$chatId] = 0
        
        # Clear active quote state
        $script:quotedMessageId = $null
        $pnlQuoteBar.Visible = $false
        
        # Trigger immediate async cloud sync check, then display cache
        Sync-ChatFromCloud
        Update-ChatHistoryView
        
        try {
            $null = Set-ChatRead -ChatId $chatId
        }
        catch {}
        
        $lblStatus.Text = "Chat loaded."
        $pnlHeader.Invalidate()
    }
})

# --- Contact Filter Event ---
$txtSearch.Add_TextChanged({
    Update-ContactsListMenu
})

# --- Cloud Sync Engine ---
function Sync-ChatFromCloud {
    if (-not $script:activeChatId) { return }
    if ($script:activeChatId -eq '0@c.us') {
        $lblStatus.Text = "System channel: Cloud sync bypassed."
        return
    }
    
    # Throttle cloud sync to once every 5 minutes per contact to prevent Green API 429 Too Many Requests rate-limiting
    if ($script:lastSyncTimes.ContainsKey($script:activeChatId)) {
        $lastSync = $script:lastSyncTimes[$script:activeChatId]
        if ((Get-Date) -lt $lastSync.AddMinutes(5)) {
            $lblStatus.Text = "Using local database cache."
            return
        }
    }
    
    $lblStatus.Text = "Syncing messages from cloud..."
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
        $cloudHistory = Get-ChatHistory -ChatId $script:activeChatId -Count 50 -ErrorAction Stop
        if ($cloudHistory) {
            $sortedCloud = $cloudHistory | Sort-Object timestamp
            foreach ($cMsg in $sortedCloud) {
                $dbPayload = [PSCustomObject]@{
                    idMessage   = $cMsg.idMessage
                    timestamp   = $cMsg.timestamp
                    type        = $cMsg.type
                    chatId      = $script:activeChatId
                    senderId    = $cMsg.senderId
                    senderName  = $script:activeSenderName
                    typeMessage = $cMsg.typeMessage
                    textMessage = $cMsg.textMessage
                    caption     = $cMsg.caption
                    fileName    = $cMsg.fileName
                    jpegThumbnail = $cMsg.jpegThumbnail
                }
                if ($cMsg.typeMessage -eq 'imageMessage' -and $cMsg.imageMessageData) {
                    $dbPayload.caption = $cMsg.imageMessageData.caption
                    $dbPayload.jpegThumbnail = $cMsg.imageMessageData.jpegThumbnail
                }
                elseif ($cMsg.typeMessage -eq 'videoMessage' -and $cMsg.videoMessageData) {
                    $dbPayload.caption = $cMsg.videoMessageData.caption
                }
                elseif ($cMsg.typeMessage -eq 'documentMessage' -and $cMsg.documentMessageData) {
                    $dbPayload.caption = $cMsg.documentMessageData.caption
                    $dbPayload.fileName = $cMsg.documentMessageData.fileName
                }
                Save-LocalChatMessage -ChatId $script:activeChatId -MessageObj $dbPayload
            }
            # Record successful sync time
            $script:lastSyncTimes[$script:activeChatId] = Get-Date
            $lblStatus.Text = "Sync complete."
        }
    }
    catch { 
        $lblStatus.Text = "Sync bypassed: Using localized dataset cache." 
    }
}

# Format Text helper to pad bubble content
function Get-PaddedBubbleText {
    param([string]$text)
    if ([string]::IsNullOrEmpty($text)) { return "" }
    $lines = $text -split "\r?\n"
    $padded = @()
    foreach ($line in $lines) {
        $padded += "  $line  "
    }
    return $padded -join "`r`n"
}

# --- Active Thread Conversation View Generator ---
function Update-ChatHistoryView {
    if (-not $script:activeChatId) {
        $rtbHistory.Clear()
        return
    }
    
    $rtbHistory.SuspendLayout()
    $rtbHistory.Clear()
    
    $history = Get-LocalChatHistory -ChatId $script:activeChatId -Count 50
    if ($history) {
        foreach ($msg in $history) {
            $time = [DateTimeOffset]::FromUnixTimeSeconds($msg.timestamp).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
            $displayName = if ($msg.type -eq 'outgoing') { "Me" } else { $msg.senderName }
            
            # Layout formatting based on incoming/outgoing orientation
            if ($msg.type -eq 'outgoing') {
                $rtbHistory.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Right
                $rtbHistory.SelectionIndent = 250
                $rtbHistory.SelectionRightIndent = 15
                $bubbleColor = $script:colorBubbleOut
                $headerColor = [System.Drawing.ColorTranslator]::FromHtml("#95C6A6")
                $statusGlyph = "  [Read]"
            }
            else {
                $rtbHistory.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Left
                $rtbHistory.SelectionIndent = 15
                $rtbHistory.SelectionRightIndent = 250
                $bubbleColor = $script:colorBubbleIn
                $headerColor = [System.Drawing.ColorTranslator]::FromHtml("#A6B6C6")
                $statusGlyph = ""
            }
            
            # Message Text snippet construction
            $msgText = ""
            if ($msg.textMessage) {
                $msgText = $msg.textMessage
            }
            elseif ($msg.caption) {
                $msgText = $msg.caption
            }
            elseif ($msg.fileName) {
                $msgText = $msg.fileName
            }
            else {
                $msgText = "[$($msg.typeMessage)]"
            }
            
            # Check if file has been downloaded locally
            if ($msg.typeMessage -and $msg.typeMessage -ne 'textMessage' -and $msg.typeMessage -ne 'extendedTextMessage') {
                $localFileFolder = Join-Path $downloadsParentFolder "Downloads"
                $localFilePath = Join-Path $localFileFolder $msg.fileName
                if ($msg.fileName -and (Test-Path $localFilePath)) {
                    $msgText += " `r`nOpen Attachment (file://$($localFilePath.Replace('\', '/')))"
                }
                else {
                    $msgText += " `r`nDownload Attachment (download://$($msg.idMessage))"
                }
            }
            
            # Pre-space separator line
            $rtbHistory.SelectionBackColor = $script:colorChatBg
            $rtbHistory.AppendText("`r`n")
            
            # Draw Header details
            $rtbHistory.SelectionBackColor = $bubbleColor
            $rtbHistory.SelectionColor = $headerColor
            $rtbHistory.SelectionFont = New-Object System.Drawing.Font("Segoe UI", 8, [System.Drawing.FontStyle]::Bold)
            $rtbHistory.AppendText("  $displayName  ($time)$statusGlyph  `r`n")
            
            # Draw Message bubble content
            $rtbHistory.SelectionBackColor = $bubbleColor
            $rtbHistory.SelectionColor = $script:colorTextMain
            $rtbHistory.SelectionFont = $script:fontSegoeRegular
            
            $paddedText = Get-PaddedBubbleText -text $msgText
            $rtbHistory.AppendText($paddedText + "`r`n")
        }
    }
    
    # Automatically scroll to bottom
    $rtbHistory.SelectionStart = $rtbHistory.TextLength
    $rtbHistory.SelectionLength = 0
    $rtbHistory.ScrollToCaret()
    $rtbHistory.ResumeLayout()
}

# --- Right-Click Mouse Tracking Engine for Context Menus ---
$rtbHistory.Add_MouseDown({
    param($evtSender, $e)
    if ($e.Button -eq [System.Windows.Forms.MouseButtons]::Right) {
        $charIndex = $rtbHistory.GetCharIndexFromPosition($e.Location)
        $lineIndex = $rtbHistory.GetLineFromCharIndex($charIndex)
        
        $history = Get-LocalChatHistory -ChatId $script:activeChatId -Count 50
        if ($history) {
            $lines = $rtbHistory.Lines
            $headerLineIndex = -1
            for ($i = $lineIndex; $i -ge 0; $i--) {
                if ($i -lt $lines.Length -and $lines[$i] -match '\s\(\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2}\)\s') {
                    $headerLineIndex = $i
                    break
                }
            }
            
            if ($headerLineIndex -ne -1) {
                if ($lines[$headerLineIndex] -match '\((\d{4}-\d{2}-\d{2}\s\d{2}:\d{2}:\d{2})\)') {
                    $timestampStr = $Matches[1]
                    $matchTime = [DateTime]::ParseExact($timestampStr, "yyyy-MM-dd HH:mm:ss", $null)
                    
                    foreach ($msg in $history) {
                        $msgTime = [DateTimeOffset]::FromUnixTimeSeconds($msg.timestamp).LocalDateTime
                        if ([Math]::Abs(($msgTime - $matchTime).TotalSeconds) -lt 2) {
                            $script:rightClickedMessage = $msg
                            $ctxMsgMenu.Show($rtbHistory, $e.Location)
                            break
                        }
                    }
                }
            }
        }
    }
})

# --- Message context menu Actions ---
$menuReply.Add_Click({
    if ($script:rightClickedMessage) {
        $script:quotedMessageId = $script:rightClickedMessage.idMessage
        $msgSnippet = if ($script:rightClickedMessage.textMessage) { $script:rightClickedMessage.textMessage } else { "Media attachment" }
        $lblQuoteText.Text = "Replying to: $msgSnippet"
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
                $null = Invoke-WhatsappApi -Endpoint "deleteMessage" -Body @{
                    chatId    = $script:activeChatId
                    idMessage = $script:rightClickedMessage.idMessage
                }
                
                # Remove locally from history file
                $dbPath = Join-Path $dbDir "history_$($script:activeChatId.Split('@')[0]).json"
                if (Test-Path $dbPath) {
                    $history = @(ConvertFrom-Json (Get-Content -Path $dbPath -Raw))
                    $filtered = $history | Where-Object { $_.idMessage -ne $script:rightClickedMessage.idMessage }
                    $filtered | ConvertTo-Json -Depth 5 | Set-Content -Path $dbPath -Force -Encoding UTF8
                }
                
                Update-ContactsListMenu
                Update-ChatHistoryView
                $lblStatus.Text = "Message recalled successfully."
            }
            catch {
                $lblStatus.Text = "Delete error: $_"
            }
        }
    }
})

$btnCancelQuote.Add_Click({
    $script:quotedMessageId = $null
    $pnlQuoteBar.Visible = $false
})

$menuDeleteChat.Add_Click({
    if ($script:activeChatId) {
        $confirm = [System.Windows.Forms.MessageBox]::Show("Drop all local message histories for this conversation?", "Clear local logs", [System.Windows.Forms.MessageBoxButtons]::YesNo)
        if ($confirm -eq [System.Windows.Forms.DialogResult]::Yes) {
            $dbPath = Join-Path $dbDir "history_$($script:activeChatId.Split('@')[0]).json"
            if (Test-Path $dbPath) {
                Remove-Item -Path $dbPath -Force
                $rtbHistory.Clear()
                $script:activeChatId = $null
                $script:activeSenderName = ""
                $lblActiveContact.Text = "Select a contact to start chat"
                $lblActiveStatus.Text = ""
                $pnlHeader.Invalidate()
                $pnlSplash.Visible = $true
            }
            Update-ContactsListMenu
            $lblStatus.Text = "Conversation log dropped."
        }
    }
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
                    idMessage     = $response.idMessage
                    timestamp     = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                    type          = "outgoing"
                    chatId        = $script:activeChatId
                    senderId      = $null
                    senderName    = "Me"
                    typeMessage   = $inferredType
                    textMessage   = $null
                    caption       = [System.IO.Path]::GetFileName($filePath)
                    fileName      = [System.IO.Path]::GetFileName($filePath)
                    jpegThumbnail = $null
                }
                Save-LocalChatMessage -ChatId $script:activeChatId -MessageObj $outgoingPayload
                Update-ContactsListMenu
                Update-ChatHistoryView
            }
            else {
                $lblStatus.Text = "Failed to upload file asset."
            }
        }
        catch {
            $lblStatus.Text = "Upload error: $_"
        }
    }
})

# --- Share Location Action Handler ---
$btnLocation.Add_Click({
    if (-not $script:activeChatId) { return }
    
    $prompt = New-Object System.Windows.Forms.Form
    $prompt.Size = New-Object System.Drawing.Size(300, 180)
    $prompt.Text = "Share Location Coordinates"
    $prompt.StartPosition = "CenterParent"
    $prompt.BackColor = $script:colorHeaderBg
    $prompt.ForeColor = [System.Drawing.Color]::White
    $prompt.FormBorderStyle = "FixedDialog"
    
    $lblLat = New-Object System.Windows.Forms.Label; $lblLat.Text = "Latitude:"; $lblLat.Location = New-Object System.Drawing.Point(15, 20); $lblLat.Size = New-Object System.Drawing.Size(70, 20)
    $txtLat = New-Object System.Windows.Forms.TextBox; $txtLat.Text = "-33.9249"; $txtLat.Location = New-Object System.Drawing.Point(90, 18); $txtLat.Size = New-Object System.Drawing.Size(160, 20)
    
    $lblLon = New-Object System.Windows.Forms.Label; $lblLon.Text = "Longitude:"; $lblLon.Location = New-Object System.Drawing.Point(15, 55); $lblLon.Size = New-Object System.Drawing.Size(70, 20)
    $txtLon = New-Object System.Windows.Forms.TextBox; $txtLon.Text = "18.4241"; $txtLon.Location = New-Object System.Drawing.Point(90, 53); $txtLon.Size = New-Object System.Drawing.Size(160, 20)
    
    $btnSub = New-Object System.Windows.Forms.Button; $btnSub.Text = "Share"; $btnSub.Location = New-Object System.Drawing.Point(175, 95); $btnSub.DialogResult = [System.Windows.Forms.DialogResult]::OK
    $btnSub.BackColor = $script:colorAccent
    
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
                    idMessage     = $response.idMessage
                    timestamp     = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                    type          = "outgoing"
                    chatId        = $script:activeChatId
                    senderId      = $null
                    senderName    = "Me"
                    typeMessage   = "locationMessage"
                    textMessage   = "Shared Location (Map Location: $lat, $lon)"
                    caption       = $null
                    fileName      = $null
                    jpegThumbnail = $null
                }
                Save-LocalChatMessage -ChatId $script:activeChatId -MessageObj $outgoingPayload
                Update-ContactsListMenu
                Update-ChatHistoryView
            }
        }
        catch {
            $lblStatus.Text = "Coordinate configuration numerical casting error."
        }
    }
    $prompt.Dispose()
})

# --- Double-Click & LinkClick Hyperlink Action Dispatcher ---
$rtbHistory.Add_LinkClicked({
    param($evtSender, $e)
    $url = $e.LinkText
    
    if ($url -like "file://*") {
        try {
            $filePath = $url.Substring(8).Replace('/', '\')
            $filePath = [uri]::UnescapeDataString($filePath)
            [System.Diagnostics.Process]::Start((New-Object -TypeName System.Diagnostics.ProcessStartInfo -ArgumentList $filePath -Property @{UseShellExecute = $true }))
        }
        catch {
            [System.Windows.Forms.MessageBox]::Show("Error opening file: $_", "Error")
        }
    }
    elseif ($url -like "download://*") {
        $msgId = $url.Substring(11)
        
        $lblStatus.Text = "Downloading attachment..."
        [System.Windows.Forms.Application]::DoEvents()
        
        $history = Get-LocalChatHistory -ChatId $script:activeChatId -Count 50
        $targetMsg = $history | Where-Object { $_.idMessage -eq $msgId }
        
        if ($targetMsg) {
            $fileName = $targetMsg.fileName
            if ([string]::IsNullOrEmpty($fileName)) {
                $fileName = "downloaded_file"
            }
            
            $localFileFolder = Join-Path $downloadsParentFolder "Downloads"
            if (-not (Test-Path $localFileFolder)) {
                New-Item -ItemType Directory -Path $localFileFolder -Force | Out-Null
            }
            $localFilePath = Join-Path $localFileFolder $fileName
            
            try {
                $success = Get-WhatsappFile -ChatId $script:activeChatId -MessageId $msgId -SavePath $localFilePath
                if ($success) {
                    $lblStatus.Text = "Download complete."
                    
                    $dbPath = Join-Path $dbDir "history_$($script:activeChatId.Split('@')[0]).json"
                    if (Test-Path $dbPath) {
                        $historyData = @(ConvertFrom-Json (Get-Content -Path $dbPath -Raw))
                        foreach ($m in $historyData) {
                            if ($m.idMessage -eq $msgId) {
                                $m.fileName = $fileName
                            }
                        }
                        $historyData | ConvertTo-Json -Depth 5 | Set-Content -Path $dbPath -Force -Encoding UTF8
                    }
                    
                    Update-ChatHistoryView
                    [System.Diagnostics.Process]::Start((New-Object -TypeName System.Diagnostics.ProcessStartInfo -ArgumentList $localFilePath -Property @{UseShellExecute = $true }))
                }
                else {
                    $lblStatus.Text = "Download returned unsuccessful status."
                }
            }
            catch {
                $lblStatus.Text = "Download failed: $_"
                [System.Windows.Forms.MessageBox]::Show("Failed to download file from Green API server: $_", "Download Error")
            }
        }
    }
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
                        jpegThumbnail = $null
                    }
                    
                    if ($mediaTypes -contains $messageData.messageData.typeMessage) {
                        $msgText = "[$($messageData.messageData.typeMessage)]"
                        if ($messageData.messageData.typeMessage -eq 'imageMessage') {
                            $dbPayload.caption = $messageData.messageData.imageMessageData.caption
                            $dbPayload.jpegThumbnail = $messageData.messageData.imageMessageData.jpegThumbnail
                            if ($dbPayload.caption) { $msgText += " " + $dbPayload.caption }
                        }
                        elseif ($messageData.messageData.typeMessage -eq 'videoMessage') {
                            $dbPayload.caption = $messageData.messageData.videoMessageData.caption
                            $dbPayload.jpegThumbnail = $messageData.messageData.videoMessageData.gifPlayback
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
                    
                    Save-LocalChatMessage -ChatId $incomingChatId -MessageObj $dbPayload
                    Update-ContactsListMenu
                    
                    if ($incomingChatId -eq $script:activeChatId) {
                        Update-ChatHistoryView
                        $null = Set-ChatRead -ChatId $script:activeChatId
                    }
                    else {
                        $script:unreadCounts[$incomingChatId] = ($script:unreadCounts[$incomingChatId] + 1)
                    }
                    
                    [System.Media.SystemSounds]::Asterisk.Play()
                    $lblStatus.Text = "New message from ${incomingSenderName}: $msgText"
                }
            }
        }
    }
    catch [System.Management.Automation.PipelineStoppedException] {
    }
    catch {
        $lblStatus.Text = "Polling Error: $_"
    }
    finally {
        if ($form -and $form.Visible) {
            $lblLastCheck.Text = "Last check: $((Get-Date).ToString('HH:mm:ss'))"
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
            $response = $null
            if ($script:quotedMessageId) {
                $response = Invoke-WhatsappApi -Endpoint "sendMessage" -Body @{
                    chatId          = $script:activeChatId
                    message         = $text
                    quotedMessageId = $script:quotedMessageId
                }
            }
            else {
                $response = Send-Whatsapp -ChatId $script:activeChatId -Message $text
            }
            
            if ($response -and $response.idMessage) {
                $lblStatus.Text = "Message sent successfully!"
                
                $localSaveText = $text
                if ($script:quotedMessageId) {
                    $localSaveText = "[Reply]: " + $localSaveText
                }
                
                $outgoingPayload = [PSCustomObject]@{
                    idMessage     = $response.idMessage
                    timestamp     = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                    type          = "outgoing"
                    chatId        = $script:activeChatId
                    senderId      = $null
                    senderName    = "Me"
                    typeMessage   = "textMessage"
                    textMessage   = $localSaveText
                    caption       = $null
                    fileName      = $null
                    jpegThumbnail = $null
                }
                Save-LocalChatMessage -ChatId $script:activeChatId -MessageObj $outgoingPayload
                
                $script:quotedMessageId = $null
                $pnlQuoteBar.Visible = $false
                
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
    $lblStatus.Text = "Loading contacts..."
    [System.Windows.Forms.Application]::DoEvents()
    Update-ContactsListMenu
    $timer.Start()
    $lblStatus.Text = "Online"
})

$form.Add_FormClosing({
    $timer.Stop()
})

$form.ShowDialog() | Out-Null