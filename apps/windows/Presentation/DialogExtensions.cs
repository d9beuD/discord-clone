using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;
using Microsoft.UI.Xaml.Media;

namespace DiscordClone.Windows.Presentation;

public static class DialogExtensions
{
    /// Closes the ContentDialog hosting this element, the sheet's dismiss equivalent on macOS.
    public static void HideHostDialog(this FrameworkElement element)
    {
        DependencyObject? node = element;
        try
        {
            while (node is not null)
            {
                if (node is ContentDialog dialog)
                {
                    dialog.Hide();
                    return;
                }

                node = VisualTreeHelper.GetParent(node);
            }
        }
        catch (ArgumentException)
        {
            // A non-visual ancestor ends the walk; the caller simply keeps its dialog open.
        }
    }

    /// Anchors a ContentDialog to the XamlRoot of an element that is already in the tree.
    /// Actions live inside the hosted view, the way the macOS sheets do.
    public static async Task<ContentDialogResult> ShowDialogAsync(
        this FrameworkElement anchor,
        UIElement content,
        string title,
        string closeText = "Fermer")
    {
        var root = anchor.XamlRoot;
        if (root is null) return ContentDialogResult.None;
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = title,
            Content = content,
            CloseButtonText = closeText,
            DefaultButton = ContentDialogButton.Close,
            MaxWidth = 760,
        };
        return await dialog.ShowAsync();
    }

    /// Destructive actions require confirmation, mirroring the macOS confirmationDialog.
    public static async Task<bool> ConfirmAsync(this FrameworkElement anchor, string message)
    {
        var root = anchor.XamlRoot;
        if (root is null) return false;
        var dialog = new ContentDialog
        {
            XamlRoot = root,
            Title = "Confirmer cette action",
            Content = new TextBlock { Text = message, TextWrapping = TextWrapping.Wrap },
            PrimaryButtonText = "Confirmer",
            CloseButtonText = "Annuler",
            DefaultButton = ContentDialogButton.Close,
        };
        return await dialog.ShowAsync() == ContentDialogResult.Primary;
    }
}
