using System.ComponentModel;
using DiscordClone.Bridge;
using DiscordClone.Windows.Presentation;
using DiscordClone.Windows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DiscordClone.Windows.Views;

public sealed partial class ServerRailView : UserControl
{
    private readonly AppViewModel ViewModel = App.ViewModel;
    private bool _suppressSelection;

    public ServerRailView()
    {
        InitializeComponent();
        ViewModel.PropertyChanged += OnModelChanged;
        Loaded += (_, _) => SyncSelection();
        Refresh();
    }

    private void OnModelChanged(object? sender, PropertyChangedEventArgs args)
    {
        switch (args.PropertyName)
        {
            case nameof(AppViewModel.Servers):
            case nameof(AppViewModel.SelectedServerID):
                SyncSelection();
                break;
            case nameof(AppViewModel.IsConnected):
            case nameof(AppViewModel.CurrentUser):
                Refresh();
                break;
        }
    }

    private void Refresh()
    {
        AddServer.Visibility = ViewModel.IsConnected ? Visibility.Visible : Visibility.Collapsed;
        var user = ViewModel.CurrentUser;
        ProfileButton.Visibility = user is null ? Visibility.Collapsed : Visibility.Visible;
        if (user is not null) ProfileInitials.Text = user.Initials;
    }

    private void SyncSelection()
    {
        var servers = ViewModel.Servers;
        int index = Array.FindIndex(servers, server => server.Id == ViewModel.SelectedServerID);
        _suppressSelection = true;
        if (index >= 0 && ServerList.SelectedIndex != index) ServerList.SelectedIndex = index;
        _suppressSelection = false;
    }

    private void OnSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressSelection) return;
        if (ServerList.SelectedItem is Server server && server.Id != ViewModel.SelectedServerID)
            ViewModel.SelectServer(server.Id);
    }

    private async void OnAddServer(object sender, RoutedEventArgs e) =>
        await this.ShowDialogAsync(new JoinServerView(), "Créer ou rejoindre un serveur");

    private async void OnOpenProfile(object sender, RoutedEventArgs e)
    {
        if (ViewModel.CurrentUser is { } user)
            await this.ShowDialogAsync(new ProfileView(user), "Votre profil");
    }
}
