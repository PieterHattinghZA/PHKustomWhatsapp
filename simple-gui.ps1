<#
.SYNOPSIS
    Two-column Green API chat client for Windows PowerShell 5.1.

.DESCRIPTION
    Retrieves active chats first, resolves their contact names, and displays the
    selected chat in the right-hand pane. Images are rendered in the conversation.
    Videos show their thumbnail and can be downloaded and opened in the default
    Windows video player. Local image and video uploads are supported.

.NOTES
    Author  : Pieter Hattingh
    Date    : 20/07/2026
    Version : 4.0.0
    Requires: Windows PowerShell 5.1 and PHKustomWhatsapp.psd1
#>

[CmdletBinding()]
param(
    [ValidateRange(10, 500)]
    [int]$ChatCount = 100,

    [ValidateRange(10, 200)]
    [int]$MessageCount = 50,

    [ValidateRange(0, 3650)]
    [int]$MediaRetentionDays = 30
)

$ErrorActionPreference = 'Stop'

$script:ChatCount = $ChatCount
$script:MessageCount = $MessageCount
$script:MediaRetentionDays = $MediaRetentionDays

Add-Type -AssemblyName System.Windows.Forms
Add-Type -AssemblyName System.Drawing
[System.Windows.Forms.Application]::EnableVisualStyles()

$modulePath = Join-Path $PSScriptRoot 'PHKustomWhatsapp.psd1'
if (-not (Test-Path -LiteralPath $modulePath -PathType Leaf)) {
    throw "Module manifest was not found: $modulePath"
}

Import-Module $modulePath -Force
if (-not (Get-WhatsappConfig)) {
    throw 'Green API configuration could not be loaded. Run New-WhatsappConfigFile first.'
}

$script:ActiveChatId = $null
$script:ActiveChatName = $null
$script:ChatItems = @()
$script:ContactLookup = @{}
$script:ImageObjects = New-Object System.Collections.ArrayList
$script:AvatarLookup = @{}
$script:AvatarQueue = New-Object System.Collections.Queue
$script:LastChatRefresh = [datetime]::MinValue
$script:IsBusy = $false

$script:DataDirectory = Join-Path $env:APPDATA 'PHWhatsapp'
$script:MediaDirectory = Join-Path $script:DataDirectory 'MediaCache'
$script:LogDirectory = Join-Path $script:DataDirectory 'Logs'
$script:AvatarDirectory = Join-Path $script:DataDirectory 'AvatarCache'
$script:AssetDirectory = Join-Path $PSScriptRoot 'assets'
$script:BrandIconPath = Join-Path $script:AssetDirectory 'BlikbreinPyn-icon.png'
$script:BrandFullPath = Join-Path $script:AssetDirectory 'BlikbreinPyn-brand.png'
$script:WindowIconPath = Join-Path $script:AssetDirectory 'BlikbreinPyn.ico'

foreach ($directory in @($script:DataDirectory, $script:MediaDirectory, $script:LogDirectory, $script:AvatarDirectory)) {
    if (-not (Test-Path -LiteralPath $directory)) {
        New-Item -Path $directory -ItemType Directory -Force | Out-Null
    }
}

$script:LogFile = Join-Path $script:LogDirectory ('simple-gui_{0}.log' -f (Get-Date -Format 'yyyy-MM-dd'))

function Write-GuiLog {
    [CmdletBinding()]
    param(
        [Parameter(Mandatory = $true)]
        [string]$Message,

        [ValidateSet('INFO', 'WARN', 'ERROR')]
        [string]$Level = 'INFO'
    )

    $line = '{0} [{1}] {2}' -f (Get-Date -Format 'yyyy-MM-dd HH:mm:ss'), $Level, $Message
    Add-Content -LiteralPath $script:LogFile -Value $line -Encoding UTF8
}

function Get-SafeFileName {
    param(
        [string]$Value,
        [string]$Fallback = 'media.bin'
    )

    if ([string]::IsNullOrWhiteSpace($Value)) {
        return $Fallback
    }

    $result = $Value
    foreach ($character in [System.IO.Path]::GetInvalidFileNameChars()) {
        $result = $result.Replace([string]$character, '_')
    }

    if ([string]::IsNullOrWhiteSpace($result)) {
        return $Fallback
    }

    return $result
}

function Get-MessageTimeText {
    param([object]$Timestamp)

    try {
        $seconds = [int64]$Timestamp
        $epoch = [DateTime]::SpecifyKind([DateTime]::ParseExact('1970-01-01', 'yyyy-MM-dd', [Globalization.CultureInfo]::InvariantCulture), [DateTimeKind]::Utc)
        return $epoch.AddSeconds($seconds).ToLocalTime().ToString('dd/MM/yyyy HH:mm')
    }
    catch {
        return ''
    }
}

function Get-MediaExtension {
    param(
        [object]$Message,
        [string]$DefaultExtension
    )

    if ($Message.fileName) {
        $extension = [System.IO.Path]::GetExtension([string]$Message.fileName)
        if ($extension) { return $extension }
    }

    switch -Regex ([string]$Message.mimeType) {
        '^image/jpeg' { return '.jpg' }
        '^image/png' { return '.png' }
        '^image/gif' { return '.gif' }
        '^image/webp' { return '.webp' }
        '^video/mp4' { return '.mp4' }
        '^video/quicktime' { return '.mov' }
        '^video/x-msvideo' { return '.avi' }
        '^video/x-matroska' { return '.mkv' }
        '^video/webm' { return '.webm' }
        '^video/3gpp' { return '.3gp' }
        '^video/3gpp2' { return '.3g2' }
        '^video/' { return $DefaultExtension }
        default { return $DefaultExtension }
    }
}

