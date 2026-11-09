using System.ComponentModel;
using DiscordClone.Windows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Input;
using Windows.System;

namespace DiscordClone.Windows.Views;

public sealed partial class WorkspaceView : UserControl
{
    private const double SidebarWidth = 280;
    private const double InspectorWidth = 260;

    private readonly AppViewModel _model = App.ViewModel;

    public WorkspaceView()
    {
        InitializeComponent();
        AddAccelerators();
        _model.PropertyChanged += OnModelChanged;
        Loaded += (_, _) => ApplyPanes();
        ApplyPanes();
    }

    /// The WinUI 3 markup compiler refuses comma-separated VirtualKeyModifiers text, so the
    /// Ctrl+Alt+S and Ctrl+Shift+M combinations from the macOS menu are assembled in code.
    /// Alt is spelled Menu: Windows.System.VirtualKeyModifiers has None/Control/Menu/Shift/Windows.
    private void AddAccelerators()
    {
        SidebarToggle.KeyboardAccelerators.Add(new KeyboardAccelerator
        {
            Key = VirtualKey.S,
            Modifiers = VirtualKeyModifiers.Control | VirtualKeyModifiers.Menu,
        });
        MembersToggle.KeyboardAccelerators.Add(new KeyboardAccelerator
        {
            Key = VirtualKey.M,
            Modifiers = VirtualKeyModifiers.Control | VirtualKeyModifiers.Shift,
        });
    }

    private void OnModelChanged(object? sender, PropertyChangedEventArgs args)
    {
        switch (args.PropertyName)
        {
            case nameof(AppViewModel.ShowSidebar):
            case nameof(AppViewModel.ShowMembers):
                ApplyPanes();
                break;
            case nameof(AppViewModel.IsConnected):
            case nameof(AppViewModel.IsDemoOpen):
                StatusLabel.Text = _model.IsSessionOpen ? _model.StatusLabel : "";
                break;
        }
    }

    // The AppKit split controller on macOS owns pane geometry; WinUI has no collapsing columns,
    // so widths and minimums are driven here instead of through bindings.
    private void ApplyPanes()
    {
        var sidebar = _model.ShowSidebar;
        SidebarColumn.MinWidth = sidebar ? 240 : 0;
        SidebarColumn.Width = new GridLength(sidebar ? SidebarWidth : 0);
        SidebarPane.Visibility = sidebar ? Visibility.Visible : Visibility.Collapsed;

        var members = _model.ShowMembers;
        InspectorColumn.MinWidth = members ? 220 : 0;
        InspectorColumn.Width = new GridLength(members ? InspectorWidth : 0);
        InspectorPane.Visibility = members ? Visibility.Visible : Visibility.Collapsed;

        SidebarToggle.Content = sidebar ? "Masquer la barre latérale" : "Afficher la barre latérale";
        MembersToggle.Content = members ? "Masquer les membres" : "Afficher les membres";
        StatusLabel.Text = _model.IsSessionOpen ? _model.StatusLabel : "";
    }

    private void OnToggleSidebar(object sender, RoutedEventArgs e) => _model.ShowSidebar = !_model.ShowSidebar;

    private void OnToggleMembers(object sender, RoutedEventArgs e) => _model.ShowMembers = !_model.ShowMembers;
}
