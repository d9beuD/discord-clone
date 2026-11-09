using System.ComponentModel;
using DiscordClone.Bridge;
using DiscordClone.Windows.Presentation;
using DiscordClone.Windows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace DiscordClone.Windows.Views;

public sealed partial class ChannelSidebarView : UserControl
{
    private readonly AppViewModel ViewModel = App.ViewModel;
    private bool _suppressSelection;

    public ChannelSidebarView()
    {
        InitializeComponent();
        ViewModel.PropertyChanged += OnModelChanged;
        Loaded += (_, _) =>
        {
            SyncHeader();
            RebuildChannels();
            SyncSelection();
            Footer.Text = ViewModel.StatusLabel;
        };
        SyncHeader();
        RebuildChannels();
        Footer.Text = ViewModel.StatusLabel;
    }

    private void OnModelChanged(object? sender, PropertyChangedEventArgs args)
    {
        switch (args.PropertyName)
        {
            case nameof(AppViewModel.Channels):
            case nameof(AppViewModel.Workspace):
                RebuildChannels();
                SyncSelection();
                break;
            case nameof(AppViewModel.SelectedChannelID):
                SyncSelection();
                break;
            case nameof(AppViewModel.SelectedServerID):
            case nameof(AppViewModel.Servers):
                SyncHeader();
                break;
            case nameof(AppViewModel.IsConnected):
            case nameof(AppViewModel.IsDemoOpen):
                Footer.Text = ViewModel.StatusLabel;
                break;
        }
    }

    private void SyncHeader() => ServerHeader.Text = ViewModel.SelectedServer?.Name ?? "Salons";

    private void RebuildChannels()
    {
        var secondary = Theme.Brush("TextFillColorSecondaryBrush");
        ChannelList.Items.Clear();
        foreach (var channel in ViewModel.Channels)
        {
            var row = new StackPanel { Orientation = Orientation.Horizontal, Spacing = 8 };
            if (ViewModel.IsVoiceChannel(channel.Id))
                row.Children.Add(new SymbolIcon { Symbol = Symbol.Volume });
            else
                row.Children.Add(new TextBlock { Text = "#", Foreground = secondary });
            row.Children.Add(new TextBlock { Text = channel.Name });
            row.Tag = channel.Id;
            ChannelList.Items.Add(row);
        }
    }

    private void SyncSelection()
    {
        var channels = ViewModel.Channels;
        int index = System.Array.FindIndex(channels, channel => channel.Id == ViewModel.SelectedChannelID);
        _suppressSelection = true;
        if (index >= 0 && ChannelList.SelectedIndex != index) ChannelList.SelectedIndex = index;
        else if (index < 0) ChannelList.SelectedItem = null;
        _suppressSelection = false;
    }

    private void OnSelectionChanged(object sender, SelectionChangedEventArgs e)
    {
        if (_suppressSelection) return;
        if (ChannelList.SelectedItem is FrameworkElement { Tag: string } row)
        {
            var id = (string)row.Tag;
            if (id != ViewModel.SelectedChannelID) ViewModel.SelectChannel(id);
        }
    }
}