function Get-MediaCachePath {
    param(
        [Parameter(Mandatory = $true)]
        [object]$Message,

        [Parameter(Mandatory = $true)]
        [string]$DefaultExtension
    )

    $messageId = Get-SafeFileName -Value ([string]$Message.idMessage) -Fallback ([guid]::NewGuid().ToString('N'))
    $extension = Get-MediaExtension -Message $Message -DefaultExtension $DefaultExtension
    return Join-Path $script:MediaDirectory ($messageId + $extension)
}

function Save-UrlToFile {
    param(
        [Parameter(Mandatory = $true)]
        [string]$Url,

        [Parameter(Mandatory = $true)]
        [string]$Path
    )

    if (Test-Path -LiteralPath $Path -PathType Leaf) {
        return $Path
    }

    $temporaryPath = $Path + '.download'
    $client = New-Object System.Net.WebClient
    try {
        $client.DownloadFile($Url, $temporaryPath)
        Move-Item -LiteralPath $temporaryPath -Destination $Path -Force
        return $Path
    }
    finally {
        $client.Dispose()
        if (Test-Path -LiteralPath $temporaryPath) {
            Remove-Item -LiteralPath $temporaryPath -Force -ErrorAction SilentlyContinue
        }
    }
}

function Convert-Base64ToImage {
    param([string]$Base64)

    if ([string]::IsNullOrWhiteSpace($Base64)) { return $null }

    try {
        $bytes = [Convert]::FromBase64String($Base64)
        $stream = New-Object System.IO.MemoryStream(, $bytes)
        try {
            $source = [System.Drawing.Image]::FromStream($stream)
            $bitmap = New-Object System.Drawing.Bitmap($source.Width, $source.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $g.DrawImage($source, 0, 0, $source.Width, $source.Height)
            }
            finally {
                $g.Dispose()
            }
            return $bitmap
        }
        finally {
            if ($source) { $source.Dispose() }
            $stream.Dispose()
        }
    }
    catch {
        Write-GuiLog -Level WARN -Message ('Could not decode media thumbnail: {0}' -f $_.Exception.Message)
        return $null
    }
}

function Get-ImageFromFile {
    param([Parameter(Mandatory = $true)][string]$Path)

    if (-not (Test-Path -LiteralPath $Path -PathType Leaf)) { return $null }

    try {
        $bytes = [System.IO.File]::ReadAllBytes($Path)
        $stream = New-Object System.IO.MemoryStream(, $bytes)
        try {
            $source = [System.Drawing.Image]::FromStream($stream)
            $bitmap = New-Object System.Drawing.Bitmap($source.Width, $source.Height, [System.Drawing.Imaging.PixelFormat]::Format32bppArgb)
            $g = [System.Drawing.Graphics]::FromImage($bitmap)
            try {
                $g.DrawImage($source, 0, 0, $source.Width, $source.Height)
            }
            finally {
                $g.Dispose()
            }
            return $bitmap
        }
        finally {
            if ($source) { $source.Dispose() }
            $stream.Dispose()
        }
    }
    catch {
        Write-GuiLog -Level WARN -Message ('Could not load image from {0}: {1}' -f $Path, $_.Exception.Message)
        return $null
    }
}

function Clear-RenderedImage {
    foreach ($image in @($script:ImageObjects)) {
        if ($image) { $image.Dispose() }
    }
    $script:ImageObjects.Clear()
}

function Get-DisplayName {
    param([Parameter(Mandatory = $true)][object]$Chat)

    $contact = $script:ContactLookup[[string]$Chat.id]
    if ($contact) {
        if (-not [string]::IsNullOrWhiteSpace([string]$contact.contactName)) {
            return [string]$contact.contactName
        }
        if (-not [string]::IsNullOrWhiteSpace([string]$contact.name)) {
            return [string]$contact.name
        }
    }

    if (-not [string]::IsNullOrWhiteSpace([string]$Chat.name)) {
        return [string]$Chat.name
    }

    return ([string]$Chat.id -replace '@c\.us$|@g\.us$|@lid$', '')
}

function Get-ContactAvatar {
    param([Parameter(Mandatory = $true)][string]$ChatId)

    if ($script:AvatarLookup.ContainsKey($ChatId)) { return $script:AvatarLookup[$ChatId] }
    $safeId = Get-SafeFileName -Value $ChatId -Fallback ([guid]::NewGuid().ToString('N'))
    $cachePath = Join-Path $script:AvatarDirectory ($safeId + '.jpg')

    try {
        if (-not (Test-Path -LiteralPath $cachePath -PathType Leaf)) {
            $contactInfo = Get-WhatsappContactInfo -ChatId $ChatId
            if (-not $contactInfo -or [string]::IsNullOrWhiteSpace([string]$contactInfo.avatar)) {
                $script:AvatarLookup[$ChatId] = $null
                return $null
            }
            Save-UrlToFile -Url ([string]$contactInfo.avatar) -Path $cachePath | Out-Null
        }
        $avatar = Get-ImageFromFile -Path $cachePath
        $script:AvatarLookup[$ChatId] = $avatar
        return $avatar
    }
    catch {
        Write-GuiLog -Level WARN -Message ('Avatar load failed for {0}: {1}' -f $ChatId, $_.Exception.Message)
        $script:AvatarLookup[$ChatId] = $null
        return $null
    }
}

function Get-Initial {
    param([string]$Name)
    if ([string]::IsNullOrWhiteSpace($Name)) { return '?' }
    $parts = @($Name.Trim().Split(' ') | Where-Object { $_ })
    if ($parts.Count -eq 1) { return $parts[0].Substring(0, [Math]::Min(2, $parts[0].Length)).ToUpperInvariant() }
    return ($parts[0].Substring(0, 1) + $parts[1].Substring(0, 1)).ToUpperInvariant()
}

