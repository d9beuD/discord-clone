using System.ComponentModel;
using System.Globalization;
using DiscordClone.Bridge;
using DiscordClone.Windows.Presentation;
using DiscordClone.Windows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Microsoft.UI.Xaml.Media;
using Windows.ApplicationModel.DataTransfer;
using Windows.System;
using Windows.UI;
using Windows.UI.Core;

namespace DiscordClone.Windows.Views;

public sealed partial class ChatView : UserControl
{
    private const string RemoteNotice =
        "Le backend connecté ne propose pas encore les conversations ni les appels. Vous pouvez gérer ce salon et ses permissions.";

    private static readonly CultureInfo Fr = new("fr-FR");

    private readonly AppViewModel ViewModel = App.ViewModel;
    private bool _suppressDraft;

    public ChatView()
    {
        InitializeComponent();
        ViewModel.PropertyChanged += OnModelChanged;
        Loaded += (_, _) =>
        {
            Refresh();
            RebuildMessages();
            RestoreDraft();
            ScrollToBottom();
        };
        Refresh();
        RebuildMessages();
    }

    private void OnModelChanged(object? sender, PropertyChangedEventArgs args)
    {
        switch (args.PropertyName)
        {
            case nameof(AppViewModel.Messages):
                RebuildMessages();
                RefreshChannel();
                ScrollToBottom();
                break;
            case nameof(AppViewModel.SelectedChannelID):
                RefreshChannel();
                RestoreDraft();
                ScrollToBottom();
                break;
            case nameof(AppViewModel.SelectedServerID):
            case nameof(AppViewModel.Servers):
                ConnectionServer.Text = ViewModel.SelectedServer?.Name ?? "Vos serveurs";
                break;
            case nameof(AppViewModel.IsConnected):
            case nameof(AppViewModel.IsDemoOpen):
            case nameof(AppViewModel.Workspace):
                Refresh();
                break;
            case nameof(AppViewModel.ErrorMessage):
                RefreshErrors();
                break;
            case nameof(AppViewModel.CanSend):
                SendButton.IsEnabled = ViewModel.CanSend;
                break;
        }
    }

    private void Refresh()
    {
        ConnectionBar.Visibility = ViewModel.IsConnected ? Visibility.Visible : Visibility.Collapsed;
        ConnectionServer.Text = ViewModel.SelectedServer?.Name ?? "Vos serveurs";
        ManageButton.Visibility = ViewModel.Workspace is null ? Visibility.Collapsed : Visibility.Visible;
        RefreshButton.IsEnabled = !ViewModel.IsWorking;
        ManageButton.IsEnabled = !ViewModel.IsWorking;
        RefreshChannel();
        RefreshErrors();
    }

    private void RefreshChannel()
    {
        var channel = ViewModel.SelectedChannel;
        if (channel is null)
        {
            ChannelHeader.Visibility = Visibility.Collapsed;
            MessageList.Visibility = Visibility.Collapsed;
            Composer.Visibility = Visibility.Collapsed;
            EmptyState.Visibility = Visibility.Visible;
            EmptyTitle.Text = "Choisissez un salon";
            EmptyBody.Text = ViewModel.IsConnected
                ? "Créez ou rejoignez un serveur, puis choisissez un salon."
                : "Vos conversations apparaîtront ici.";
            return;
        }

        var voice = ViewModel.SelectedChannelKind == ChannelKind.Voice;
        ChannelHeader.Visibility = Visibility.Visible;
        // The text-channel marker is a literal hash; the voice marker is the icon font glyph.
        ChannelHash.Visibility = voice ? Visibility.Collapsed : Visibility.Visible;
        ChannelVolume.Visibility = voice ? Visibility.Visible : Visibility.Collapsed;
        ChannelName.Text = channel.Name;
        ChannelTopic.Text = channel.Topic;
        EmptyTitle.Text = voice ? "Salon vocal" : "Salon texte";

        if (ViewModel.IsConnected)
        {
            MessageList.Visibility = Visibility.Collapsed;
            Composer.Visibility = Visibility.Collapsed;
            EmptyBody.Text = RemoteNotice;
            EmptyState.Visibility = Visibility.Visible;
            return;
        }

        Composer.Visibility = Visibility.Visible;
        SendButton.IsEnabled = ViewModel.CanSend;
        if (MessageList.Items.Count == 0)
        {
            EmptyBody.Text = "Le début d’une nouvelle conversation. Envoyez le premier message.";
            EmptyState.Visibility = Visibility.Visible;
        }
        else
        {
            EmptyState.Visibility = Visibility.Collapsed;
        }

        MessageList.Visibility = Visibility.Visible;
    }

    private void RefreshErrors()
    {
        var message = ViewModel.ErrorMessage;
        BackendError.IsOpen = ViewModel.IsConnected && message is not null;
        BackendError.Message = message ?? "";
        DemoError.IsOpen = !ViewModel.IsConnected && message is not null && ViewModel.IsDemoOpen;
        DemoError.Message = message ?? "";
    }

