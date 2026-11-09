using System.ComponentModel;
using DiscordClone.Windows.Presentation;
using DiscordClone.Windows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DiscordClone.Windows.Views;

public sealed partial class JoinServerView : UserControl
{
    private readonly AppViewModel ViewModel = App.ViewModel;

    public JoinServerView()
    {
        InitializeComponent();
        ViewModel.PropertyChanged += OnModelChanged;
        Refresh();
    }

    private void OnModelChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName is nameof(AppViewModel.IsWorking) or nameof(AppViewModel.ErrorMessage)) Refresh();
    }

    private void OnChanged(object sender, TextChangedEventArgs e) => Refresh();

    private void Refresh()
    {
        var busy = ViewModel.IsWorking;
        Busy.IsActive = busy;
        CreateButton.IsEnabled = !busy && GuildName.Text.Length > 0;
        JoinButton.IsEnabled = !busy && InviteToken.Text.Length > 0;
        Error.Text = ViewModel.ErrorMessage ?? "";
        Error.Visibility = ViewModel.ErrorMessage is null ? Visibility.Collapsed : Visibility.Visible;
    }

    private async void OnCreate(object sender, RoutedEventArgs e)
    {
        if (await ViewModel.CreateGuildAsync(GuildName.Text)) this.HideHostDialog();
    }

    private async void OnJoin(object sender, RoutedEventArgs e)
    {
        if (await ViewModel.AcceptInviteAsync(InviteToken.Text))
        {
            InviteToken.Text = "";
            this.HideHostDialog();
        }
    }
}
