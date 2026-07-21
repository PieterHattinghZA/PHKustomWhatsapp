using System;
using System.Globalization;
using System.Net.Http;
using System.Threading.Tasks;
using Avalonia.Data.Converters;
using Avalonia.Media.Imaging;

namespace PHKustom.ChatClient.Services;

public class ImageLoaderConverter : IValueConverter
{
    public static readonly ImageLoaderConverter Instance = new();
    private static readonly HttpClient _http = new();

    public object? Convert(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        if (value is string url && !string.IsNullOrWhiteSpace(url))
        {
            return LoadImageAsync(url);
        }
        return null;
    }

    private async Task<Bitmap?> LoadImageAsync(string url)
    {
        try 
        {
            var response = await _http.GetAsync(url);
            using var stream = await response.Content.ReadAsStreamAsync();
            return new Bitmap(stream);
        } 
        catch 
        { 
            return null; 
        }
    }

    public object? ConvertBack(object? value, Type targetType, object? parameter, CultureInfo culture)
    {
        throw new NotImplementedException();
    }
}
