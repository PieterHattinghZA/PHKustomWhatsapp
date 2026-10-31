using Avalonia.Controls;
using Avalonia.Markup.Xaml;

namespace PHKustom.ChatClient.Views;

public sealed partial class MainWindow : Window
{
    public MainWindow() => AvaloniaXamlLoader.Load(this);
}