    private void RebuildMessages()
    {
        MessageList.Items.Clear();
        foreach (var message in ViewModel.Messages) MessageList.Items.Add(MessageRow(message));
    }

    private UIElement MessageRow(Message message)
    {
        var avatar = new Grid { Width = 40, Height = 40 };
        avatar.Children.Add(new Ellipse
        {
            Fill = (Brush)Application.Current.FindResource("AccentFillColorDefaultBrush"),
        });
        avatar.Children.Add(new TextBlock
        {
            Text = message.Author.Initials,
            HorizontalAlignment = HorizontalAlignment.Center,
            VerticalAlignment = VerticalAlignment.Center,
            FontSize = 12,
            FontWeight = FontWeights.SemiBold,
            Foreground = (Brush)Application.Current.FindResource("TextOnAccentFillColorPrimaryBrush"),
        });

        var author = new Button
        {
            Padding = new Thickness(0),
            BorderThickness = new Thickness(0),
            Background = new SolidColorBrush(Colors.Transparent),
            Tag = message.Author,
            Content = avatar,
        };
        ToolTipService.SetToolTip(author, $"Profil de {message.Author.DisplayName}");
        author.Click += OnOpenAuthor;

        var header = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 10 };
        header.Children.Add(new TextBlock { Text = message.Author.DisplayName, FontWeight = FontWeights.SemiBold });
        header.Children.Add(new TextBlock
        {
            Text = Stamp(message.CreatedAtMs),
            FontSize = 11,
            VerticalAlignment = VerticalAlignment.Bottom,
            Foreground = (Brush)Application.Current.FindResource("TextFillColorSecondaryBrush"),
        });

        var column = new StackPanel { Spacing = 4, MaxWidth = 620 };
        column.Children.Add(header);
        column.Children.Add(new TextBlock
        {
            Text = message.Content,
            TextWrapping = TextWrapping.Wrap,
            IsTextSelectionEnabled = true,
        });

        var row = new StackPanel
        {
            Orientation = Orientation.Horizontal,
            Spacing = 12,
            Padding = new Thickness(0, 6, 0, 6),
        };
        row.Children.Add(author);
        row.Children.Add(column);

        var menu = new MenuFlyout();
        var copy = new MenuFlyoutItem { Text = "Copier le message" };
        copy.Click += (_, _) =>
        {
            var package = new DataPackage { RequestedOperation = DataPackageOperation.Copy };
            package.SetText(message.Content);
            Clipboard.SetContent(package);
        };
        menu.Items.Add(copy);
        if (message.Author.Id == ViewModel.CurrentUser?.Id)
        {
            var delete = new MenuFlyoutItem { Text = "Supprimer le message" };
            delete.Click += (_, _) => ViewModel.DeleteMessage(message);
            menu.Items.Add(delete);
        }

        FlyoutBase.SetContextFlyout(row, menu);
        return row;
    }

    private static string Stamp(ulong createdAtMs) =>
        DateTimeOffset.FromUnixTimeMilliseconds((long)createdAtMs).LocalDateTime.ToString("d MMM HH:mm", Fr);

    private void RestoreDraft()
    {
        _suppressDraft = true;
        Draft.Text = ViewModel.Draft;
        _suppressDraft = false;
    }

    private void OnDraftChanged(object sender, TextChangedEventArgs e)
    {
        if (_suppressDraft) return;
        ViewModel.Draft = Draft.Text;
    }

    private void OnDraftKeyDown(object sender, KeyRoutedEventArgs e)
    {
        if (e.Key != VirtualKey.Enter) return;
        var shift = Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(VirtualKey.Shift)
            .HasFlag(CoreVirtualKeyStates.Down);
        if (shift) return;
        e.Handled = true;
        ViewModel.SendMessage();
        RestoreDraft();
    }

    private void OnSend(object sender, RoutedEventArgs e)
    {
        ViewModel.SendMessage();
        RestoreDraft();
    }

    private void OnRetry(object sender, RoutedEventArgs e) => ViewModel.Retry();

    private async void OnRefresh(object sender, RoutedEventArgs e) => await ViewModel.RefreshBackendAsync();

    private async void OnManage(object sender, RoutedEventArgs e) =>
        await this.ShowDialogAsync(new CommunityManagementView(), ViewModel.SelectedServer?.Name ?? "Gestion du serveur");

    private void OnOpenAuthor(object sender, RoutedEventArgs e)
    {
        if (sender is Button { Tag: User user }) _ = this.ShowDialogAsync(new ProfileView(user), user.DisplayName);
    }

    private void ScrollToBottom()
    {
        if (MessageList.Items.Count == 0) return;
        MessageList.ScrollIntoView(MessageList.Items[^1]);
    }
}
