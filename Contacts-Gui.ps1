Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing

[System.Windows.Forms.Application]::EnableVisualStyles()

# Import the module and load configurations
$modulePath = Join-Path $PSScriptRoot "PHKustomWhatsapp.psd1"
if (-not (Test-Path $modulePath)) {
    # Fallback to current directory if script root is not set (e.g. running lines manually)
    $modulePath = ".\PHKustomWhatsapp.psd1"
}
Import-Module $modulePath -Force
Get-WhatsappConfig | Out-Null

$contactsCacheFile = Join-Path $env:APPDATA "PHWhatsapp\contacts.json"
$messagesCacheFile = Join-Path $env:APPDATA "PHWhatsapp\messages_cache.json"

# --- Design Palette Constants (Matched to Green API WhatsApp Theme) ---
$script:colorMainBg      = [System.Drawing.ColorTranslator]::FromHtml("#111B21")
$script:colorSidebarBg   = [System.Drawing.ColorTranslator]::FromHtml("#18191a")
$script:colorHeaderBg    = [System.Drawing.ColorTranslator]::FromHtml("#202C33")
$script:colorChatBg      = [System.Drawing.ColorTranslator]::FromHtml("#222e35")
$script:colorInputBg     = [System.Drawing.ColorTranslator]::FromHtml("#202C33")
$script:colorTextMain    = [System.Drawing.ColorTranslator]::FromHtml("#E9EDEF")
$script:colorTextMuted   = [System.Drawing.ColorTranslator]::FromHtml("#8696A0")
$script:colorAccent      = [System.Drawing.ColorTranslator]::FromHtml("#00c278") # Bright Green
$script:colorSelectBg    = [System.Drawing.ColorTranslator]::FromHtml("#2a3942")
$script:colorBorder      = [System.Drawing.ColorTranslator]::FromHtml("#313D45")

$script:fontSegoeRegular = New-Object System.Drawing.Font("Segoe UI", 9.5)
$script:fontSegoeBold    = New-Object System.Drawing.Font("Segoe UI", 10.5, [System.Drawing.FontStyle]::Bold)

# --- Global States ---
$script:allContacts = @()         # Full list of WhatsApp contacts
$script:contactsMapping = @{}     # DisplayName -> ChatId
$script:contactsCache = @{}       # ChatId -> Contact Details Object
$script:messagesCache = @{}       # ChatId -> List of messages

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

# --- Main Window Form Configuration ---
$form = New-Object System.Windows.Forms.Form
$form.Text = "WhatsApp Contacts Explorer"
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

# Left Column Panel (Width 20%)
$pnlLeft = $splitContainer.Panel1
$pnlLeft.BackColor = $script:colorSidebarBg

# Right Column Panel (Width 80%)
$pnlRight = $splitContainer.Panel2
$pnlRight.BackColor = $script:colorChatBg

# --- Left Column Header Panel (With Contacts Title and Refresh Button) ---
$pnlLeftHeader = New-Object System.Windows.Forms.Panel
$pnlLeftHeader.Dock = "Top"
$pnlLeftHeader.Height = 60
$pnlLeftHeader.BackColor = $script:colorSidebarBg

# Refresh Button
$btnRefresh = New-Object System.Windows.Forms.Button
$btnRefresh.Size = New-Object System.Drawing.Size(28, 28)
$btnRefresh.Text = "R"
$btnRefresh.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnRefresh.FlatAppearance.BorderSize = 1
$btnRefresh.FlatAppearance.BorderColor = $script:colorTextMuted
$btnRefresh.BackColor = [System.Drawing.Color]::Transparent
$btnRefresh.ForeColor = $script:colorTextMain
$btnRefresh.Font = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
$btnRefresh.Cursor = [System.Windows.Forms.Cursors]::Hand
$pnlLeftHeader.Controls.Add($btnRefresh)

$pnlLeftHeader.Add_Resize({
    $btnRefresh.Location = New-Object System.Drawing.Point(($pnlLeftHeader.Width - $btnRefresh.Width - 15), 16)
})

# Draw Header Title "Contacts"
$pnlLeftHeader.Add_Paint({
    param($evtSender, $e)
    $graphics = $e.Graphics
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    
    $titleFont = New-Object System.Drawing.Font("Segoe UI", 16, [System.Drawing.FontStyle]::Bold)
    $titleBrush = New-Object System.Drawing.SolidBrush($script:colorTextMain)
    $graphics.DrawString("Contacts", $titleFont, $titleBrush, 15, 14)
    
    $titleFont.Dispose()
    $titleBrush.Dispose()
})
$pnlLeft.Controls.Add($pnlLeftHeader)

