using Avalonia;
using Avalonia.Controls.ApplicationLifetimes;
using Avalonia.Markup.Xaml;
using Microsoft.Extensions.DependencyInjection;
using Microsoft.Extensions.Hosting;
using PHKustom.ChatClient.Services;
using PHKustom.ChatClient.ViewModels;
using PHKustom.ChatClient.Views;

namespace PHKustom.ChatClient;

public sealed partial class App : Application
{
    private IHost? _host;

    public override void Initialize() => AvaloniaXamlLoader.Load(this);

    public override void OnFrameworkInitializationCompleted()
    {
        _host = Host.CreateDefaultBuilder()
            .ConfigureServices(services =>
            {
                services.AddSingleton<AppPaths>();
                services.AddSingleton<CredentialStore>();
                services.AddSingleton<AppConfigurationService>();
                services.AddSingleton<ChatDatabase>();
                services.AddHttpClient<GreenApiClient>();
                services.AddSingleton<MediaCacheService>();
                services.AddSingleton<ExportService>();
                services.AddSingleton<MainWindowViewModel>();
            })
            .Build();

        _host.Start();
        _host.Services.GetRequiredService<ChatDatabase>().InitializeAsync().GetAwaiter().GetResult();

        if (ApplicationLifetime is IClassicDesktopStyleApplicationLifetime desktop)
        {
            desktop.MainWindow = new MainWindow
            {
                DataContext = _host.Services.GetRequiredService<MainWindowViewModel>()
            };
            desktop.Exit += (_, _) => _host.Dispose();
        }

        base.OnFrameworkInitializationCompleted();
    }
}
