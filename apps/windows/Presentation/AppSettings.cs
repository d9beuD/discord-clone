using Microsoft.UI.Xaml;
using Microsoft.Windows.Storage;

namespace DiscordClone.Windows;

/// Only the appearance preference survives a session, mirroring the macOS app.
/// Windows App SDK 2.2+ gives unpackaged apps a first-class per-user store, so this no longer
/// hand-manages a file under LOCALAPPDATA (2.3.1 fixed its wrong registry path).
public sealed class AppSettings
{
    private const string Publisher = "d9beud";
    private const string Product = "DiscordClone";
    private const string AppearanceKey = "appearance";

    public string Appearance { get; private set; } = "system";

    public event Action? AppearanceChanged;

    private static ApplicationDataContainer Settings =>
        ApplicationData.GetForUnpackaged(Publisher, Product).LocalSettings;

    public static AppSettings Load()
    {
        var settings = new AppSettings();
        if (Settings.Values.TryGetValue(AppearanceKey, out var stored)
            && stored is string value && value is "light" or "dark")
            settings.Appearance = value;
        return settings;
    }

    public void SetAppearance(string value)
    {
        if (value is not ("system" or "light" or "dark") || value == Appearance) return;
        Appearance = value;
        AppearanceChanged?.Invoke();
        Settings.Values[AppearanceKey] = value;
    }

    public ElementTheme Theme => Appearance switch
    {
        "light" => ElementTheme.Light,
        "dark" => ElementTheme.Dark,
        _ => ElementTheme.Auto,
    };
}
