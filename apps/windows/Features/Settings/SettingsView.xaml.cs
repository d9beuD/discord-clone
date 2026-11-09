using DiscordClone.Windows.Presentation;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DiscordClone.Windows.Views;

public sealed partial class SettingsView : UserControl
{
    private readonly ViewModels.AppViewModel ViewModel = App.ViewModel;
    private bool _loaded;

    public SettingsView()
    {
        InitializeComponent();
        // Radio buttons raise Checked while initialising; _loaded keeps that from rewriting the choice.
        switch (ViewModel.Settings.Appearance)
        {
            case "light":
                ThemeLight.IsChecked = true;
                break;
            case "dark":
                ThemeDark.IsChecked = true;
                break;
            default:
                ThemeSystem.IsChecked = true;
                break;
        }

        _loaded = true;
        ProfileLine.Text = $"Profil : {ViewModel.CurrentUser?.DisplayName ?? "Non connecté"}";
        SessionLine.Text = "Session : " + (ViewModel.IsConnected
            ? "Backend"
            : ViewModel.IsDemoOpen ? "Démonstration locale" : "Aucune");
        LogoutButton.Visibility = ViewModel.IsSessionOpen ? Visibility.Visible : Visibility.Collapsed;
        LogoutButton.Content = ViewModel.IsConnected ? "Se déconnecter" : "Fermer la session démo";
    }

    private void OnThemeChanged(object sender, RoutedEventArgs e)
    {
        if (!_loaded) return;
        var choice = ThemeDark.IsChecked == true ? "dark" : ThemeLight.IsChecked == true ? "light" : "system";
        ViewModel.Settings.SetAppearance(choice);
    }

    private async void OnLogout(object sender, RoutedEventArgs e)
    {
        this.HideHostDialog();
        await ViewModel.LogoutAsync();
    }
}
