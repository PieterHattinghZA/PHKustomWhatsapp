# Security policy

## Credentials

PHKustomWhatsapp stores the Green API token using Windows Data Protection API (DPAPI). The protected token is bound to the current Windows user and computer.

Never commit config.json or paste its contents into an issue. If a token was stored in plaintext, copied, exposed in logs, or committed, rotate it immediately:

~~~powershell
Import-Module PHKustomWhatsapp -Force
Update-WhatsappApiToken -Confirm
~~~

## Local message data

Chat history, media cache and logs can contain personal information. The module restricts the application data directory to the current Windows user. Use the cleanup command to enforce retention:

~~~powershell
Clear-WhatsappLocalData -OlderThanDays 30 -Confirm
~~~

Backups of these directories must receive equivalent access controls and encryption.

## Reporting a vulnerability

Do not disclose tokens, phone numbers, message text or reproducible private-account data in a public issue. Contact the repository owner privately with:

- affected version and commit;
- concise reproduction steps;
- impact;
- suggested remediation, if known.

Revoke exposed credentials before sending the report.