# --- Main window and 20/80 layout ---
$form = New-Object System.Windows.Forms.Form
$form.Text = 'Blikbrein Pyn - PHKustom Chat Client'
if (Test-Path -LiteralPath $script:WindowIconPath -PathType Leaf) {
    try { $form.Icon = New-Object System.Drawing.Icon($script:WindowIconPath) }
    catch { Write-GuiLog -Level WARN -Message ('Window icon could not be loaded: {0}' -f $_.Exception.Message) }
}
$form.StartPosition = 'CenterScreen'
$form.MinimumSize = New-Object System.Drawing.Size(900, 600)
$form.Size = New-Object System.Drawing.Size(1280, 800)
$form.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#111B21')
$form.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#E9EDEF')
$form.Font = New-Object System.Drawing.Font('Segoe UI', 9)

$split = New-Object System.Windows.Forms.SplitContainer
$split.Dock = 'Fill'
$split.Orientation = [System.Windows.Forms.Orientation]::Vertical
$split.SplitterWidth = 4
$split.FixedPanel = [System.Windows.Forms.FixedPanel]::None
$form.Controls.Add($split)
$split.Panel1MinSize = 180
$split.Panel2MinSize = 350

$leftHeader = New-Object System.Windows.Forms.Panel
$leftHeader.Dock = 'Top'
$leftHeader.Height = 108
$leftHeader.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#202C33')

$brandPicture = New-Object System.Windows.Forms.PictureBox
$brandPicture.Location = New-Object System.Drawing.Point(10, 8)
$brandPicture.Size = New-Object System.Drawing.Size(42, 42)
$brandPicture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
if (Test-Path -LiteralPath $script:BrandIconPath -PathType Leaf) {
    try { $brandPicture.Image = Get-ImageFromFile -Path $script:BrandIconPath }
    catch { Write-GuiLog -Level WARN -Message ('Brand image could not be loaded: {0}' -f $_.Exception.Message) }
}

$title = New-Object System.Windows.Forms.Label
$title.Text = 'Blikbrein Pyn' + [Environment]::NewLine + 'Active chats'
$title.Font = New-Object System.Drawing.Font('Segoe UI', 11, [System.Drawing.FontStyle]::Bold)
$title.Location = New-Object System.Drawing.Point(58, 8)
$title.Size = New-Object System.Drawing.Size(120, 42)

$refreshButton = New-Object System.Windows.Forms.Button
$refreshButton.Text = 'Refresh'
$refreshButton.Anchor = 'Top,Right'
$refreshButton.Size = New-Object System.Drawing.Size(70, 27)
$refreshButton.Location = New-Object System.Drawing.Point(170, 14)

$searchBox = New-Object System.Windows.Forms.TextBox
$searchBox.Location = New-Object System.Drawing.Point(12, 68)
$searchBox.Anchor = 'Top,Left,Right'
$searchBox.Width = 228

$leftHeader.Controls.AddRange(@($brandPicture, $title, $refreshButton, $searchBox))
$split.Panel1.Controls.Add($leftHeader)

$chatList = New-Object System.Windows.Forms.ListBox
$chatList.Dock = 'Fill'
$chatList.BorderStyle = 'None'
$chatList.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#111B21')
$chatList.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#E9EDEF')
$chatList.Font = New-Object System.Drawing.Font('Segoe UI', 10)
$chatList.IntegralHeight = $false
$chatList.DrawMode = [System.Windows.Forms.DrawMode]::OwnerDrawFixed
$chatList.ItemHeight = 66
$split.Panel1.Controls.Add($chatList)
$chatList.BringToFront()

$rightHeader = New-Object System.Windows.Forms.Panel
$rightHeader.Dock = 'Top'
$rightHeader.Height = 68
$rightHeader.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#202C33')

$selectedAvatar = New-Object System.Windows.Forms.PictureBox
$selectedAvatar.Location = New-Object System.Drawing.Point(12, 9)
$selectedAvatar.Size = New-Object System.Drawing.Size(48, 48)
$selectedAvatar.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom

$contactLabel = New-Object System.Windows.Forms.Label
$contactLabel.Text = 'Select an active chat'
$contactLabel.Font = New-Object System.Drawing.Font('Segoe UI', 13, [System.Drawing.FontStyle]::Bold)
$contactLabel.Location = New-Object System.Drawing.Point(70, 9)
$contactLabel.AutoSize = $true

$chatIdLabel = New-Object System.Windows.Forms.Label
$chatIdLabel.Text = ''
$chatIdLabel.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#8696A0')
$chatIdLabel.Location = New-Object System.Drawing.Point(72, 37)
$chatIdLabel.AutoSize = $true

$exportCsvButton = New-Object System.Windows.Forms.Button
$exportCsvButton.Text = 'Export CSV'
$exportCsvButton.Anchor = 'Top,Right'
$exportCsvButton.Size = New-Object System.Drawing.Size(88, 30)
$exportCsvButton.Location = New-Object System.Drawing.Point(690, 18)
$exportCsvButton.Enabled = $false

$saveMediaButton = New-Object System.Windows.Forms.Button
$saveMediaButton.Text = 'Save Media'
$saveMediaButton.Anchor = 'Top,Right'
$saveMediaButton.Size = New-Object System.Drawing.Size(90, 30)
$saveMediaButton.Location = New-Object System.Drawing.Point(786, 18)
$saveMediaButton.Enabled = $false

$rightHeader.Controls.AddRange(@($selectedAvatar, $contactLabel, $chatIdLabel, $exportCsvButton, $saveMediaButton))
$split.Panel2.Controls.Add($rightHeader)

$composer = New-Object System.Windows.Forms.Panel
$composer.Dock = 'Bottom'
$composer.Height = 58
$composer.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#202C33')

