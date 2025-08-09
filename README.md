# PHKustomWhatsapp PowerShell Module

WhatsApp automation and reporting toolkit using Green API.

## Features
- Send WhatsApp messages, media, locations, contacts
- Manage chats, groups, and contacts
- Retrieve message history and status
- Robust error handling and configuration management

## Requirements
- PowerShell 5.1+
- Green API account and credentials
- ImportExcel module (for Excel integration)

## Installation
1. Copy `PHKustomWhatsapp.psm1` to your module path or project folder.
2. Import the module:
   ```powershell
   Import-Module ./PHKustomWhatsapp.psm1
   ```
3. Ensure your config file exists at `c:\Programdata\PHWhatsapp\config.json`.

## Usage Example
```powershell
Send-Whatsapp -Number "0731234567" -Message "Hello from PowerShell!"
```

## License
See LICENSE.md for details.

## Author
Pieter Hattingh

---
For full documentation, see the comments in the module or contact the author.
