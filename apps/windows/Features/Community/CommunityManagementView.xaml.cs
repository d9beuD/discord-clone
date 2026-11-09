using System.ComponentModel;
using DiscordClone.Bridge;
using DiscordClone.Windows.Presentation;
using DiscordClone.Windows.ViewModels;
using Microsoft.UI.Xaml;
using Microsoft.UI.Xaml.Controls;

namespace DiscordClone.Windows.Views;

/// Ports apps/macos/Features/Community/CommunityManagementView.swift.
/// Rows are built in code because each one owns request-bound form state, the way the
/// SwiftUI disclosure rows do; Rust computes every capability flag below.
public sealed partial class CommunityManagementView : UserControl
{
    private static readonly (long Bit, string Label)[] Permissions =
    [
        (1, "Voir le salon"),
        (2, "Envoyer des messages"),
        (4, "Gérer les messages"),
        (8, "Gérer les salons"),
        (16, "Gérer les rôles"),
        (32, "Expulser des membres"),
        (64, "Bannir des membres"),
    ];

    private readonly AppViewModel ViewModel = App.ViewModel;

    public CommunityManagementView()
    {
        InitializeComponent();
        ViewModel.PropertyChanged += OnModelChanged;
        // Attached in code so the handler signature follows the delegate the SDK declares.
        Tabs.SelectionChanged += (_, _) => _ = LoadTabAsync();
        Build();
        _ = LoadTabAsync();
    }

    private void OnModelChanged(object? sender, PropertyChangedEventArgs args)
    {
        switch (args.PropertyName)
        {
            case nameof(AppViewModel.Workspace):
            case nameof(AppViewModel.IsWorking):
            case nameof(AppViewModel.Invites):
            case nameof(AppViewModel.Overrides):
            case nameof(AppViewModel.ChannelAccess):
            case nameof(AppViewModel.CreatedInviteToken):
                Build();
                break;
            case nameof(AppViewModel.ErrorMessage):
                Error.Text = ViewModel.ErrorMessage ?? "";
                Error.Visibility = ViewModel.ErrorMessage is null ? Visibility.Collapsed : Visibility.Visible;
                break;
        }
    }

    private void Build()
    {
        var workspace = ViewModel.Workspace;
        if (workspace is null)
        {
            ServerPanel.Children.Clear();
            ServerPanel.Children.Add(Secondary("Chargement du serveur…"));
            return;
        }

        BuildServer(workspace);
        BuildChannels(workspace);
        BuildMembers(workspace);
        BuildRoles(workspace);
        BuildInvites(workspace);
        BuildOverrides(workspace);
    }

    private async Task LoadTabAsync()
    {
        if (Tabs.SelectedIndex == 4 && ViewModel.Workspace?.CanManageChannels == true) await ViewModel.LoadInvitesAsync();
        if (Tabs.SelectedIndex == 5) await ViewModel.LoadOverridesAsync();
    }

    // MARK: - Serveur

    private void BuildServer(BackendWorkspace workspace)
    {
        var guild = workspace.Guild;
        ServerPanel.Children.Clear();
        ServerPanel.Children.Add(Selectable($"Identifiant : {guild.Id}"));
        if (workspace.IsOwner)
        {
            var name = new TextBox { Header = "Nom", Text = ViewModel.SelectedServer?.Name ?? guild.Name };
            ServerPanel.Children.Add(name);
            ServerPanel.Children.Add(Action("Renommer", () =>
                ViewModel.PerformBackendAsync(client => client.RenameGuild(guild.Id, name.Text))));
            ServerPanel.Children.Add(Action("Supprimer le serveur…", async () =>
            {
                if (!await this.ConfirmAsync(
                        "Supprimer ce serveur, ses salons, rôles et invitations ? Cette action est définitive.")) return;
                if (await ViewModel.PerformBackendAsync(client => client.DeleteGuild(guild.Id)))
                {
                    await ViewModel.RefreshBackendAsync();
                    this.HideHostDialog();
                }
            }));
        }
        else
        {
            ServerPanel.Children.Add(Action("Quitter le serveur…", async () =>
            {
                if (!await this.ConfirmAsync("Quitter ce serveur ? Une invitation sera nécessaire pour le rejoindre à nouveau."))
                    return;
                if (await ViewModel.PerformBackendAsync(client => client.LeaveGuild(guild.Id))) this.HideHostDialog();
            }));
        }
    }