$attachButton = New-Object System.Windows.Forms.Button
$attachButton.Text = 'Attach'
$attachButton.Location = New-Object System.Drawing.Point(10, 12)
$attachButton.Size = New-Object System.Drawing.Size(65, 32)
$attachButton.Enabled = $false

$messageBox = New-Object System.Windows.Forms.TextBox
$messageBox.Location = New-Object System.Drawing.Point(84, 14)
$messageBox.Anchor = 'Top,Left,Right'
$messageBox.Width = 700
$messageBox.Enabled = $false

$sendButton = New-Object System.Windows.Forms.Button
$sendButton.Text = 'Send'
$sendButton.Anchor = 'Top,Right'
$sendButton.Location = New-Object System.Drawing.Point(792, 12)
$sendButton.Size = New-Object System.Drawing.Size(65, 32)
$sendButton.Enabled = $false

$composer.Controls.AddRange(@($attachButton, $messageBox, $sendButton))
$split.Panel2.Controls.Add($composer)

$conversation = New-Object System.Windows.Forms.FlowLayoutPanel
$conversation.Dock = 'Fill'
$conversation.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
$conversation.WrapContents = $false
$conversation.AutoScroll = $true
$conversation.Padding = New-Object System.Windows.Forms.Padding(12)
$conversation.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#0B141A')
$split.Panel2.Controls.Add($conversation)
$conversation.BringToFront()

$brandSplash = New-Object System.Windows.Forms.PictureBox
$brandSplash.Size = New-Object System.Drawing.Size(360, 360)
$brandSplash.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
$brandSplash.Margin = New-Object System.Windows.Forms.Padding(40)
if (Test-Path -LiteralPath $script:BrandFullPath -PathType Leaf) {
    try { $brandSplash.Image = Get-ImageFromFile -Path $script:BrandFullPath }
    catch { Write-GuiLog -Level WARN -Message ('Full brand image could not be loaded: {0}' -f $_.Exception.Message) }
}
$conversation.Controls.Add($brandSplash)

$statusStrip = New-Object System.Windows.Forms.StatusStrip
$statusLabel = New-Object System.Windows.Forms.ToolStripStatusLabel
$statusLabel.Text = 'Starting...'
$statusStrip.Items.Add($statusLabel) | Out-Null
$form.Controls.Add($statusStrip)
$statusStrip.BringToFront()

function Set-Status {
    param(
        [string]$Text,
        [bool]$IsError = $false
    )

    $statusLabel.Text = $Text
    if ($IsError) {
        $statusLabel.ForeColor = [System.Drawing.Color]::Firebrick
    }
    else {
        $statusLabel.ForeColor = [System.Drawing.SystemColors]::ControlText
    }
    [System.Windows.Forms.Application]::DoEvents()
}

function Set-Busy {
    param([bool]$Busy)

    $script:IsBusy = $Busy
    $refreshButton.Enabled = -not $Busy
    $chatList.Enabled = -not $Busy
    $searchBox.Enabled = -not $Busy
    $messageBox.Enabled = (-not $Busy -and $null -ne $script:ActiveChatId)
    $sendButton.Enabled = (-not $Busy -and $null -ne $script:ActiveChatId)
    $attachButton.Enabled = (-not $Busy -and $null -ne $script:ActiveChatId)
    $exportCsvButton.Enabled = (-not $Busy -and $null -ne $script:ActiveChatId)
    $saveMediaButton.Enabled = (-not $Busy -and $null -ne $script:ActiveChatId)
    $form.UseWaitCursor = $Busy
}

function Update-ChatListFilter {
    $selectedId = $script:ActiveChatId
    $filter = $searchBox.Text.Trim()

    $chatList.BeginUpdate()
    try {
        $chatList.Items.Clear()
        foreach ($item in $script:ChatItems) {
            if (-not $filter -or $item.DisplayName -like ('*' + $filter + '*') -or $item.ChatId -like ('*' + $filter + '*')) {
                [void]$chatList.Items.Add($item)
            }
        }

        if ($selectedId) {
            foreach ($item in $chatList.Items) {
                if ($item.ChatId -eq $selectedId) {
                    $chatList.SelectedItem = $item
                    break
                }
            }
        }
    }
    finally {
        $chatList.EndUpdate()
    }
}

function Update-ActiveChat {
    param([switch]$Quiet)

    if ($script:IsBusy) { return }

    Set-Busy $true
    try {
        if (-not $Quiet) { Set-Status 'Retrieving contacts...' }
        $contacts = @(Get-Contacts)
        $script:ContactLookup = @{}
        foreach ($contact in $contacts) {
            if ($contact.id) { $script:ContactLookup[[string]$contact.id] = $contact }
        }

        if (-not $Quiet) { Set-Status 'Retrieving active chats...' }
        $chats = @(Get-WhatsappChats -Count $script:ChatCount)
        $items = New-Object System.Collections.ArrayList
        foreach ($chat in $chats) {
            if (-not $chat.id) { continue }
            $displayName = Get-DisplayName -Chat $chat
            $item = [PSCustomObject]@{
                DisplayName = $displayName
                ChatId      = [string]$chat.id
                Type        = [string]$chat.type
                Archived    = [bool]$chat.archive
                Avatar      = if ($script:AvatarLookup.ContainsKey([string]$chat.id)) { $script:AvatarLookup[[string]$chat.id] } else { $null }
            }
            if (-not $script:AvatarLookup.ContainsKey([string]$chat.id)) { $script:AvatarQueue.Enqueue([string]$chat.id) }
            [void]$items.Add($item)
        }

        $script:ChatItems = @($items)
        $script:LastChatRefresh = Get-Date
        Update-ChatListFilter
        Set-Status ('Loaded {0} active chats.' -f $script:ChatItems.Count)
    }
    catch {
        Write-GuiLog -Level ERROR -Message ('Active chat refresh failed: {0}' -f $_.Exception.ToString())
        Set-Status -IsError $true -Text ('Could not load active chats: {0}' -f $_.Exception.Message)
    }
    finally {
        Set-Busy $false
    }
}

