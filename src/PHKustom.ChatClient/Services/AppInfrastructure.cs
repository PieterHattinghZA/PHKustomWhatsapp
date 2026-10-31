using System.Runtime.InteropServices;
using System.Security.Cryptography;
using System.Text;
using System.Text.Json;
using PHKustom.ChatClient.Models;

namespace PHKustom.ChatClient.Services;

public sealed class AppPaths
{
    public string Root { get; } = Path.Combine(Environment.GetFolderPath(Environment.SpecialFolder.ApplicationData), "PHKustom", "ChatClient");
    public string Database => Path.Combine(Root, "chatclient.db");
    public string Configuration => Path.Combine(Root, "config.json");
    public string Media => Path.Combine(Root, "MediaCache");
    public string Exports => Path.Combine(Root, "Exports");

    public AppPaths()
    {
        Directory.CreateDirectory(Root);
        Directory.CreateDirectory(Media);
        Directory.CreateDirectory(Exports);
    }
}

public sealed class CredentialStore
{
    public string Protect(string value)
    {
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            return Convert.ToBase64String(Encoding.UTF8.GetBytes(value));
        var bytes = ProtectedData.Protect(Encoding.UTF8.GetBytes(value), null, DataProtectionScope.CurrentUser);
        return Convert.ToBase64String(bytes);
    }

    public string Unprotect(string value)
    {
        var bytes = Convert.FromBase64String(value);
        if (!RuntimeInformation.IsOSPlatform(OSPlatform.Windows))
            return Encoding.UTF8.GetString(bytes);
        return Encoding.UTF8.GetString(ProtectedData.Unprotect(bytes, null, DataProtectionScope.CurrentUser));
    }
}

public sealed class AppConfigurationService(AppPaths paths, CredentialStore credentials)
{
    private sealed record StoredOptions(string ApiUrl, string InstanceId, string ProtectedToken);

    public async Task<GreenApiOptions> LoadAsync(CancellationToken cancellationToken = default)
    {
        if (File.Exists(paths.Configuration))
        {
            await using var stream = File.OpenRead(paths.Configuration);
            var stored = await JsonSerializer.DeserializeAsync<StoredOptions>(stream, cancellationToken: cancellationToken)
                         ?? throw new InvalidDataException("Configuration file is invalid.");
            return new GreenApiOptions(stored.ApiUrl.TrimEnd('/'), stored.InstanceId, credentials.Unprotect(stored.ProtectedToken));
        }

        var apiUrl = Environment.GetEnvironmentVariable("GREEN_API_URL");
        var instance = Environment.GetEnvironmentVariable("GREEN_API_INSTANCE_ID");
        var token = Environment.GetEnvironmentVariable("GREEN_API_TOKEN");
        if (string.IsNullOrWhiteSpace(apiUrl) || string.IsNullOrWhiteSpace(instance) || string.IsNullOrWhiteSpace(token))
            throw new InvalidOperationException("Set GREEN_API_URL, GREEN_API_INSTANCE_ID and GREEN_API_TOKEN for first launch.");

        var options = new GreenApiOptions(apiUrl.TrimEnd('/'), instance, token);
        await SaveAsync(options, cancellationToken);
        return options;
    }

    public async Task SaveAsync(GreenApiOptions options, CancellationToken cancellationToken = default)
    {
        var stored = new StoredOptions(options.ApiUrl.TrimEnd('/'), options.InstanceId, credentials.Protect(options.ApiToken));
        await using var stream = File.Create(paths.Configuration);
        await JsonSerializer.SerializeAsync(stream, stored, new JsonSerializerOptions { WriteIndented = true }, cancellationToken);
    }
}
