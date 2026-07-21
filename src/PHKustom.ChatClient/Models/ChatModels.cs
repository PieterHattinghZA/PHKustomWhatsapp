namespace PHKustom.ChatClient.Models;

public sealed record ChatSummary(string Id, string DisplayName, string? AvatarUrl, bool Archived)
{
    public string Initial => string.IsNullOrWhiteSpace(DisplayName) ? "?" : DisplayName[..1].ToUpperInvariant();
    public string DisplayId => Id.Contains('@') ? Id[..Id.IndexOf('@')] : Id;
    public string FormattedName
    {
        get
        {
            var clean = new string(DisplayName.Where(char.IsDigit).ToArray());
            return clean.Length > 5 && DisplayName.Replace(" ", "").Replace("+", "").Replace("-", "").All(char.IsDigit) ? $"+{clean}" : DisplayName;
        }
    }
}

public sealed record ChatMessage(
    string Id,
    string ChatId,
    long Timestamp,
    bool IsOutgoing,
    string Type,
    string? Text,
    string? Caption,
    string? DownloadUrl,
    string? FileName,
    string? MimeType)
{
    public DateTimeOffset SentAt => DateTimeOffset.FromUnixTimeSeconds(Timestamp).ToLocalTime();
    public string FormattedTime => SentAt.Date == DateTimeOffset.Now.Date ? SentAt.ToString("HH:mm") : SentAt.ToString("dd/MM/yyyy HH:mm");
    public string DisplayText => Text ?? Caption ?? FileName ?? $"[{Type}]";
    public bool IsImage => MimeType?.StartsWith("image/") == true;
}

public sealed record GreenApiOptions(string ApiUrl, string InstanceId, string ApiToken);