    // MARK: - Salons

    private void BuildChannels(BackendWorkspace workspace)
    {
        ChannelPanel.Children.Clear();
        if (workspace.CanManageChannels)
        {
            var name = new TextBox { Header = "Nom" };
            var kind = new ComboBox { Header = "Type" };
            kind.Items.Add(new ComboBoxItem { Content = "Texte" });
            kind.Items.Add(new ComboBoxItem { Content = "Vocal" });
            kind.SelectedIndex = 0;
            ChannelPanel.Children.Add(name);
            ChannelPanel.Children.Add(kind);
            ChannelPanel.Children.Add(Action("Créer", async () =>
            {
                if (name.Text.Length == 0) return;
                var voice = kind.SelectedIndex == 1;
                if (await ViewModel.PerformBackendAsync(client => client.CreateChannel(
                        workspace.Guild.Id, name.Text, voice ? ChannelKind.Voice : ChannelKind.Text, 0)))
                    name.Text = "";
            }));
        }

        foreach (var channel in workspace.RemoteChannels) ChannelPanel.Children.Add(ChannelRow(channel, workspace));
        if (workspace.RemoteChannels.Length == 0) ChannelPanel.Children.Add(Secondary("Aucun salon visible."));
    }

    private Expander ChannelRow(RemoteChannel channel, BackendWorkspace workspace)
    {
        var body = new StackPanel { Spacing = 8 };
        body.Children.Add(Secondary(channel.Kind == ChannelKind.Voice ? "Salon vocal" : "Salon texte"));
        var editor = new StackPanel { Spacing = 8 };
        body.Children.Add(editor);
        var expander = new Expander { Header = channel.Name, Content = body };
        var loaded = false;
        expander.Expanded += async (_, _) =>
        {
            if (loaded) return;
            loaded = true;
            var access = await ViewModel.AccessForChannelAsync(channel.Id);
            if (access?.CanManageChannels is not true)
            {
                editor.Children.Add(Secondary("Vous ne pouvez pas gérer ce salon."));
                return;
            }

            var name = new TextBox { Header = "Nom", Text = channel.Name };
            var position = new NumberBox
            {
                Header = "Position",
                Minimum = 0,
                SmallChange = 1,
                LargeChange = 5,
                Value = channel.Position,
            };
            editor.Children.Add(name);
            editor.Children.Add(position);
            editor.Children.Add(Action("Enregistrer", () => ViewModel.PerformBackendAsync(client =>
            {
                var parsed = (int)WholeNumber(position.Value, channel.Position);
                client.UpdateChannel(channel.Id, name.Text, parsed);
            })));
            editor.Children.Add(Action("Supprimer le salon…", async () =>
            {
                if (!await this.ConfirmAsync($"Supprimer le salon {channel.Name} ? Cette action est définitive.")) return;
                await ViewModel.PerformBackendAsync(client => client.DeleteChannel(channel.Id));
            }));
        };
        return expander;
    }

    // MARK: - Membres

    private void BuildMembers(BackendWorkspace workspace)
    {
        MemberPanel.Children.Clear();
        foreach (var member in workspace.GuildMembers) MemberPanel.Children.Add(MemberRow(member, workspace));
    }