function Add-TextBlock {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Control]$Parent,
        [string]$Text,
        [System.Drawing.Color]$Color
    )

    $label = New-Object System.Windows.Forms.Label
    $label.Text = $Text
    $label.ForeColor = $Color
    $label.AutoSize = $true
    $label.MaximumSize = New-Object System.Drawing.Size(([Math]::Max(300, $conversation.ClientSize.Width - 110)), 0)
    $label.Font = New-Object System.Drawing.Font('Segoe UI', 10)
    $label.Margin = New-Object System.Windows.Forms.Padding(8, 4, 8, 8)
    $Parent.Controls.Add($label)
}

function Add-ImageContent {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory = $true)][object]$Message
    )

    $image = $null
    $path = Get-MediaCachePath -Message $Message -DefaultExtension '.jpg'
    try {
        if ($Message.downloadUrl) {
            Save-UrlToFile -Url ([string]$Message.downloadUrl) -Path $path | Out-Null
            $image = Get-ImageFromFile -Path $path
        }
        elseif ($Message.jpegThumbnail) {
            $image = Convert-Base64ToImage -Base64 ([string]$Message.jpegThumbnail)
        }

        if (-not $image) {
            Add-TextBlock -Parent $Parent -Text '[Image unavailable]' -Color ([System.Drawing.Color]::Silver)
            return
        }

        [void]$script:ImageObjects.Add($image)
        $picture = New-Object System.Windows.Forms.PictureBox
        $picture.Image = $image
        $picture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
        $picture.Size = New-Object System.Drawing.Size(480, 320)
        $picture.Margin = New-Object System.Windows.Forms.Padding(8)
        $picture.Cursor = [System.Windows.Forms.Cursors]::Hand
        $picture.Tag = $path
        $picture.Add_DoubleClick({
                if ($this.Tag -and (Test-Path -LiteralPath ([string]$this.Tag))) {
                    Start-Process -FilePath ([string]$this.Tag)
                }
            })
        $Parent.Controls.Add($picture)
    }
    catch {
        Write-GuiLog -Level WARN -Message ('Image load failed for {0}: {1}' -f $Message.idMessage, $_.Exception.Message)
        Add-TextBlock -Parent $Parent -Text ('[Image could not be loaded: {0}]' -f $_.Exception.Message) -Color ([System.Drawing.Color]::Salmon)
    }
}

function Add-VideoContent {
    param(
        [Parameter(Mandatory = $true)][System.Windows.Forms.Control]$Parent,
        [Parameter(Mandatory = $true)][object]$Message
    )

    if ($Message.jpegThumbnail) {
        $thumbnail = Convert-Base64ToImage -Base64 ([string]$Message.jpegThumbnail)
        if ($thumbnail) {
            [void]$script:ImageObjects.Add($thumbnail)
            $picture = New-Object System.Windows.Forms.PictureBox
            $picture.Image = $thumbnail
            $picture.SizeMode = [System.Windows.Forms.PictureBoxSizeMode]::Zoom
            $picture.Size = New-Object System.Drawing.Size(480, 270)
            $picture.Margin = New-Object System.Windows.Forms.Padding(8)
            $Parent.Controls.Add($picture)
        }
    }

    $button = New-Object System.Windows.Forms.Button
    $button.Text = 'Download and play video'
    $button.AutoSize = $true
    $button.Margin = New-Object System.Windows.Forms.Padding(8)
    $button.Tag = [PSCustomObject]@{
        Url  = [string]$Message.downloadUrl
        Path = Get-MediaCachePath -Message $Message -DefaultExtension '.mp4'
    }
    $button.Add_Click({
            try {
                $media = $this.Tag
                if (-not $media.Url) { throw 'The API did not return a video download URL.' }
                $this.Enabled = $false
                $this.Text = 'Downloading video...'
                [System.Windows.Forms.Application]::DoEvents()
                Save-UrlToFile -Url $media.Url -Path $media.Path | Out-Null
                Start-Process -FilePath $media.Path
                $this.Text = 'Play video'
            }
            catch {
                [System.Windows.Forms.MessageBox]::Show($_.Exception.Message, 'Video error', 'OK', 'Error') | Out-Null
                Write-GuiLog -Level ERROR -Message ('Video open failed: {0}' -f $_.Exception.ToString())
                $this.Text = 'Download and play video'
            }
            finally {
                $this.Enabled = $true
            }
        })
    $Parent.Controls.Add($button)
}

