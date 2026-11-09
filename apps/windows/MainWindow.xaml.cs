using System.ComponentModel;
using DiscordClone.Windows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Input;
using Windows.Graphics;
using Windows.System;
using Windows.UI.Core;

namespace DiscordClone.Windows;

public sealed partial class MainWindow : Window
{
    private const int MinimumWidth = 900;
    private const int MinimumHeight = 600;

    private readonly AppViewModel _model = App.ViewModel;
    private bool _sizeConfigured;

    public MainWindow()
    {
        InitializeComponent();
        RootHost.RequestedTheme = _model.Settings.Theme;
        _model.Settings.AppearanceChanged += ApplyTheme;
        _model.PropertyChanged += OnModelChanged;
        // WinUI 3 exposes no native minimum window size, so the shell clamps every resize.
        AppWindow.Changed += (_, _) => ClampToMinimumSize();
        Activated += (_, _) =>
        {
            if (_sizeConfigured) return;
            _sizeConfigured = true;
            AppWindow.Resize(new SizeInt32(1280, 820));
        };
        RootHost.PreviewKeyDown += OnPreviewKeyDown;
        Closed += (_, _) =>
        {
            _model.PropertyChanged -= OnModelChanged;
            _model.Settings.AppearanceChanged -= ApplyTheme;
            // Window closure discards the in-memory token only; it never revokes remotely.
            _model.CloseSession();
        };
        ShowState();
    }

    private void OnModelChanged(object? sender, PropertyChangedEventArgs args)
    {
        if (args.PropertyName is nameof(AppViewModel.IsDemoOpen) or nameof(AppViewModel.IsConnected))
            ShowState();
    }

    private void ShowState()
    {
        var open = _model.IsSessionOpen;
        LoginPane.Visibility = open ? Visibility.Collapsed : Visibility.Visible;
        WorkspacePane.Visibility = open ? Visibility.Visible : Visibility.Collapsed;
    }

    private void ApplyTheme() => RootHost.RequestedTheme = _model.Settings.Theme;

    private void ClampToMinimumSize()
    {
        var size = AppWindow.Size;
        if (size.Width >= MinimumWidth && size.Height >= MinimumHeight) return;
        AppWindow.Resize(new SizeInt32(Math.Max(MinimumWidth, size.Width), Math.Max(MinimumHeight, size.Height)));
    }

    private void OnPreviewKeyDown(object sender, KeyRoutedEventArgs args)
    {
        if (!KeyDown(VirtualKey.Control)) return;

        int slot = args.Key switch
        {
            VirtualKey.Number1 or VirtualKey.NumberPad1 => 1,
            VirtualKey.Number2 or VirtualKey.NumberPad2 => 2,
            VirtualKey.Number3 or VirtualKey.NumberPad3 => 3,
            VirtualKey.Number4 or VirtualKey.NumberPad4 => 4,
            VirtualKey.Number5 or VirtualKey.NumberPad5 => 5,
            VirtualKey.Number6 or VirtualKey.NumberPad6 => 6,
            VirtualKey.Number7 or VirtualKey.NumberPad7 => 7,
            VirtualKey.Number8 or VirtualKey.NumberPad8 => 8,
            VirtualKey.Number9 or VirtualKey.NumberPad9 => 9,
            _ => 0,
        };
        if (slot == 0) return;
        if (slot <= _model.Servers.Length)
        {
            _model.SelectServer(_model.Servers[slot - 1].Id);
            args.Handled = true;
        }
        // No Ctrl+, for Settings: Windows.System.VirtualKey has no OEM punctuation members, so
        // macOS's comma shortcut has no equivalent. Settings is reachable from the rail gear.
    }

    private static bool KeyDown(VirtualKey key) =>
        Microsoft.UI.Input.InputKeyboardSource.GetKeyStateForCurrentThread(key).HasFlag(CoreVirtualKeyStates.Down);
}
