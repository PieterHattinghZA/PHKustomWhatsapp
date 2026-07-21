using System.Collections.ObjectModel;
using CommunityToolkit.Mvvm.ComponentModel;
using CommunityToolkit.Mvvm.Input;
using PHKustom.ChatClient.Models;
using PHKustom.ChatClient.Services;

namespace PHKustom.ChatClient.ViewModels;

public sealed partial class MainWindowViewModel(
    GreenApiClient api,
    ChatDatabase database,
    MediaCacheService media,
    ExportService exports) : ObservableObject
{
    public ObservableCollection<ChatSummary> Chats { get; } = [];
    public ObservableCollection<ChatMessage> Messages { get; } = [];

    [ObservableProperty] private ChatSummary? selectedChat;
    [ObservableProperty] private string searchText = string.Empty;
    [ObservableProperty] private string messageText = string.Empty;
    [ObservableProperty] private string status = "Ready";
    [ObservableProperty] private bool isBusy;
    [ObservableProperty] private double progress;

    public IEnumerable<ChatSummary> FilteredChats => Chats.Where(x =>
        string.IsNullOrWhiteSpace(SearchText) ||
        x.DisplayName.Contains(SearchText, StringComparison.OrdinalIgnoreCase) ||
        x.Id.Contains(SearchText, StringComparison.OrdinalIgnoreCase));

    partial void OnSearchTextChanged(string value) => OnPropertyChanged(nameof(FilteredChats));

    partial void OnSelectedChatChanged(ChatSummary? value)
    {
        if (value is not null) LoadSelectedChatCommand.Execute(null);
    }

    [RelayCommand]
    private async Task RefreshChatsAsync(CancellationToken token)
    {
        await RunAsync("Loading active chats...", async () =>
        {
            var chats = await api.GetChatsAsync(100, token);
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
        await RunAsync($"Loading {SelectedChat.DisplayName}...", async () =>
        {
            var history = await api.GetHistoryAsync(SelectedChat.Id, 100, token);
            await database.UpsertMessagesAsync(history, token);
            var existing = Messages.Select(x => x.Id).ToHashSet(StringComparer.Ordinal);
            if (Messages.Count == 0 || Messages.Any(x => x.ChatId != SelectedChat.Id)) Messages.Clear();
            existing = Messages.Select(x => x.Id).ToHashSet(StringComparer.Ordinal);
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
            await api.SendMessageAsync(SelectedChat.Id, text, token);
            MessageText = string.Empty;
            await LoadSelectedChatAsync(token);
        });
    }

    [RelayCommand]
    private async Task ExportCsvAsync(CancellationToken token)
    {
        if (SelectedChat is null) return;
        await RunAsync("Exporting CSV...", async () => Status = $"Exported: {await exports.ExportCsvAsync(SelectedChat.DisplayName, Messages, token)}");
    }

    [RelayCommand]
    private async Task ExportMediaAsync(CancellationToken token)
    {
        Progress = 0;
        var reporter = new Progress<double>(value => Progress = value * 100);
        await RunAsync("Exporting media...", async () => Status = $"Exported {(await exports.ExportMediaAsync(Messages, reporter, token)).Count} media files");
    }

    [RelayCommand]
    private void CleanupCache()
    {
        media.Cleanup(TimeSpan.FromDays(30));
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