function Add-MessageBubble {
    param([Parameter(Mandatory = $true)][object]$Message)

    $outgoing = ([string]$Message.type -eq 'outgoing')
    $bubble = New-Object System.Windows.Forms.FlowLayoutPanel
    $bubble.FlowDirection = [System.Windows.Forms.FlowDirection]::TopDown
    $bubble.WrapContents = $false
    $bubble.AutoSize = $true
    $bubble.AutoSizeMode = [System.Windows.Forms.AutoSizeMode]::GrowAndShrink
    $bubble.MaximumSize = New-Object System.Drawing.Size(([Math]::Max(400, $conversation.ClientSize.Width - 70)), 0)
    $bubble.Padding = New-Object System.Windows.Forms.Padding(6)
    $bubble.Margin = New-Object System.Windows.Forms.Padding(8, 5, 8, 5)
    if ($outgoing) {
        $bubble.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#005C4B')
        $bubble.Margin = New-Object System.Windows.Forms.Padding(([Math]::Max(8, [int]($conversation.ClientSize.Width * 0.20))), 5, 8, 5)
    }
    else {
        $bubble.BackColor = [System.Drawing.ColorTranslator]::FromHtml('#202C33')
    }

    $senderText = if ($outgoing) { 'Me' } elseif ($Message.senderContactName) { [string]$Message.senderContactName } elseif ($Message.senderName) { [string]$Message.senderName } else { $script:ActiveChatName }
    $header = New-Object System.Windows.Forms.Label
    $header.Text = '{0}  {1}' -f $senderText, (Get-MessageTimeText -Timestamp $Message.timestamp)
    $header.ForeColor = [System.Drawing.ColorTranslator]::FromHtml('#9FB3BD')
    $header.AutoSize = $true
    $header.Font = New-Object System.Drawing.Font('Segoe UI', 8, [System.Drawing.FontStyle]::Bold)
    $header.Margin = New-Object System.Windows.Forms.Padding(8, 5, 8, 2)
    $bubble.Controls.Add($header)

    switch ([string]$Message.typeMessage) {
        { $_ -in @('textMessage', 'extendedTextMessage', 'quotedMessage') } {
            $text = [string]$Message.textMessage
            if (-not $text -and $Message.extendedTextMessage) { $text = [string]$Message.extendedTextMessage.text }
            if (-not $text) { $text = '[Empty text message]' }
            Add-TextBlock -Parent $bubble -Text $text -Color ([System.Drawing.ColorTranslator]::FromHtml('#E9EDEF'))
            break
        }
        'imageMessage' {
            Add-ImageContent -Parent $bubble -Message $Message
            if ($Message.caption) { Add-TextBlock -Parent $bubble -Text ([string]$Message.caption) -Color ([System.Drawing.ColorTranslator]::FromHtml('#E9EDEF')) }
            break
        }
        'stickerMessage' {
            Add-ImageContent -Parent $bubble -Message $Message
            break
        }
        'videoMessage' {
            Add-VideoContent -Parent $bubble -Message $Message
            if ($Message.caption) { Add-TextBlock -Parent $bubble -Text ([string]$Message.caption) -Color ([System.Drawing.ColorTranslator]::FromHtml('#E9EDEF')) }
            break
        }
        default {
            $description = '[{0}]' -f [string]$Message.typeMessage
            if ($Message.fileName) { $description += ' ' + [string]$Message.fileName }
            if ($Message.caption) { $description += [Environment]::NewLine + [string]$Message.caption }
            Add-TextBlock -Parent $bubble -Text $description -Color ([System.Drawing.Color]::Silver)
        }
    }

    $conversation.Controls.Add($bubble)
}

function Show-SelectedChat {
    param([switch]$Quiet)

    if (-not $script:ActiveChatId -or $script:IsBusy) { return }

    Set-Busy $true
    try {
        if (-not $Quiet) { Set-Status ('Loading chat with {0}...' -f $script:ActiveChatName) }
        $history = @(Get-ChatHistory -ChatId $script:ActiveChatId -Count $script:MessageCount)
        Clear-RenderedImage
        $conversation.SuspendLayout()
        try {
            $conversation.Controls.Clear()
            foreach ($message in @($history | Sort-Object { [int64]$_.timestamp })) {
                Add-MessageBubble -Message $message
            }
        }
        finally {
            $conversation.ResumeLayout($true)
        }

        if ($conversation.Controls.Count -gt 0) {
            $conversation.ScrollControlIntoView($conversation.Controls[$conversation.Controls.Count - 1])
        }
        Set-ChatRead -ChatId $script:ActiveChatId | Out-Null
        Set-Status ('Showing {0} messages.' -f $history.Count)
    }
    catch {
        Write-GuiLog -Level ERROR -Message ('History load failed for {0}: {1}' -f $script:ActiveChatId, $_.Exception.ToString())
        Set-Status -IsError $true -Text ('Could not load chat history: {0}' -f $_.Exception.Message)
    }
    finally {
        Set-Busy $false
    }
}

$chatList.Add_DrawItem({
        if ($_.Index -lt 0 -or $_.Index -ge $chatList.Items.Count) { return }
        $item = $chatList.Items[$_.Index]
        $selected = (($_.State -band [Windows.Forms.DrawItemState]::Selected) -ne 0)
        $background = if ($selected) { [Drawing.ColorTranslator]::FromHtml('#17453F') } else { $chatList.BackColor }
        $backgroundBrush = New-Object Drawing.SolidBrush($background)
        $_.Graphics.FillRectangle($backgroundBrush, $_.Bounds)
        $backgroundBrush.Dispose()

        $avatarRect = New-Object Drawing.Rectangle(($_.Bounds.X + 9), ($_.Bounds.Y + 9), 46, 46)
        $drawnAvatar = $false
        if ($item.Avatar) {
            try {
                $state = $_.Graphics.Save()
                $avatarPath = New-Object Drawing.Drawing2D.GraphicsPath
                $avatarPath.AddEllipse($avatarRect)
                $_.Graphics.SetClip($avatarPath)
                $_.Graphics.DrawImage($item.Avatar, $avatarRect)
                $_.Graphics.Restore($state)
                $avatarPath.Dispose()
                $drawnAvatar = $true
            }
            catch {
                $drawnAvatar = $false
            }
        }

        if (-not $drawnAvatar) {
            $avatarBrush = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#2A7F76'))
            $_.Graphics.FillEllipse($avatarBrush, $avatarRect)
            $avatarBrush.Dispose()
            $initials = Get-Initial -Name $item.DisplayName
            $initialFont = New-Object Drawing.Font('Segoe UI', 11, [Drawing.FontStyle]::Bold)
            $initialBrush = New-Object Drawing.SolidBrush([Drawing.Color]::White)
            $initialSize = $_.Graphics.MeasureString($initials, $initialFont)
            $_.Graphics.DrawString($initials, $initialFont, $initialBrush, ($avatarRect.X + (($avatarRect.Width - $initialSize.Width) / 2)), ($avatarRect.Y + (($avatarRect.Height - $initialSize.Height) / 2)))
            $initialFont.Dispose()
            $initialBrush.Dispose()
        }

        $nameFont = New-Object Drawing.Font('Segoe UI', 10, [Drawing.FontStyle]::Bold)
        $detailFont = New-Object Drawing.Font('Segoe UI', 8)
        $nameBrush = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#E9EDEF'))
        $detailBrush = New-Object Drawing.SolidBrush([Drawing.ColorTranslator]::FromHtml('#8696A0'))
        $_.Graphics.DrawString([string]$item.DisplayName, $nameFont, $nameBrush, ($_.Bounds.X + 64), ($_.Bounds.Y + 11))
        $_.Graphics.DrawString([string]$item.ChatId, $detailFont, $detailBrush, ($_.Bounds.X + 64), ($_.Bounds.Y + 36))
        $nameFont.Dispose()
        $detailFont.Dispose()
        $nameBrush.Dispose()
        $detailBrush.Dispose()
    })

