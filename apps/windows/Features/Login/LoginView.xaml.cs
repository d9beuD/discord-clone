using System.ComponentModel;
using DiscordClone.Windows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace DiscordClone.Windows.Views;

public sealed partial class LoginView : UserControl
{
    private const string LoginHint = "Connectez-vous au backend. La session reste en mémoire sur ce PC.";
    private const string RegisterHint = "Mot de passe de 15 à 128 caractères. La session reste en mémoire sur ce PC.";

    private readonly AppViewModel _model = App.ViewModel;

    public LoginView()
    {
        InitializeComponent();
        _model.PropertyChanged += OnModelChanged;
        Password.KeyDown += OnPasswordKeyDown;
        Refresh();
    }

    private bool CreatingAccount => ModeCreate.IsChecked == true;

    private void OnModeChanged(object sender, RoutedEventArgs e)
    {
        if (Username is null || Submit is null || Hint is null) return;
        Username.Visibility = CreatingAccount ? Visibility.Visible : Visibility.Collapsed;
        Submit.Content = CreatingAccount ? "Créer mon compte" : "Se connecter";
        Hint.Text = CreatingAccount ? RegisterHint : LoginHint;
    }

    private void OnPasswordKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key == VirtualKey.Enter)
        {
            e.Handled = true;
            Submit_Click();
        }
    }

    private void OnSubmit(object sender, RoutedEventArgs e) => Submit_Click();

    private async void Submit_Click()
    {
        var baseUrl = BaseUrl.Text;
        var email = Identifier.Text;
        var secret = Password.Password;
        var username = CreatingAccount ? Username.Text : null;
        // The typed secret leaves the field immediately, as in the macOS login form.
        Password.Password = "";
        await _model.AuthenticateAsync(baseUrl, email, secret, username);
    }

    private async void OnDemo(object sender, RoutedEventArgs e)
    {
        Identifier.Text = "";
        Password.Password = "";
        await _model.OpenDemoAsync();
    }

    private void OnModelChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName is not (nameof(AppViewModel.IsLoading)
            or nameof(AppViewModel.ErrorMessage)
            or nameof(AppViewModel.IsDemoOpen)
            or nameof(AppViewModel.IsConnected))) return;
        Refresh();
    }

    private void Refresh()
    {
        var busy = _model.IsLoading;
        Busy.IsActive = busy;
        Submit.IsEnabled = !busy
            && Identifier.Text.Length > 0
            && Password.Password.Length > 0
            && (!CreatingAccount || Username.Text.Length > 0);
        Demo.IsEnabled = !busy;
        Error.Text = _model.ErrorMessage ?? "";
        Error.Visibility = _model.ErrorMessage is null ? Visibility.Collapsed : Visibility.Visible;
    }
}
