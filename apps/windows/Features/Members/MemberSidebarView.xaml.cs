using System.ComponentModel;
using DiscordClone.Bridge;
using DiscordClone.Windows.Presentation;
using DiscordClone.Windows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DiscordClone.Windows.Views;

public sealed partial class MemberSidebarView : UserControl
{
    private readonly AppViewModel ViewModel = App.ViewModel;

    public MemberSidebarView()
    {
        InitializeComponent();
        ViewModel.PropertyChanged += OnModelChanged;
        Loaded += (_, _) => Refresh();
        Refresh();
    }

    private void OnModelChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName is nameof(AppViewModel.Members)
            or nameof(AppViewModel.IsConnected)
            or nameof(AppViewModel.SelectedChannelID))
            Refresh();
    }

    private void Refresh()
    {
        var members = ViewModel.Members;
        Count.Text = members.Length.ToString();
        if (ViewModel.IsConnected)
        {
            // The backend publishes no presence route, so the list makes no online/offline claim.
            OfflineSection.Visibility = Visibility.Collapsed;
            OnlineSection.Visibility = Visibility.Visible;
            OnlineHeader.Text = $"Membres — {members.Length}";
            OnlineList.ItemsSource = members;
            return;
        }

        OnlineSection.Visibility = Visibility.Visible;
        OfflineSection.Visibility = Visibility.Visible;
        var online = Array.FindAll(members, member => member.Online);
        var offline = Array.FindAll(members, member => !member.Online);
        OnlineHeader.Text = $"En ligne — {online.Length}";
        OfflineHeader.Text = $"Hors ligne — {offline.Length}";
        OnlineList.ItemsSource = online;
        OfflineList.ItemsSource = offline;
    }

    private void OnOpenMember(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: User user }) _ = this.ShowDialogAsync(new ProfileView(user), user.DisplayName);
    }
}