# --- Left Column Search Box Panel ---
$pnlSearch = New-Object System.Windows.Forms.Panel
$pnlSearch.Dock = "Top"
$pnlSearch.Height = 50
$pnlSearch.BackColor = $script:colorSidebarBg

$txtSearch = New-Object System.Windows.Forms.TextBox
$txtSearch.Location = New-Object System.Drawing.Point(40, 10)
$txtSearch.Size = New-Object System.Drawing.Size(($pnlSearch.Width - 55), 26)
$txtSearch.BackColor = $script:colorInputBg
$txtSearch.ForeColor = $script:colorTextMain
$txtSearch.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtSearch.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$txtSearch.Text = ""

$pnlSearch.Controls.Add($txtSearch)
$pnlLeft.Controls.Add($pnlSearch)

$pnlSearch.Add_Resize({
    $txtSearch.Width = [Math]::Max(50, ($pnlSearch.Width - 55))
})

# Custom Paint to render Search Icon (Magnifying Glass)
$pnlSearch.Add_Paint({
    param($evtSender, $e)
    $graphics = $e.Graphics
    $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
    
    $pen = New-Object System.Drawing.Pen($script:colorTextMuted, 2)
    $graphics.DrawEllipse($pen, 18, 14, 8, 8)
    $graphics.DrawLine($pen, 24, 20, 28, 24)
    $pen.Dispose()
})

# --- Left Column Contacts ListBox (Owner-Drawn) ---
$lstContacts = New-Object System.Windows.Forms.ListBox
$lstContacts.Dock = "Fill"
$lstContacts.BackColor = $script:colorSidebarBg
$lstContacts.ForeColor = $script:colorTextMain
$lstContacts.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$lstContacts.Font = New-Object System.Drawing.Font("Segoe UI", 10.5)
$lstContacts.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$lstContacts.ItemHeight = 65
$pnlLeft.Controls.Add($lstContacts)

# --- Right Column splash Screen panel (GREEN-API Branded style) ---
$pnlSplash = New-Object System.Windows.Forms.Panel
$pnlSplash.Dock = "Fill"
$pnlSplash.BackColor = $script:colorChatBg
$pnlSplash.Visible = $true

$pnlSplashContent = New-Object System.Windows.Forms.Panel
$pnlSplashContent.Size = New-Object System.Drawing.Size(600, 300)
$pnlSplashContent.Location = New-Object System.Drawing.Point(100, 150)
$pnlSplashContent.BackColor = [System.Drawing.Color]::Transparent

$lblSplashFootnote = New-Object System.Windows.Forms.Label
$lblSplashFootnote.Text = "Select a contact from the list to view details"
$lblSplashFootnote.Font = New-Object System.Drawing.Font("Segoe UI", 15)
$lblSplashFootnote.ForeColor = $script:colorTextMuted
$lblSplashFootnote.Size = New-Object System.Drawing.Size(600, 45)
$lblSplashFootnote.TextAlign = [System.Drawing.ContentAlignment]::MiddleCenter
$lblSplashFootnote.Location = New-Object System.Drawing.Point(0, 180)

$pnlSplashContent.Controls.Add($lblSplashFootnote)
$pnlSplash.Controls.Add($pnlSplashContent)
$pnlRight.Controls.Add($pnlSplash)
$pnlSplash.BringToFront()

# Align splash panel content dynamically
$pnlSplash.Add_Resize({
    $pnlSplashContent.Location = New-Object System.Drawing.Point(
        [Math]::Max(0, ($pnlSplash.Width - $pnlSplashContent.Width) / 2),
        [Math]::Max(0, ($pnlSplash.Height - $pnlSplashContent.Height) / 2)
    )
})

# Custom Paint to draw GREEN-API Logo precisely
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
    
    # Bottom Left Corner Pointer
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

# --- Right Column Active Details Panel ---
$pnlDetails = New-Object System.Windows.Forms.Panel
$pnlDetails.Dock = "Fill"
$pnlDetails.BackColor = $script:colorChatBg
$pnlDetails.Visible = $false
$pnlRight.Controls.Add($pnlDetails)

# Details Header Panel
$pnlHeader = New-Object System.Windows.Forms.Panel
$pnlHeader.Dock = "Top"
$pnlHeader.Height = 80
$pnlHeader.BackColor = $script:colorHeaderBg
$pnlDetails.Controls.Add($pnlHeader)

$lblActiveContact = New-Object System.Windows.Forms.Label
$lblActiveContact.Location = New-Object System.Drawing.Point(85, 20)
$lblActiveContact.Size = New-Object System.Drawing.Size(600, 24)
$lblActiveContact.Font = New-Object System.Drawing.Font("Segoe UI", 14, [System.Drawing.FontStyle]::Bold)
$lblActiveContact.ForeColor = $script:colorTextMain
$lblActiveContact.Text = ""