    private Expander MemberRow(GuildMember member, BackendWorkspace workspace)
    {
        var body = new StackPanel { Spacing = 6 };
        body.Children.Add(Selectable(member.UserId));
        if (workspace.CanManageRoles)
        {
            foreach (var role in workspace.Roles.Where(role => !role.IsDefault))
            {
                var assigned = member.RoleIds.Contains(role.Id);
                body.Children.Add(Action($"{(assigned ? "Retirer" : "Attribuer")} : {role.Name}", () =>
                    ViewModel.PerformBackendAsync(client => client.SetMemberRole(
                        workspace.Guild.Id, member.UserId, role.Id, !assigned))));
            }
        }

        var kickable = workspace.CanKickMembers
            && member.UserId != workspace.Guild.OwnerId
            && member.UserId != ViewModel.CurrentUser?.Id;
        if (kickable)
        {
            body.Children.Add(Action("Expulser…", async () =>
            {
                if (!await this.ConfirmAsync($"Expulser {member.Username} du serveur ?")) return;
                await ViewModel.PerformBackendAsync(client => client.KickMember(workspace.Guild.Id, member.UserId));
            }));
        }

        return new Expander { Header = member.Username, Content = body };
    }

    // MARK: - Rôles

    private void BuildRoles(BackendWorkspace workspace)
    {
        RolePanel.Children.Clear();
        if (workspace.CanManageRoles)
        {
            var name = new TextBox { Header = "Nom" };
            var permissions = new PermissionEditor(3, readOnly: false);
            RolePanel.Children.Add(name);
            RolePanel.Children.Add(permissions.View);
            RolePanel.Children.Add(Action("Créer", async () =>
            {
                if (name.Text.Length == 0) return;
                var mask = permissions.Value;
                if (await ViewModel.PerformBackendAsync(client => client.CreateRole(workspace.Guild.Id, name.Text, mask)))
                    name.Text = "";
            }));
        }

        foreach (var role in workspace.Roles) RolePanel.Children.Add(RoleRow(role, workspace));
    }

    private Expander RoleRow(Role role, BackendWorkspace workspace)
    {
        var body = new StackPanel { Spacing = 8 };
        TextBox? name = null;
        if (!role.IsDefault)
        {
            name = new TextBox { Header = "Nom", Text = role.Name, IsEnabled = workspace.CanManageRoles };
            body.Children.Add(name);
        }

        var permissions = new PermissionEditor(role.Permissions, readOnly: !workspace.CanManageRoles);
        body.Children.Add(permissions.View);
        if (workspace.CanManageRoles)
        {
            body.Children.Add(Action("Enregistrer", () => ViewModel.PerformBackendAsync(client =>
            {
                var updated = role.IsDefault ? null : name?.Text;
                client.UpdateRole(role.GuildId, role.Id, updated, permissions.Value);
            })));
            if (!role.IsDefault)
            {
                body.Children.Add(Action("Supprimer le rôle…", async () =>
                {
                    if (!await this.ConfirmAsync($"Supprimer le rôle {role.Name} et ses attributions ?")) return;
                    await ViewModel.PerformBackendAsync(client => client.DeleteRole(role.GuildId, role.Id));
                }));
            }
        }

        return new Expander { Header = role.Name, Content = body };
    }

    // MARK: - Invitations

    private void BuildInvites(BackendWorkspace workspace)
    {
        InvitePanel.Children.Clear();
        if (!workspace.CanManageChannels)
        {
            InvitePanel.Children.Add(Secondary("La gestion des invitations nécessite la permission de gérer les salons."));
            return;
        }

        var expiry = new NumberBox
        {
            Header = "Durée en secondes (1 à 604 800)",
            Minimum = 1,
            Maximum = 604_800,
            SmallChange = 1,
            Value = 86_400,
        };
        var unlimited = new ToggleSwitch { Header = "Utilisations illimitées", OffContent = "", OnContent = "" };
        var uses = new NumberBox
        {
            Header = "Utilisations maximales",
            Minimum = 1,
            Maximum = 1_000_000,
            SmallChange = 1,
            Value = 10,
        };
        InvitePanel.Children.Add(expiry);
        InvitePanel.Children.Add(unlimited);
        InvitePanel.Children.Add(uses);
        unlimited.Toggled += (_, _) => uses.Visibility = unlimited.IsOn ? Visibility.Collapsed : Visibility.Visible;
        InvitePanel.Children.Add(Action("Créer le code", () =>
        {
            long seconds = WholeNumber(expiry.Value, 86_400);
            long? max = unlimited.IsOn ? null : WholeNumber(uses.Value, 10);
            return ViewModel.CreateInviteAsync(seconds, max);
        }));

        if (ViewModel.CreatedInviteToken is { } token)
        {
            InvitePanel.Children.Add(Secondary("Copiez ce code : il ne pourra plus être relu après fermeture."));
            InvitePanel.Children.Add(Selectable(token));
            InvitePanel.Children.Add(Action("Copier le code", () =>
            {
                var package = new Windows.ApplicationModel.DataTransfer.DataPackage();
                package.SetText(token);
                Windows.ApplicationModel.DataTransfer.Clipboard.SetContent(package);
                return Task.CompletedTask;
            }));
        }

        foreach (var invite in ViewModel.Invites) InvitePanel.Children.Add(InviteRow(invite, workspace));
    }

