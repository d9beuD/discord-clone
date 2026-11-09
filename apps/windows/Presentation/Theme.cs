using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Media;

namespace DiscordClone.Windows.Presentation;

internal static class Theme
{
    /// Microsoft.UI.Xaml.Application exposes no FindResource, so code-built visuals read theme
    /// resources through the application dictionary chain that {ThemeResource} walks at runtime.
    public static Brush Brush(string key) => (Brush)Application.Current.Resources[key];
}
