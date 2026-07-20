namespace PHKustom.ChatClient.Models;

public sealed record ChatSummary(string Id, string DisplayName, string? AvatarUrl, bool Archived);

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
    public string DisplayText => Text ?? Caption ?? FileName ?? $"[{Type}]";
}

public sealed record GreenApiOptions(string ApiUrl, string InstanceId, string ApiToken);