$chatList.Add_SelectedIndexChanged({
        if ($script:IsBusy -or -not $chatList.SelectedItem) { return }
        $selected = $chatList.SelectedItem
        $script:ActiveChatId = [string]$selected.ChatId
        $script:ActiveChatName = [string]$selected.DisplayName
        $contactLabel.Text = $script:ActiveChatName
        $chatIdLabel.Text = $script:ActiveChatId
        $selectedAvatar.Image = $selected.Avatar
        Show-SelectedChat
    })

$searchBox.Add_TextChanged({ Update-ChatListFilter })
$refreshButton.Add_Click({ Update-ActiveChat })

$sendAction = {
    if ($script:IsBusy -or -not $script:ActiveChatId) { return }
    $text = $messageBox.Text.Trim()
    if (-not $text) { return }

    Set-Busy $true
    try {
        Set-Status 'Sending message...'
        $result = Send-Whatsapp -ChatId $script:ActiveChatId -Message $text
        if (-not $result -or -not $result.idMessage) { throw 'Green API did not confirm the message ID.' }
        $messageBox.Clear()
        Set-Busy $false
        Show-SelectedChat
    }
    catch {
        Write-GuiLog -Level ERROR -Message ('Send failed: {0}' -f $_.Exception.ToString())
        Set-Status -IsError $true -Text ('Send failed: {0}' -f $_.Exception.Message)
    }
    finally {
        Set-Busy $false
    }
}

$sendButton.Add_Click($sendAction)
$messageBox.Add_KeyDown({
        if ($_.KeyCode -eq [System.Windows.Forms.Keys]::Enter -and -not $_.Shift) {
            $_.SuppressKeyPress = $true
            & $sendAction
        }
    })

$attachButton.Add_Click({
        if (-not $script:ActiveChatId -or $script:IsBusy) { return }

        $dialog = New-Object System.Windows.Forms.OpenFileDialog
        $dialog.Title = 'Select an image or video'
        $dialog.Filter = 'Supported media|*.jpg;*.jpeg;*.png;*.gif;*.webp;*.mp4;*.mov;*.avi;*.mkv;*.webm|Images|*.jpg;*.jpeg;*.png;*.gif;*.webp|Videos|*.mp4;*.mov;*.avi;*.mkv;*.webm|All files|*.*'
        if ($dialog.ShowDialog($form) -ne [System.Windows.Forms.DialogResult]::OK) {
            $dialog.Dispose()
            return
        }

        $path = $dialog.FileName
        $dialog.Dispose()
        $caption = $messageBox.Text.Trim()

        Set-Busy $true
        try {
            Set-Status ('Uploading {0}...' -f [System.IO.Path]::GetFileName($path))
            $result = Send-WhatsappFileByUpload -ChatId $script:ActiveChatId -FilePath $path -Caption $caption
            if (-not $result -or -not $result.idMessage) { throw 'Green API did not confirm the uploaded media message.' }
            $messageBox.Clear()
            Set-Busy $false
            Show-SelectedChat
        }
        catch {
            Write-GuiLog -Level ERROR -Message ('Media upload failed: {0}' -f $_.Exception.ToString())
            Set-Status -IsError $true -Text ('Media upload failed: {0}' -f $_.Exception.Message)
        }
        finally {
            Set-Busy $false
        }
    })

$exportCsvButton.Add_Click({
        if (-not $script:ActiveChatId -or $script:IsBusy) { return }
        $dialog = New-Object Windows.Forms.SaveFileDialog
        $safeName = Get-SafeFileName -Value $script:ActiveChatName -Fallback 'chat'
        $dialog.Title = 'Export selected chat to CSV'
        $dialog.Filter = 'CSV files|*.csv'
        $dialog.FileName = '{0}_{1}.csv' -f $safeName, (Get-Date -Format 'yyyyMMdd_HHmmss')
        if ($dialog.ShowDialog($form) -ne [Windows.Forms.DialogResult]::OK) { $dialog.Dispose(); return }
        $path = $dialog.FileName
        $dialog.Dispose()
        Set-Busy $true
        try {
            Set-Status 'Exporting chat to CSV...'
            $file = Export-WhatsappChat -ChatId $script:ActiveChatId -Path $path -Count 10000
            Set-Status ('Chat exported to {0}' -f $file.FullName)
            $message = 'Chat exported successfully:' + [Environment]::NewLine + $file.FullName
            [Windows.Forms.MessageBox]::Show($message, 'Export complete', 'OK', 'Information') | Out-Null
        }
        catch {
            Write-GuiLog -Level ERROR -Message ('CSV export failed: {0}' -f $_.Exception.ToString())
            Set-Status -IsError $true -Text ('CSV export failed: {0}' -f $_.Exception.Message)
        }
        finally { Set-Busy $false }
    })