$lblActiveStatus = New-Object System.Windows.Forms.Label
$lblActiveStatus.Location = New-Object System.Drawing.Point(85, 46)
$lblActiveStatus.Size = New-Object System.Drawing.Size(600, 18)
$lblActiveStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9.5)
$lblActiveStatus.ForeColor = $script:colorTextMuted
$lblActiveStatus.Text = ""

$pnlHeader.Controls.AddRange(@($lblActiveContact, $lblActiveStatus))

# Header Avatar Custom Painting
$script:selectedContactName = ""
$pnlHeader.Add_Paint({
    param($evtSender, $e)
    if ($script:selectedContactName) {
        $graphics = $e.Graphics
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        
        $avatarRect = [System.Drawing.Rectangle]::new(20, 15, 50, 50)
        $avatarColor = Get-AvatarColor -Name $script:selectedContactName
        $avatarBrush = New-Object System.Drawing.SolidBrush($avatarColor)
        $graphics.FillEllipse($avatarBrush, $avatarRect)
        
        $initials = Get-Initials -Name $script:selectedContactName
        $avatarFont = New-Object System.Drawing.Font("Segoe UI", 12, [System.Drawing.FontStyle]::Bold)
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

# Details Content Card Panel (Container)
$pnlContent = New-Object System.Windows.Forms.Panel
$pnlContent.Dock = "Fill"
$pnlDetails.Controls.Add($pnlContent)
$pnlContent.BringToFront()

# Left Column Panel for Info and Actions
$pnlDetailsLeft = New-Object System.Windows.Forms.Panel
$pnlDetailsLeft.Dock = "Left"
$pnlDetailsLeft.Width = 395
$pnlDetailsLeft.Padding = New-Object System.Windows.Forms.Padding(20, 20, 10, 20)
$pnlContent.Controls.Add($pnlDetailsLeft)

# Right Column Panel for Message History
$pnlDetailsRight = New-Object System.Windows.Forms.Panel
$pnlDetailsRight.Dock = "Fill"
$pnlDetailsRight.Padding = New-Object System.Windows.Forms.Padding(10, 20, 20, 20)
$pnlContent.Controls.Add($pnlDetailsRight)

# GroupBox for Info Details
$grpInfo = New-Object System.Windows.Forms.GroupBox
$grpInfo.Text = "Contact Information"
$grpInfo.ForeColor = $script:colorAccent
$grpInfo.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$grpInfo.Size = New-Object System.Drawing.Size(365, 180)
$grpInfo.Location = New-Object System.Drawing.Point(20, 20)
$grpInfo.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$pnlDetailsLeft.Controls.Add($grpInfo)

# Labels inside Info GroupBox
$lblInfoFont = New-Object System.Drawing.Font("Segoe UI", 10)
$lblInfoValFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Bold)

$lblPropName = New-Object System.Windows.Forms.Label
$lblPropName.Text = "Display Name:"
$lblPropName.Location = New-Object System.Drawing.Point(15, 35)
$lblPropName.Size = New-Object System.Drawing.Size(110, 20)
$lblPropName.ForeColor = $script:colorTextMuted
$lblPropName.Font = $lblInfoFont

$valPropName = New-Object System.Windows.Forms.Label
$valPropName.Location = New-Object System.Drawing.Point(130, 35)
$valPropName.Size = New-Object System.Drawing.Size(220, 20)
$valPropName.ForeColor = $script:colorTextMain
$valPropName.Font = $lblInfoValFont

$lblPropId = New-Object System.Windows.Forms.Label
$lblPropId.Text = "WhatsApp ID:"
$lblPropId.Location = New-Object System.Drawing.Point(15, 70)
$lblPropId.Size = New-Object System.Drawing.Size(110, 20)
$lblPropId.ForeColor = $script:colorTextMuted
$lblPropId.Font = $lblInfoFont

$valPropId = New-Object System.Windows.Forms.Label
$valPropId.Location = New-Object System.Drawing.Point(130, 70)
$valPropId.Size = New-Object System.Drawing.Size(220, 20)
$valPropId.ForeColor = $script:colorTextMain
$valPropId.Font = $lblInfoValFont

$lblPropPhone = New-Object System.Windows.Forms.Label
$lblPropPhone.Text = "Phone Number:"
$lblPropPhone.Location = New-Object System.Drawing.Point(15, 105)
$lblPropPhone.Size = New-Object System.Drawing.Size(110, 20)
$lblPropPhone.ForeColor = $script:colorTextMuted
$lblPropPhone.Font = $lblInfoFont

$valPropPhone = New-Object System.Windows.Forms.Label
$valPropPhone.Location = New-Object System.Drawing.Point(130, 105)
$valPropPhone.Size = New-Object System.Drawing.Size(220, 20)
$valPropPhone.ForeColor = $script:colorTextMain
$valPropPhone.Font = $lblInfoValFont

$lblPropType = New-Object System.Windows.Forms.Label
$lblPropType.Text = "Chat Type:"
$lblPropType.Location = New-Object System.Drawing.Point(15, 140)
$lblPropType.Size = New-Object System.Drawing.Size(110, 20)
$lblPropType.ForeColor = $script:colorTextMuted
$lblPropType.Font = $lblInfoFont

$valPropType = New-Object System.Windows.Forms.Label
$valPropType.Location = New-Object System.Drawing.Point(130, 140)
$valPropType.Size = New-Object System.Drawing.Size(220, 20)
$valPropType.ForeColor = $script:colorTextMain
$valPropType.Font = $lblInfoValFont

$grpInfo.Controls.AddRange(@(
    $lblPropName, $valPropName,
    $lblPropId, $valPropId,
    $lblPropPhone, $valPropPhone,
    $lblPropType, $valPropType
))

# GroupBox for Actions (Send Message & Check Availability)
$grpActions = New-Object System.Windows.Forms.GroupBox
$grpActions.Text = "Quick Actions"
$grpActions.ForeColor = $script:colorAccent
$grpActions.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$grpActions.Size = New-Object System.Drawing.Size(365, 280)
$grpActions.Location = New-Object System.Drawing.Point(20, 220)
$grpActions.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$pnlDetailsLeft.Controls.Add($grpActions)

# Check Availability Button
$btnCheck = New-Object System.Windows.Forms.Button
$btnCheck.Text = "Check WhatsApp Registration Status"
$btnCheck.Location = New-Object System.Drawing.Point(15, 35)
$btnCheck.Size = New-Object System.Drawing.Size(330, 35)
$btnCheck.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnCheck.FlatAppearance.BorderColor = $script:colorAccent
$btnCheck.FlatAppearance.BorderSize = 1
$btnCheck.ForeColor = $script:colorTextMain
$btnCheck.BackColor = $script:colorSelectBg
$btnCheck.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnCheck.Cursor = [System.Windows.Forms.Cursors]::Hand
$grpActions.Controls.Add($btnCheck)

# Quick Message Text Label
$lblQuickMsg = New-Object System.Windows.Forms.Label
$lblQuickMsg.Text = "Send Quick Text Message:"
$lblQuickMsg.Location = New-Object System.Drawing.Point(15, 85)
$lblQuickMsg.Size = New-Object System.Drawing.Size(200, 20)
$lblQuickMsg.ForeColor = $script:colorTextMuted
$lblQuickMsg.Font = $lblInfoFont
$grpActions.Controls.Add($lblQuickMsg)

# Textbox for message input
$txtQuickMsg = New-Object System.Windows.Forms.TextBox
$txtQuickMsg.Location = New-Object System.Drawing.Point(15, 110)
$txtQuickMsg.Size = New-Object System.Drawing.Size(330, 60)
$txtQuickMsg.Multiline = $true
$txtQuickMsg.BackColor = $script:colorInputBg
$txtQuickMsg.ForeColor = $script:colorTextMain
$txtQuickMsg.BorderStyle = [System.Windows.Forms.BorderStyle]::FixedSingle
$txtQuickMsg.Font = New-Object System.Drawing.Font("Segoe UI", 10)
$grpActions.Controls.Add($txtQuickMsg)

# Send Button
$btnSend = New-Object System.Windows.Forms.Button
$btnSend.Text = "Send Message"
$btnSend.Location = New-Object System.Drawing.Point(225, 180)
$btnSend.Size = New-Object System.Drawing.Size(120, 35)
$btnSend.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$btnSend.FlatAppearance.BorderSize = 0
$btnSend.BackColor = $script:colorAccent
$btnSend.ForeColor = [System.Drawing.Color]::White
$btnSend.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Bold)
$btnSend.Cursor = [System.Windows.Forms.Cursors]::Hand
$grpActions.Controls.Add($btnSend)

# Action status label
$lblActionStatus = New-Object System.Windows.Forms.Label
$lblActionStatus.Location = New-Object System.Drawing.Point(15, 230)
$lblActionStatus.Size = New-Object System.Drawing.Size(330, 35)
$lblActionStatus.Font = New-Object System.Drawing.Font("Segoe UI", 9.5, [System.Drawing.FontStyle]::Italic)
$lblActionStatus.ForeColor = $script:colorTextMuted
$lblActionStatus.Text = ""
$grpActions.Controls.Add($lblActionStatus)

# GroupBox for Message History
$grpHistory = New-Object System.Windows.Forms.GroupBox
$grpHistory.Text = "Last 50 Messages"
$grpHistory.ForeColor = $script:colorAccent
$grpHistory.Font = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
$grpHistory.Dock = "Fill"
$grpHistory.FlatStyle = [System.Windows.Forms.FlatStyle]::Flat
$pnlDetailsRight.Controls.Add($grpHistory)

# Message History RichTextBox
$rtbHistory = New-Object System.Windows.Forms.RichTextBox
$rtbHistory.Dock = "Fill"
$rtbHistory.BackColor = $script:colorMainBg
$rtbHistory.ForeColor = $script:colorTextMain
$rtbHistory.BorderStyle = [System.Windows.Forms.BorderStyle]::None
$rtbHistory.ReadOnly = $true
$rtbHistory.Font = $script:fontSegoeRegular
$grpHistory.Controls.Add($rtbHistory)

# Bottom Status Strip
$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusStrip.BackColor = $script:colorHeaderBg
$lblStatus = New-Object System.Windows.Forms.ToolStripStatusLabel
$lblStatus.ForeColor = $script:colorTextMuted
$lblStatus.Text = "Loading application..."
$statusStrip.Items.Add($lblStatus)
$form.Controls.Add($statusStrip)

# --- Functions ---

# Load Contacts List
function Import-AllContacts {
    $lblStatus.Text = "Fetching contacts list..."
    [System.Windows.Forms.Application]::DoEvents()
    
    # 1. Try local cache first
    if (Test-Path $contactsCacheFile) {
        try {
            $raw = Get-Content -Path $contactsCacheFile -Raw -ErrorAction SilentlyContinue
            if ($raw) {
                $script:allContacts = @(ConvertFrom-Json $raw)
            }
        }
        catch {}
    }
    
    # 2. Call API if cache empty
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
                # Save to cache
                $script:allContacts | ConvertTo-Json -Depth 5 | Set-Content -Path $contactsCacheFile -Force -Encoding UTF8
            }
        }
        catch {
            $lblStatus.Text = "API Error: Could not fetch contacts list."
            Write-Warning "Could not fetch contacts list: $_"
        }
    }
    
    # 3. Retrieve last 50 messages for each contact
    $script:messagesCache = @{}
    $loadedHistory = $false
    if (Test-Path $messagesCacheFile) {
        try {
            $rawMsg = Get-Content -Path $messagesCacheFile -Raw -ErrorAction SilentlyContinue
            if ($rawMsg) {
                $parsed = ConvertFrom-Json $rawMsg
                if ($parsed) {
                    foreach ($prop in $parsed.PSObject.Properties) {
                        $script:messagesCache[$prop.Name] = @($prop.Value)
                    }
                    $loadedHistory = $true
                }
            }
        }
        catch {}
    }
    
    if (-not $loadedHistory -and $script:allContacts.Count -gt 0) {
        $total = $script:allContacts.Count
        $index = 0
        foreach ($contact in $script:allContacts) {
            $index++
            $lblStatus.Text = "Retrieving last 50 messages ($index/$total) for $($contact.name)..."
            [System.Windows.Forms.Application]::DoEvents()
            
            try {
                $history = Get-ChatHistory -ChatId $contact.id -Count 50 -ErrorAction SilentlyContinue
                if ($history) {
                    $script:messagesCache[$contact.id] = @($history)
                } else {
                    $script:messagesCache[$contact.id] = @()
                }
            }
            catch {
                $script:messagesCache[$contact.id] = @()
            }
        }
        # Save messages cache to local file
        try {
            $script:messagesCache | ConvertTo-Json -Depth 5 | Set-Content -Path $messagesCacheFile -Force -Encoding UTF8
        } catch {}
        
        $lblStatus.Text = "Loaded $total contacts and retrieved their last 50 messages."
    } elseif ($script:allContacts.Count -gt 0) {
        $lblStatus.Text = "Loaded $($script:allContacts.Count) contacts with cached message history."
    } else {
        $lblStatus.Text = "No contacts found."
    }
}

