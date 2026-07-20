# PHKustom Chat Client

A .NET 10 Avalonia desktop replacement for `simple-gui.ps1`.

## Architecture

- Avalonia 12 UI with compiled bindings
- CommunityToolkit.Mvvm commands and observable state
- fully asynchronous Green API calls
- SQLite WAL message cache
- cancellable media downloads and exports
- Windows DPAPI token protection
- cross-platform application structure

## First launch

Set these environment variables once:

```powershell
$env:GREEN_API_URL = 'https://api.green-api.com'
$env:GREEN_API_INSTANCE_ID = '<instance-id>'
$env:GREEN_API_TOKEN = '<token>'
```

The first successful launch stores the token under the current Windows user's DPAPI protection in `%APPDATA%\PHKustom\ChatClient\config.json`.

## Run

```powershell
cd src\PHKustom.ChatClient
dotnet restore
dotnet run
```

## Publish for Windows

```powershell
dotnet publish -c Release -r win-x64 --self-contained true -p:PublishSingleFile=true
```

The PowerShell module remains available for administration and compatibility. The Avalonia client talks to GREEN API directly and does not execute PowerShell for normal GUI operations.
