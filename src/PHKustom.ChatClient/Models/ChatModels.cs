namespace PHKustom.ChatClient.Models;

public sealed record ChatSummary(string Id, string DisplayName, string? AvatarUrl, bool Archived)
{
    public string RawNumber => Id.Contains('@') ? Id[..Id.IndexOf('@')] : Id;
    public string FormattedPhone
    {
        get
        {
            var digits = new string(RawNumber.Where(char.IsDigit).ToArray());
            return digits.Length > 0 ? $"+{digits}" : RawNumber;
        }
    }
    public bool IsPhoneName => string.IsNullOrWhiteSpace(DisplayName) || DisplayName.Replace(" ", "").Replace("+", "").Replace("-", "").All(char.IsDigit);
    public string FormattedName => IsPhoneName ? FormattedPhone : DisplayName;
    public string Initial => IsPhoneName ? "👤" : (string.IsNullOrWhiteSpace(DisplayName) ? "👤" : DisplayName[..1].ToUpperInvariant());
    public string DisplayId => RawNumber;
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
    public bool IsImage => MimeType?.StartsWith("image/") == true || Type.Equals("image", StringComparison.OrdinalIgnoreCase);
    public bool IsVideo => MimeType?.StartsWith("video/") == true || Type.Equals("video", StringComparison.OrdinalIgnoreCase);
    public bool IsMedia => !string.IsNullOrWhiteSpace(DownloadUrl) && (IsImage || IsVideo);
}

public sealed record GreenApiOptions(string ApiUrl, string InstanceId, string ApiToken);