    private Expander InviteRow(Invite invite, BackendWorkspace workspace)
    {
        var body = new StackPanel { Spacing = 6 };
        body.Children.Add(Selectable(invite.Id));
        body.Children.Add(Secondary($"{invite.Uses} utilisation(s) · expiration : {invite.ExpiresAt ?? "aucune"}"));
        if (invite.RevokedAt is null)
        {
            body.Children.Add(Action("Révoquer…", async () =>
            {
                if (!await this.ConfirmAsync("Révoquer cette invitation ? Son code cessera de fonctionner.")) return;
                await ViewModel.PerformBackendAsync(client => client.RevokeInvite(workspace.Guild.Id, invite.Id));
                await ViewModel.LoadInvitesAsync();
            }));
        }
        else
        {
            body.Children.Add(Secondary("Révoquée"));
        }

        return new Expander { Header = invite.Id, Content = body };
    }

    // MARK: - Permissions

    private void BuildOverrides(BackendWorkspace workspace)
    {
        OverridePanel.Children.Clear();
        OverridePanel.Children.Add(Secondary("Salon sélectionné"));
        OverridePanel.Children.Add(new TextBlock { Text = ViewModel.SelectedChannel?.Name ?? "Aucun salon" });

        var access = ViewModel.ChannelAccess;
        if (access is null)
        {
            OverridePanel.Children.Add(Secondary("Sélectionnez un salon pour charger ses permissions."));
            return;
        }

        OverridePanel.Children.Add(new PermissionEditor(access.Permissions, readOnly: true, title: "Vos droits effectifs").View);
        if (access.CanManageRoles is false) return;

        var channelId = ViewModel.SelectedChannelID;
        if (channelId is null) return;

        var targetMember = new ToggleSwitch { Header = "Cibler un membre", OffContent = "", OnContent = "" };
        var target = new ComboBox { Header = "Cible" };
        var allow = new PermissionEditor(0, readOnly: false, title: "Autoriser");
        var deny = new PermissionEditor(0, readOnly: false, title: "Refuser");
        void FillTargets()
        {
            target.Items.Clear();
            target.Items.Add(new ComboBoxItem { Content = "Choisir…", Tag = "" });
            if (targetMember.IsOn)
            {
                foreach (var member in workspace.GuildMembers)
                    target.Items.Add(new ComboBoxItem { Content = member.Username, Tag = member.UserId });
            }
            else
            {
                foreach (var role in workspace.Roles)
                    target.Items.Add(new ComboBoxItem { Content = role.Name, Tag = role.Id });
            }

            target.SelectedIndex = 0;
        }

        FillTargets();
        targetMember.Toggled += (_, _) => FillTargets();
        OverridePanel.Children.Add(targetMember);
        OverridePanel.Children.Add(target);
        OverridePanel.Children.Add(allow.View);
        OverridePanel.Children.Add(deny.View);
        OverridePanel.Children.Add(Action("Enregistrer l’exception", async () =>
        {
            var chosen = (target.SelectedItem as ComboBoxItem)?.Tag as string ?? "";
            if (chosen.Length == 0) return;
            var asMember = targetMember.IsOn;
            var allowed = allow.Value;
            var denied = deny.Value;
            await ViewModel.PerformBackendAsync(client => client.PutOverride(
                channelId,
                asMember ? null : chosen,
                asMember ? chosen : null,
                allowed,
                denied));
            await ViewModel.LoadOverridesAsync();
        }));

        foreach (var current in ViewModel.Overrides)
        {
            var row = new StackPanel { Spacing = 6 };
            row.Children.Add(new TextBlock { Text = TargetName(current, workspace) });
            row.Children.Add(new PermissionEditor(current.AllowPermissions, readOnly: true, title: "Autorisations").View);
            row.Children.Add(new PermissionEditor(current.DenyPermissions, readOnly: true, title: "Refus").View);
            row.Children.Add(Action("Retirer l’exception…", async () =>
            {
                if (!await this.ConfirmAsync("Retirer cette exception de permissions ?")) return;
                await ViewModel.PerformBackendAsync(client => client.DeleteOverride(channelId, current.Id));
                await ViewModel.LoadOverridesAsync();
            }));
            OverridePanel.Children.Add(new Expander { Header = TargetName(current, workspace), Content = row });
        }
    }

