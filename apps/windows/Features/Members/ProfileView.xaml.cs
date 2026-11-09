using DiscordClone.Bridge;
using Microsoft.UI.Xaml.Controls;

namespace DiscordClone.Windows.Views;

public sealed partial class ProfileView : UserControl
{
    public ProfileView(User user)
    {
        InitializeComponent();
        Initials.Text = user.Initials;
        DisplayName.Text = user.DisplayName;
        Bio.Text = user.Bio;
        Kind.Text = App.ViewModel.IsConnected ? "Profil du serveur" : "Profil de démonstration";
    }
}
