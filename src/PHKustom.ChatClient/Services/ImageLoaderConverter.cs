using System;
using System.Collections.Concurrent;
using System.Globalization;
using System.IO;
using System.Net.Http;
using System.Threading.Tasks;
using Avalonia.Data.Converters;
using Avalonia.Media.Imaging;
using Avalonia.Threading;

namespace PHKustom.ChatClient.Services;

public class ImageLoaderConverter : IValueConverter
{
    public static readonly ImageLoaderConverter Instance = new();
    private static readonly HttpClient _http = new();
    private static readonly ConcurrentDictionary<string, Bitmap> _cache = new();
    private static readonly ConcurrentDictionary<string, bool> _loading = new();

    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is not string url || string.IsNullOrWhiteSpace(url))
            return null;

        if (_cache.TryGetValue(url, out var cached))
            return cached;

        if (File.Exists(url))
        {
            try
            {
                var bitmap = new Bitmap(url);
                _cache[url] = bitmap;
                return bitmap;
            }
            catch
            {
                return null;
            }
        }

        if (_loading.TryAdd(url, true))
        {
            _ = LoadAndCacheAsync(url);
        }

        return null;
    }

    private static async Task LoadAndCacheAsync(string url)
    {
        try
        {
            if (url.StartsWith("http://", StringComparison.OrdinalIgnoreCase) || url.StartsWith("https://", StringComparison.OrdinalIgnoreCase))
            {
                using var response = await _http.GetAsync(url);
                if (response.IsSuccessStatusCode)
                {
                    await using var stream = await response.Content.ReadAsStreamAsync();
                    using var ms = new MemoryStream();
                    await stream.CopyToAsync(ms);
                    ms.Position = 0;
                    var bitmap = new Bitmap(ms);
                    _cache[url] = bitmap;
                }
            }
        }
        catch { }
        finally
        {
            _loading.TryRemove(url, out _);
            Dispatcher.UIThread.Post(() => { }, DispatcherPriority.Background);
        }
    }

    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture) => throw new NotImplementedException();
}