    private static string TargetName(ChannelOverride value, BackendWorkspace workspace)
    {
        if (value.RoleId is { } roleId)
            return workspace.Roles.FirstOrDefault(role => role.Id == roleId)?.Name ?? roleId;
        return workspace.GuildMembers.FirstOrDefault(member => member.UserId == value.MemberId)?.Username
            ?? value.MemberId
            ?? "Cible inconnue";
    }

    // MARK: - widgets

    /// A NumberBox yields NaN when its text is empty or unparsable, so every numeric field
    /// funnels through here instead of reading a raw value.
    private static long WholeNumber(double? value, long fallback) =>
        value is { } number && double.IsFinite(number) ? (long)Math.Round(number) : fallback;

    private Button Action(string text, Func<Task> run)
    {
        var button = new Button { Content = text, IsEnabled = !ViewModel.IsWorking };
        button.Click += async (_, _) =>
        {
            button.IsEnabled = false;
            try { await run(); }
            finally { button.IsEnabled = !ViewModel.IsWorking; }
        };
        return button;
    }

    private static TextBlock Secondary(string text) => new()
    {
        Text = text,
        FontSize = 12,
        TextWrapping = TextWrapping.Wrap,
        Foreground = (Microsoft.UI.Xaml.Media.Brush)Microsoft.UI.Xaml.Application.Current.FindResource(
            "TextFillColorSecondaryBrush"),
    };

    private static TextBlock Selectable(string text) => new()
    {
        Text = text,
        FontSize = 12,
        TextWrapping = TextWrapping.Wrap,
        IsTextSelectionEnabled = true,
    };

    private sealed class PermissionEditor
    {
        private readonly ToggleSwitch[] _switches;

        public PermissionEditor(long value, bool readOnly, string title = "Permissions")
        {
            var panel = new StackPanel { Spacing = 4 };
            _switches = new ToggleSwitch[Permissions.Length];
            for (int index = 0; index < Permissions.Length; index++)
            {
                var (bit, label) = Permissions[index];
                var toggle = new ToggleSwitch
                {
                    Header = label,
                    IsOn = (value & bit) != 0,
                    IsEnabled = !readOnly,
                    OffContent = "",
                    OnContent = "",
                };
                _switches[index] = toggle;
                panel.Children.Add(toggle);
            }

            View = new Expander { Header = title, Content = panel };
        }

        public Expander View { get; }

        public long Value
        {
            get
            {
                long mask = 0;
                for (int index = 0; index < _switches.Length; index++)
                    if (_switches[index].IsOn) mask |= Permissions[index].Bit;
                return mask;
            }
        }
    }
}