# Update contacts view list
# Render last 50 messages for the selected contact
function Update-ChatHistoryView {
    param([string]$chatId)
    $rtbHistory.Clear()
    
    $messages = $script:messagesCache[$chatId]
    if (-not $messages -or $messages.Count -eq 0) {
        $rtbHistory.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Center
        $rtbHistory.SelectionColor = $script:colorTextMuted
        $rtbHistory.SelectionFont = New-Object System.Drawing.Font("Segoe UI", 10, [System.Drawing.FontStyle]::Italic)
        $rtbHistory.AppendText("`r`n`r`nNo message history available for this contact.")
        return
    }
    
    $rtbHistory.SuspendLayout()
    foreach ($msg in $messages) {
        # Format timestamp
        $timeStr = ""
        if ($msg.timestamp) {
            $timeStr = [DateTimeOffset]::FromUnixTimeSeconds($msg.timestamp).LocalDateTime.ToString("yyyy-MM-dd HH:mm:ss")
        }
        
        # Format sender name
        $msgSender = "Me"
        if ($msg.type -eq 'incoming' -or $msg.fromMe -eq $false) {
            $msgSender = $script:selectedContactName
        }
        
        # Color & Alignment
        if ($msg.type -eq 'outgoing' -or $msg.fromMe -eq $true) {
            $rtbHistory.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Right
            $rtbHistory.SelectionIndent = 100
            $rtbHistory.SelectionRightIndent = 15
            $bubbleColor = $script:colorSelectBg
            $senderColor = [System.Drawing.ColorTranslator]::FromHtml("#95C6A6")
        } else {
            $rtbHistory.SelectionAlignment = [System.Windows.Forms.HorizontalAlignment]::Left
            $rtbHistory.SelectionIndent = 15
            $rtbHistory.SelectionRightIndent = 100
            $bubbleColor = $script:colorHeaderBg
            $senderColor = [System.Drawing.ColorTranslator]::FromHtml("#A6B6C6")
        }
        
        # Append sender and time
        $rtbHistory.SelectionBackColor = $bubbleColor
        $rtbHistory.SelectionColor = $senderColor
        $rtbHistory.SelectionFont = New-Object System.Drawing.Font("Segoe UI", 8.5, [System.Drawing.FontStyle]::Bold)
        $rtbHistory.AppendText("  $msgSender  ($timeStr)  `r`n")
        
        # Message text
        $msgText = ""
        if ($msg.textMessage) {
            $msgText = $msg.textMessage
        } elseif ($msg.body) {
            $msgText = $msg.body
        } elseif ($msg.caption) {
            $msgText = $msg.caption
        } else {
            $msgText = "[$($msg.typeMessage)]"
        }
        
        $rtbHistory.SelectionBackColor = $bubbleColor
        $rtbHistory.SelectionColor = $script:colorTextMain
        $rtbHistory.SelectionFont = $script:fontSegoeRegular
        
        # Padding lines
        $rtbHistory.AppendText("  $msgText  `r`n`r`n")
        
        # Reset colors for separator space
        $rtbHistory.SelectionBackColor = $script:colorMainBg
        $rtbHistory.AppendText("`r`n")
    }
    $rtbHistory.SelectionStart = $rtbHistory.TextLength
    $rtbHistory.ScrollToCaret()
    $rtbHistory.ResumeLayout()
}

