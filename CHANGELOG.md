# Changelog

## 4.1.0 - 20/07/2026

### Added

- Blikbrein Pyn application icon and in-client branding.
- Cached Green API contact avatars in the chat list and selected-chat header.
- Selected-chat UTF-8 CSV export.
- Bulk download of all available chat images, videos, documents, audio and stickers.
- GUI buttons for CSV and media export.

### Changed

- Installer now deploys the required branding assets.
- Contact list uses owner-drawn rows with circular avatars and initials fallback.

## 4.0.0 - 20/07/2026

### Added

- Active-chat retrieval through Green API getChats.
- Two-column 20%/80% Windows Forms chat client.
- Inline image display, video thumbnails, video playback and media upload.
- DPAPI-protected API token storage and automatic plaintext migration.
- User-only ACL enforcement for local application data.
- Structured dated logging and configurable media retention.
- Bounded retry handling for connectivity, HTTP 429 and HTTP 5xx failures.
- URL-encoded query parameters.
- Pester, PSScriptAnalyzer and GitHub Actions validation.

### Changed

- Split configuration and API transport into Private module components.
- Removed hard-coded SQLite and ImportExcel dependencies.
- Updated the installer to copy versioned module and private files.
- Aligned module, manifest and documentation versions at 4.0.0.

### Security

- Removed published instance and telephone identifiers from source.
- Eliminated plaintext token creation for new configurations.
- Replaced silent production exception handlers with logged failures.
