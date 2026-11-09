using DiscordClone.Windows.ViewModels;
using Microsoft.UI.Xaml;

namespace DiscordClone.Windows;

public partial class App : Microsoft.UI.Xaml.Application
{
    // internal: the generated UniFFI records this model exposes are internal to the assembly.
    internal static AppViewModel ViewModel { get; private set; } = null!;

    public App() => InitializeComponent();

    protected override void OnLaunched(LaunchActivatedEventArgs args)
    {
        ViewModel = new AppViewModel(AppSettings.Load());
        var main = new MainWindow();
        main.Activate();
    }
}