function Update-ContactsListMenu {
    $currentSelection = $lstContacts.SelectedItem
    $lstContacts.Items.Clear()
    $script:contactsMapping.Clear()
    $script:contactsCache.Clear()
    
    $searchText = $txtSearch.Text.Trim()
    $filtered = $script:allContacts
    
    if ($searchText) {
        $filtered = $script:allContacts | Where-Object {
            $_.name -like "*$searchText*" -or $_.id -like "*$searchText*"
        }
    }
    
    # Sort alphabetically by name
    $sorted = $filtered | Sort-Object name
    
    foreach ($contact in $sorted) {
        $lstContacts.Items.Add($contact.name) | Out-Null
        $script:contactsMapping[$contact.name] = $contact.id
        $script:contactsCache[$contact.id] = $contact
    }
    
    # Restore selection if possible
    if ($currentSelection -and $lstContacts.Items.Contains($currentSelection)) {
        $lstContacts.SelectedItem = $currentSelection
    }
}

# Drawing Event for ListBox (Premium visual styling)
$lstContacts.Add_DrawItem({
    param($evtSender, $e)
    if ($e.Index -lt 0 -or $e.Index -ge $evtSender.Items.Count) { return }
    $graphics = $e.Graphics
    $itemText = $evtSender.Items[$e.Index]
    
    $isSelected = ($e.State -band [System.Windows.Forms.DrawItemState]::Selected) -eq [System.Windows.Forms.DrawItemState]::Selected
    
    # Background Selection
    $backColor = if ($isSelected) { $script:colorSelectBg } else { $script:colorSidebarBg }
    $backBrush = New-Object System.Drawing.SolidBrush($backColor)
    $graphics.FillRectangle($backBrush, $e.Bounds)
    
    $mappedId = $script:contactsMapping[$itemText]
    $contact = $script:contactsCache[$mappedId]
    
    if ($contact) {
        $bounds = $e.Bounds
        
        # Circle Avatar Rect
        $avatarRect = [System.Drawing.Rectangle]::new(($bounds.X + 12), ($bounds.Y + 10), 45, 45)
        
        $avatarColor = Get-AvatarColor -Name $contact.name
        $avatarBrush = New-Object System.Drawing.SolidBrush($avatarColor)
        $graphics.SmoothingMode = [System.Drawing.Drawing2D.SmoothingMode]::AntiAlias
        $graphics.FillEllipse($avatarBrush, $avatarRect)
        
        # Initials Text inside Avatar
        $initials = Get-Initials -Name $contact.name
        $avatarFont = New-Object System.Drawing.Font("Segoe UI", 11, [System.Drawing.FontStyle]::Bold)
        $initialSize = $graphics.MeasureString($initials, $avatarFont)
        $textBrush = New-Object System.Drawing.SolidBrush([System.Drawing.Color]::White)
        $graphics.DrawString(
            $initials,
            $avatarFont,
            $textBrush,
            $avatarRect.X + ($avatarRect.Width - $initialSize.Width) / 2,
            $avatarRect.Y + ($avatarRect.Height - $initialSize.Height) / 2
        )
        
        # Contact Name Text
        $nameFont = $script:fontSegoeBold
        $nameBrush = New-Object System.Drawing.SolidBrush($script:colorTextMain)
        $graphics.DrawString($contact.name, $nameFont, $nameBrush, ($bounds.X + 70), ($bounds.Y + 14))
        
        # Details type Text
        $typeFont = New-Object System.Drawing.Font("Segoe UI", 9)
        $typeBrush = New-Object System.Drawing.SolidBrush($script:colorTextMuted)
        
        $typeLabel = $contact.type
        if ($contact.id -match 'g\.us') { $typeLabel = "group" }
        $graphics.DrawString($typeLabel, $typeFont, $typeBrush, ($bounds.X + 70), ($bounds.Y + 36))
        
        # Bottom item line separator
        $borderPen = New-Object System.Drawing.Pen($script:colorBorder, 1)
        $graphics.DrawLine($borderPen, ($bounds.X + 70), ($bounds.Bottom - 1), $bounds.Right, ($bounds.Bottom - 1))
        
        # Cleanup
        $avatarBrush.Dispose()
        $avatarFont.Dispose()
        $textBrush.Dispose()
        $nameBrush.Dispose()
        $typeFont.Dispose()
        $typeBrush.Dispose()
        $borderPen.Dispose()
    }
    
    $backBrush.Dispose()
})