$saveMediaButton.Add_Click({
        if (-not $script:ActiveChatId -or $script:IsBusy) { return }
        $dialog = New-Object Windows.Forms.FolderBrowserDialog
        $dialog.Description = 'Select a folder for all media from this chat'
        if ($dialog.ShowDialog($form) -ne [Windows.Forms.DialogResult]::OK) { $dialog.Dispose(); return }
        $safeName = Get-SafeFileName -Value $script:ActiveChatName -Fallback 'chat'
        $destination = Join-Path $dialog.SelectedPath ('{0}_media_{1}' -f $safeName, (Get-Date -Format 'yyyyMMdd_HHmmss'))
        $dialog.Dispose()
        Set-Busy $true
        try {
            Set-Status 'Downloading all available chat media...'
            $results = @(Save-WhatsappChatMedia -ChatId $script:ActiveChatId -DestinationPath $destination -Count 10000)
            $downloaded = @($results | Where-Object { $_.Status -eq 'Downloaded' }).Count
            $failed = @($results | Where-Object { $_.Status -eq 'Failed' }).Count
            Set-Status ('Media export complete: {0} downloaded, {1} failed.' -f $downloaded, $failed)
            $message = 'Media folder:' + [Environment]::NewLine + $destination + [Environment]::NewLine + [Environment]::NewLine + ('Downloaded: {0}' -f $downloaded) + [Environment]::NewLine + ('Failed: {0}' -f $failed)
            [Windows.Forms.MessageBox]::Show($message, 'Media export complete', 'OK', 'Information') | Out-Null
        }
        catch {
            Write-GuiLog -Level ERROR -Message ('Media export failed: {0}' -f $_.Exception.ToString())
            Set-Status -IsError $true -Text ('Media export failed: {0}' -f $_.Exception.Message)
        }
        finally { Set-Busy $false }
    })

$avatarTimer = New-Object System.Windows.Forms.Timer
$avatarTimer.Interval = 350
$avatarTimer.Add_Tick({
        if ($script:IsBusy -or $script:AvatarQueue.Count -eq 0) { return }
        $chatId = [string]$script:AvatarQueue.Dequeue()
        $avatar = Get-ContactAvatar -ChatId $chatId
        foreach ($item in $script:ChatItems) { if ($item.ChatId -eq $chatId) { $item.Avatar = $avatar } }
        if ($script:ActiveChatId -eq $chatId) { $selectedAvatar.Image = $avatar }
        $chatList.Invalidate()
    })

$timer = New-Object System.Windows.Forms.Timer
$timer.Interval = 15000
$timer.Add_Tick({
        if ($script:IsBusy) { return }
        if ($script:ActiveChatId) { Show-SelectedChat -Quiet }
        if (((Get-Date) - $script:LastChatRefresh).TotalSeconds -ge 60) { Update-ActiveChat -Quiet }
    })

$form.Add_Shown({
        $split.SplitterDistance = [Math]::Max($split.Panel1MinSize, [int]($form.ClientSize.Width * 0.20))
        $refreshButton.Left = [Math]::Max(90, $leftHeader.ClientSize.Width - $refreshButton.Width - 12)
        $searchBox.Width = [Math]::Max(80, $leftHeader.ClientSize.Width - 24)
        $sendButton.Left = [Math]::Max(180, $composer.ClientSize.Width - $sendButton.Width - 10)
        $saveMediaButton.Left = [Math]::Max(300, $rightHeader.ClientSize.Width - $saveMediaButton.Width - 12)
        $exportCsvButton.Left = $saveMediaButton.Left - $exportCsvButton.Width - 8
        $messageBox.Width = [Math]::Max(80, $sendButton.Left - $messageBox.Left - 8)
        try {
            Clear-WhatsappLocalData -OlderThanDays $script:MediaRetentionDays -Confirm:$false
        }
        catch {
            Write-GuiLog -Level WARN -Message ('Retention cleanup failed: {0}' -f $_.Exception.Message)
        }
        Update-ActiveChat
        $timer.Start()
        $avatarTimer.Start()
    })

$form.Add_Resize({
        if ($form.WindowState -ne [System.Windows.Forms.FormWindowState]::Minimized) {
            $refreshButton.Left = [Math]::Max(90, $leftHeader.ClientSize.Width - $refreshButton.Width - 12)
            $searchBox.Width = [Math]::Max(80, $leftHeader.ClientSize.Width - 24)
            $sendButton.Left = [Math]::Max(180, $composer.ClientSize.Width - $sendButton.Width - 10)
            $saveMediaButton.Left = [Math]::Max(300, $rightHeader.ClientSize.Width - $saveMediaButton.Width - 12)
            $exportCsvButton.Left = $saveMediaButton.Left - $exportCsvButton.Width - 8
            $messageBox.Width = [Math]::Max(80, $sendButton.Left - $messageBox.Left - 8)
        }
    })

$form.Add_FormClosing({
        $timer.Stop()
        $avatarTimer.Stop()
        Clear-RenderedImage
        foreach ($avatar in $script:AvatarLookup.Values) { if ($avatar) { $avatar.Dispose() } }
        if ($brandPicture.Image) { $brandPicture.Image.Dispose() }
        if ($brandSplash.Image) { $brandSplash.Image.Dispose() }
    })

try {
    [void]$form.ShowDialog()
}
finally {
    $timer.Dispose()
    $avatarTimer.Dispose()
    $form.Dispose()
}
