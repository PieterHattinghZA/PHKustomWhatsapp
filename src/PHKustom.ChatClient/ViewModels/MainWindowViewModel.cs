using System.Collections.ObjectModel;
using Avalonia.Threading;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PHKustom.ChatClient.Models;
using PHKustom.ChatClient.Services;

namespace PHKustom.ChatClient.ViewModels;

public sealed partial class MainWindowViewModel : ObservableObject
{
    private readonly GreenApiClient _api;
    private readonly ChatDatabase _database;
    private readonly MediaCacheService _media;
    private readonly ExportService _exports;
    private readonly DispatcherTimer _pollTimer;

    public ObservableCollection<ChatSummary> Chats { get; } = [];
    public ObservableCollection<ChatMessage> Messages { get; } = [];

    [ObservableProperty] private ChatSummary? _selectedChat;
    [ObservableProperty] private string _searchText = string.Empty;
    [ObservableProperty] private string _messageText = string.Empty;
    [ObservableProperty] private string _status = "Ready";
    [ObservableProperty] private bool _isBusy;
    [ObservableProperty] private double _progress;

    public MainWindowViewModel(
        GreenApiClient api,
        ChatDatabase database,
        MediaCacheService media,
        ExportService exports)
    {
        _api = api;
        _database = database;
        _media = media;
        _exports = exports;

        _pollTimer = new DispatcherTimer { Interval = TimeSpan.FromSeconds(5) };
        _pollTimer.Tick += async (_, _) => await PollAsync();
        _pollTimer.Start();
    }

    public IEnumerable<ChatSummary> FilteredChats => Chats.Where(x =>
        string.IsNullOrWhiteSpace(SearchText) ||
        x.FormattedName.Contains(SearchText, StringComparison.OrdinalIgnoreCase) ||
        x.FormattedPhone.Contains(SearchText, StringComparison.OrdinalIgnoreCase) ||
        x.Id.Contains(SearchText, StringComparison.OrdinalIgnoreCase));

    partial void OnSearchTextChanged(string value) => OnPropertyChanged(nameof(FilteredChats));

    partial void OnSelectedChatChanged(ChatSummary? value)
    {
        if (value is not null) LoadSelectedChatCommand.Execute(null);
    }

    private async Task PollAsync()
    {
        if (SelectedChat is null || IsBusy) return;
        try
        {
            using var cts = new CancellationTokenSource(TimeSpan.FromSeconds(8));
            var history = await _api.GetHistoryAsync(SelectedChat.Id, 50, cts.Token);
            await _database.UpsertMessagesAsync(history, cts.Token);
            var existing = Messages.Select(x => x.Id).ToHashSet(StringComparer.Ordinal);
            foreach (var message in history.Where(x => !existing.Contains(x.Id)))
            {
                Messages.Add(message);
            }
        }
        catch { }
    }

    [RelayCommand]
    private async Task RefreshChatsAsync(CancellationToken token)
    {
        await RunAsync("Loading active chats...", async () =>
        {
            var chats = await _api.GetChatsAsync(100, token);
            Chats.Clear();
            foreach (var chat in chats) Chats.Add(chat);
            OnPropertyChanged(nameof(FilteredChats));
            Status = $"Loaded {Chats.Count} active chats";
        });
    }

    [RelayCommand]
    private async Task LoadSelectedChatAsync(CancellationToken token)
    {
        if (SelectedChat is null) return;
        await RunAsync($"Loading {SelectedChat.FormattedName}...", async () =>
        {
            var history = await _api.GetHistoryAsync(SelectedChat.Id, 100, token);
            await _database.UpsertMessagesAsync(history, token);
            if (Messages.Count == 0 || Messages.Any(x => x.ChatId != SelectedChat.Id)) Messages.Clear();
            var existing = Messages.Select(x => x.Id).ToHashSet(StringComparer.Ordinal);
            foreach (var message in history.Where(x => !existing.Contains(x.Id))) Messages.Add(message);
            Status = $"Showing {Messages.Count} messages";
        });
    }

    [RelayCommand]
    private async Task SendAsync(CancellationToken token)
    {
        if (SelectedChat is null || string.IsNullOrWhiteSpace(MessageText)) return;
        var text = MessageText.Trim();
        await RunAsync("Sending...", async () =>
        {
            await _api.SendMessageAsync(SelectedChat.Id, text, token);
            MessageText = string.Empty;
            await LoadSelectedChatAsync(token);
        });
    }

    [RelayCommand]
    private async Task DownloadMediaAsync(ChatMessage? message)
    {
        if (message is null || string.IsNullOrWhiteSpace(message.DownloadUrl)) return;
        try
        {
            Status = $"Downloading {message.FileName ?? "media"}...";
            var path = await _media.DownloadAsync(message, null, CancellationToken.None);
            Status = $"Saved to {path}";
        }
        catch (Exception ex)
        {
            Status = $"Download failed: {ex.Message}";
        }
    }

    [RelayCommand]
    private async Task ExportCsvAsync(CancellationToken token)
    {
        if (SelectedChat is null) return;
        await RunAsync("Exporting CSV...", async () => Status = $"Exported: {await _exports.ExportCsvAsync(SelectedChat.FormattedName, Messages, token)}");
    }

    [RelayCommand]
    private async Task ExportMediaAsync(CancellationToken token)
    {
        Progress = 0;
        var reporter = new System.Progress<double>(value => Progress = value * 100);
        await RunAsync("Exporting media...", async () => Status = $"Exported {(await _exports.ExportMediaAsync(Messages, reporter, token)).Count} media files");
    }

    [RelayCommand]
    private void CleanupCache()
    {
        _media.Cleanup(TimeSpan.FromDays(30));
        Status = "Media cache cleaned";
    }

    private async Task RunAsync(string status, Func<Task> action)
    {
        if (IsBusy) return;
        IsBusy = true;
        Status = status;
        try { await action(); }
        catch (OperationCanceledException) { Status = "Cancelled"; }
        catch (Exception ex) { Status = ex.Message; }
        finally { IsBusy = false; }
    }
}