# Contact Selection Change Event
$lstContacts.Add_SelectedIndexChanged({
    $selectedName = $lstContacts.SelectedItem
    if ($selectedName) {
        $chatId = $script:contactsMapping[$selectedName]
        $contact = $script:contactsCache[$chatId]
        
        if ($contact) {
            $script:selectedContactName = $contact.name
            
            # Show details panel and hide splash panel
            $pnlSplash.Visible = $false
            $pnlDetails.Visible = $true
            
            # Resolve actual phone number (especially if it is a WhatsApp Lite @lid ID)
            $phone = $null
            if ($contact.phoneNumber) {
                $phone = $contact.phoneNumber
            } elseif ($contact.id -match '@lid$') {
                $lblStatus.Text = "Resolving real phone number..."
                [System.Windows.Forms.Application]::DoEvents()
                try {
                    $info = Get-WhatsappContactInfo -ChatId $contact.id -ErrorAction SilentlyContinue
                    if ($info -and $info.number) {
                        $phone = $info.number
                        $contact | Add-Member -MemberType NoteProperty -Name "phoneNumber" -Value $phone -Force
                        # Save updated contacts cache file
                        try {
                            $script:allContacts | ConvertTo-Json -Depth 5 | Set-Content -Path $contactsCacheFile -Force -Encoding UTF8
                        } catch {}
                    }
                } catch {}
            }
            if (-not $phone) {
                $phone = $contact.id.Split('@')[0]
                $contact | Add-Member -MemberType NoteProperty -Name "phoneNumber" -Value $phone -Force
            }

            # Update Header labels
            $lblActiveContact.Text = $contact.name
            $lblActiveStatus.Text = "+$phone"
            $pnlHeader.Invalidate() # force redraw of avatar
            
            # Update Info Card labels
            $valPropName.Text = $contact.name
            $valPropId.Text = $contact.id
            
            # Parse phone number from ID
            $valPropPhone.Text = "+$phone"
            
            $isGroup = $contact.id -match 'g\.us'
            $valPropType.Text = if ($isGroup) { "Group Chat" } else { "Individual Chat ($($contact.type))" }
            
            # Enable/Disable availability checker button based on chat type
            if ($isGroup) {
                $btnCheck.Enabled = $false
                $btnCheck.Text = "Registration Check Not Applicable to Groups"
            } else {
                $btnCheck.Enabled = $true
                $btnCheck.Text = "Check WhatsApp Registration Status"
            }
            
            # Reset Quick Actions State
            $txtQuickMsg.Clear()
            $lblActionStatus.Text = ""
            $lblStatus.Text = "Viewing contact: $($contact.name)"
            
            # Render message history
            Update-ChatHistoryView -chatId $chatId
        }
    } else {
        $script:selectedContactName = ""
        $pnlDetails.Visible = $false
        $pnlSplash.Visible = $true
    }
})

