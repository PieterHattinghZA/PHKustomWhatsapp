using System.Net.Http.Json;
using System.Text.Json;
using PHKustom.ChatClient.Models;

namespace PHKustom.ChatClient.Services;

public sealed class GreenApiClient(HttpClient http, AppConfigurationService configuration)
{
    private GreenApiOptions? _options;

    private async Task<GreenApiOptions> OptionsAsync(CancellationToken token) =>
        _options ??= await configuration.LoadAsync(token);

    private static string NameFromId(string id) => id.Replace("@c.us", "").Replace("@g.us", "").Replace("@lid", "");

    private async Task<Uri> EndpointAsync(string method, CancellationToken token)
    {
        var options = await OptionsAsync(token);
        return new Uri($"{options.ApiUrl}/waInstance{options.InstanceId}/{method}/{options.ApiToken}");
    }

    public async Task<IReadOnlyList<ChatSummary>> GetChatsAsync(int count, CancellationToken token)
    {
        var uri = await EndpointAsync("getChats", token);
        using var response = await http.GetAsync(new UriBuilder(uri) { Query = $"count={count}" }.Uri, token);
        response.EnsureSuccessStatusCode();
        using var document = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(token));
        var result = new List<ChatSummary>();
        foreach (var item in document.RootElement.EnumerateArray())
        {
            var id = item.GetProperty("id").GetString() ?? continue;
            var archived = item.TryGetProperty("archive", out var archive) && archive.GetBoolean();
            result.Add(new ChatSummary(id, NameFromId(id), null, archived));
        }

        var resolved = new List<ChatSummary>(result.Count);
        foreach (var chat in result)
        {
            try
            {
                var contact = await GetContactAsync(chat.Id, token);
                resolved.Add(chat with { DisplayName = contact.Name ?? chat.DisplayName, AvatarUrl = contact.Avatar });
            }
            catch { resolved.Add(chat); }
        }
        return resolved;
    }

    private async Task<(string? Name, string? Avatar)> GetContactAsync(string chatId, CancellationToken token)
    {
        if (chatId.EndsWith("@g.us", StringComparison.OrdinalIgnoreCase)) return (null, null);
        var uri = await EndpointAsync("getContactInfo", token);
        using var response = await http.PostAsJsonAsync(uri, new { chatId }, token);
        response.EnsureSuccessStatusCode();
        using var document = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(token));
        var root = document.RootElement;
        var name = root.TryGetProperty("contactName", out var contactName) ? contactName.GetString() : null;
        name ??= root.TryGetProperty("name", out var fallbackName) ? fallbackName.GetString() : null;
        var avatar = root.TryGetProperty("avatar", out var avatarNode) ? avatarNode.GetString() : null;
        return (name, avatar);
    }

    public async Task<IReadOnlyList<ChatMessage>> GetHistoryAsync(string chatId, int count, CancellationToken token)
    {
        var uri = await EndpointAsync("getChatHistory", token);
        using var response = await http.PostAsJsonAsync(uri, new { chatId, count }, token);
        response.EnsureSuccessStatusCode();
        using var document = JsonDocument.Parse(await response.Content.ReadAsStreamAsync(token));
        return document.RootElement.EnumerateArray().Select(item => new ChatMessage(
            item.GetProperty("idMessage").GetString() ?? Guid.NewGuid().ToString("N"),
            item.TryGetProperty("chatId", out var chat) ? chat.GetString() ?? chatId : chatId,
            item.TryGetProperty("timestamp", out var timestamp) ? timestamp.GetInt64() : 0,
            item.TryGetProperty("type", out var direction) && direction.GetString() == "outgoing",
            item.TryGetProperty("typeMessage", out var type) ? type.GetString() ?? "unknown" : "unknown",
            item.TryGetProperty("textMessage", out var text) ? text.GetString() : null,
            item.TryGetProperty("caption", out var caption) ? caption.GetString() : null,
            item.TryGetProperty("downloadUrl", out var download) ? download.GetString() : null,
            item.TryGetProperty("fileName", out var file) ? file.GetString() : null,
            item.TryGetProperty("mimeType", out var mime) ? mime.GetString() : null)).OrderBy(x => x.Timestamp).ToArray();
    }

    public async Task SendMessageAsync(string chatId, string message, CancellationToken token)
    {
        var uri = await EndpointAsync("sendMessage", token);
        using var response = await http.PostAsJsonAsync(uri, new { chatId, message }, token);
        response.EnsureSuccessStatusCode();
    }
}
