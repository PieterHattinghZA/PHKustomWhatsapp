# PHKustomWhatsapp

A Windows PowerShell 5.1 toolkit and Blikbrein Pyn-branded two-column Windows Forms client for messaging through Green API.

## Highlights

- Retrieves recent active chats through the Green API getChats method.
- Resolves active chats against the account contact list and displays each available profile avatar.
- Displays the selected conversation in an approximately 20%/80% interface.
- Renders images and video thumbnails and opens downloaded videos in Windows.
- Sends text, image and video messages.
- Exports the selected chat to UTF-8 CSV.
- Downloads all available images, videos, audio, stickers and documents from a selected chat.
- Protects the API token with Windows DPAPI for the current Windows user.
- Restricts %APPDATA%\PHWhatsapp to the owning user.
- Retries transient DNS, connectivity, HTTP 429 and HTTP 5xx failures.
- Writes dated operational logs without including the API token.

## Requirements

- Windows PowerShell 5.1
- Windows Forms support
- A configured and authorised Green API instance

No ImportExcel or SQLite dependency is required.

## Installation

~~~powershell
Set-Location C:\Scripts\PHKustom-Whatsapp
.\Install-PHKustomWhatsapp.ps1 -Scope CurrentUser
~~~

For a system-wide installation:

~~~powershell
.\Install-PHKustomWhatsapp.ps1 -Scope AllUsers
~~~

The installer uses a versioned module directory and copies the required Private implementation files and GUI.

## First-time configuration

~~~powershell
Import-Module PHKustomWhatsapp -Force
New-WhatsappConfigFile
~~~

The token prompt is masked. The token is stored as a DPAPI-protected value in %APPDATA%\PHWhatsapp\config.json. It can only be decrypted by the same Windows user on the same computer.

An older plaintext configuration is migrated automatically. Rotate any token that may previously have been copied or exposed:

~~~powershell
Update-WhatsappApiToken -Confirm
~~~

## GUI

~~~powershell
.\simple-gui.ps1 -ChatCount 150 -MessageCount 100 -MediaRetentionDays 30
~~~

Media is cached under %APPDATA%\PHWhatsapp\MediaCache. Expired files are removed when the GUI starts.

## Chat and media export

~~~powershell
Export-WhatsappChat -ChatId '27821234567@c.us' -Path 'C:\Exports\contact.csv' -Count 10000
Save-WhatsappChatMedia -ChatId '27821234567@c.us' -DestinationPath 'C:\Exports\contact-media' -Count 10000
~~~

The GUI provides Export CSV and Save Media buttons for the selected contact. Download URLs supplied by Green API can expire; media that Green API no longer exposes is reported as unavailable.

## Command examples

~~~powershell
Get-WhatsappChats -Count 100
Get-ChatHistory -ChatId '27821234567@c.us' -Count 50
Send-Whatsapp -ChatId '27821234567@c.us' -Message 'Test message'
Send-WhatsappFileByUpload -ChatId '27821234567@c.us' -FilePath 'C:\Pictures\photo.jpg' -Caption 'Photo'
~~~

## Logging and local-data cleanup

- Module logs: %APPDATA%\PHWhatsapp\Logs\module_yyyy-MM-dd.log
- GUI logs: %APPDATA%\PHWhatsapp\Logs\simple-gui_yyyy-MM-dd.log

~~~powershell
Clear-WhatsappLocalData -OlderThanDays 30 -WhatIf
Clear-WhatsappLocalData -OlderThanDays 30 -Confirm
~~~

## Development validation

~~~powershell
Invoke-ScriptAnalyzer -Path . -Recurse
Invoke-Pester -Path .\Tests
~~~

GitHub Actions validates the manifest, runs PSScriptAnalyzer and executes Pester tests on Windows PowerShell 5.1.

## Security

Do not commit configuration, message databases, cached media or logs. See [SECURITY.md](SECURITY.md).

## License

MIT. See [LICENSE.md](LICENSE.md).