# Refresh Button click event
$btnRefresh.Add_Click({
    # Clear local cache to force API load
    if (Test-Path $contactsCacheFile) {
        Remove-Item $contactsCacheFile -Force | Out-Null
    }
    if (Test-Path $messagesCacheFile) {
        Remove-Item $messagesCacheFile -Force | Out-Null
    }
    $script:allContacts = @()
    $script:messagesCache = @{}
    Import-AllContacts
    Update-ContactsListMenu
})

# Filter search input box text changed
$txtSearch.Add_TextChanged({
    Update-ContactsListMenu
})

# Check WhatsApp Availability Action
$btnCheck.Add_Click({
    $selectedName = $lstContacts.SelectedItem
    if (-not $selectedName) { return }
    $chatId = $script:contactsMapping[$selectedName]
    $contact = $script:contactsCache[$chatId]
    $phone = if ($contact -and $contact.phoneNumber) { $contact.phoneNumber } else { $chatId.Split('@')[0] }
    
    $lblActionStatus.ForeColor = $script:colorTextMuted
    $lblActionStatus.Text = "Checking WhatsApp availability for $phone..."
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
        $result = Test-WhatsappAvailability -Number $phone -ErrorAction Stop
        if ($result -and $result.exists -eq $true) {
            $lblActionStatus.ForeColor = $script:colorAccent
            $lblActionStatus.Text = "[Available] Phone number $phone is registered on WhatsApp."
        } else {
            $lblActionStatus.ForeColor = [System.Drawing.Color]::OrangeRed
            $lblActionStatus.Text = "[Not Registered] Phone number $phone is NOT registered on WhatsApp."
        }
    }
    catch {
        $lblActionStatus.ForeColor = [System.Drawing.Color]::OrangeRed
        $lblActionStatus.Text = "Error during check: $_"
    }
})

