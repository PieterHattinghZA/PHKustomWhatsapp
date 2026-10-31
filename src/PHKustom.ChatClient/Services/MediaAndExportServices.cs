using System.Globalization;
using System.Net;
using System.Text;
using PHKustom.ChatClient.Models;

namespace PHKustom.ChatClient.Services;

public sealed class MediaCacheService(HttpClient http, AppPaths paths)
{
    public async Task<string> DownloadAsync(ChatMessage message, IProgress<double>? progress, CancellationToken token)
    {
        if (string.IsNullOrWhiteSpace(message.DownloadUrl)) throw new InvalidOperationException("Message has no download URL.");
        var extension = Path.GetExtension(message.FileName);
        if (string.IsNullOrWhiteSpace(extension)) extension = MimeExtension(message.MimeType);
        var destination = Path.Combine(paths.Media, message.Id + extension);
        if (File.Exists(destination)) return destination;

        var temporary = destination + ".download";
        using var response = await http.GetAsync(message.DownloadUrl, HttpCompletionOption.ResponseHeadersRead, token);
        response.EnsureSuccessStatusCode();
        var total = response.Content.Headers.ContentLength;
        await using var input = await response.Content.ReadAsStreamAsync(token);
        await using var output = File.Create(temporary);
        var buffer = new byte[81920];
        long readTotal = 0;
        int read;
        while ((read = await input.ReadAsync(buffer, token)) > 0)
        {
            await output.WriteAsync(buffer.AsMemory(0, read), token);
            readTotal += read;
            if (total > 0) progress?.Report((double)readTotal / total.Value);
        }
        File.Move(temporary, destination, true);
        return destination;
    }

    public void Cleanup(TimeSpan retention)
    {
        foreach (var file in Directory.EnumerateFiles(paths.Media))
            if (File.GetLastWriteTimeUtc(file) < DateTime.UtcNow.Subtract(retention)) File.Delete(file);
    }

    private static string MimeExtension(string? mime) => mime?.ToLowerInvariant() switch
    {
        "image/jpeg" => ".jpg", "image/png" => ".png", "image/webp" => ".webp",
        "video/mp4" => ".mp4", "video/quicktime" => ".mov", "video/webm" => ".webm",
        _ => ".bin"
    };
}

public sealed class ExportService(MediaCacheService media, AppPaths paths)
{
    public async Task<string> ExportCsvAsync(string displayName, IEnumerable<ChatMessage> messages, CancellationToken token)
    {
        var safe = string.Concat(displayName.Select(c => Path.GetInvalidFileNameChars().Contains(c) ? '_' : c));
        var path = Path.Combine(paths.Exports, $"{safe}_{DateTime.Now:yyyyMMdd_HHmmss}.csv");
        await using var writer = new StreamWriter(path, false, new UTF8Encoding(true));
        await writer.WriteLineAsync("Timestamp,Direction,Type,Text,FileName,DownloadUrl");
        foreach (var item in messages)
        {
            token.ThrowIfCancellationRequested();
            var fields = new[] { item.SentAt.ToString("O", CultureInfo.InvariantCulture), item.IsOutgoing ? "Outgoing" : "Incoming", item.Type, item.DisplayText, item.FileName ?? "", item.DownloadUrl ?? "" };
            await writer.WriteLineAsync(string.Join(',', fields.Select(Csv)));
        }
        return path;
    }

    public async Task<IReadOnlyList<string>> ExportMediaAsync(IEnumerable<ChatMessage> messages, IProgress<double>? progress, CancellationToken token)
    {
        var mediaMessages = messages.Where(x => !string.IsNullOrWhiteSpace(x.DownloadUrl)).ToArray();
        var files = new List<string>();
        for (var index = 0; index < mediaMessages.Length; index++)
        {
            files.Add(await media.DownloadAsync(mediaMessages[index], null, token));
            progress?.Report((index + 1d) / mediaMessages.Length);
        }
        return files;
    }

    private static string Csv(string value) => $"\"{value.Replace("\"", "\"\"")}\"";
}