# Send Message Action
$btnSend.Add_Click({
    $selectedName = $lstContacts.SelectedItem
    if (-not $selectedName) { return }
    $chatId = $script:contactsMapping[$selectedName]
    $msgText = $txtQuickMsg.Text.Trim()
    
    if (-not $msgText) {
        [System.Windows.Forms.MessageBox]::Show("Please enter a message to send.", "Warning")
        return
    }
    
    $lblActionStatus.ForeColor = $script:colorTextMuted
    $lblActionStatus.Text = "Sending message to $selectedName..."
    [System.Windows.Forms.Application]::DoEvents()
    
    try {
        $response = Send-Whatsapp -Number $chatId -Message $msgText -ErrorAction Stop
        if ($response -and $response.idMessage) {
            $lblActionStatus.ForeColor = $script:colorAccent
            $lblActionStatus.Text = "[Sent] Message sent successfully!"
            $txtQuickMsg.Clear()
            
            # Optimistically append to local message cache
            $newMsgObj = [PSCustomObject]@{
                idMessage   = $response.idMessage
                timestamp   = [DateTimeOffset]::UtcNow.ToUnixTimeSeconds()
                type        = "outgoing"
                fromMe      = $true
                textMessage = $msgText
                typeMessage = "textMessage"
            }
            if (-not $script:messagesCache.ContainsKey($chatId)) {
                $script:messagesCache[$chatId] = @()
            }
            $script:messagesCache[$chatId] = @($script:messagesCache[$chatId]) + $newMsgObj
            
            # Write to cache file
            try {
                $script:messagesCache | ConvertTo-Json -Depth 5 | Set-Content -Path $messagesCacheFile -Force -Encoding UTF8
            } catch {}
            
            # Re-render history view
            Update-ChatHistoryView -chatId $chatId
        } else {
            $lblActionStatus.ForeColor = [System.Drawing.Color]::OrangeRed
            $lblActionStatus.Text = "Failed to send message: API did not return a Message ID."
        }
    }
    catch {
        $lblActionStatus.ForeColor = [System.Drawing.Color]::OrangeRed
        $lblActionStatus.Text = "Error sending message: $_"
    }
})

# Form Shown initial load event
$form.Add_Shown({
    Import-AllContacts
    Update-ContactsListMenu
})

# Run the Form
[System.Windows.Forms.Application]::Run($form)
