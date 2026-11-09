using DiscordClone.Bridge;
using DiscordClone.Windows.Presentation;
using Microsoft.UI.Dispatching;

namespace DiscordClone.Windows.ViewModels;

/// Ports apps/macos/ViewModels/AppViewModel.swift.
/// Rust decides, this class only holds presentation state. Every UniFFI call that can block
/// runs on the thread pool, and results are applied only while their generation still matches.
internal sealed class AppViewModel : ObservableBase
{
    private readonly DispatcherQueue _queue = DispatcherQueue.GetForCurrentThread();
    private readonly Dictionary<string, string> _drafts = [];
    private readonly Dictionary<string, string> _lastChannelByServer = [];

    private ChatClient? _client;
    private BackendClient? _backend;
    private int _sessionGeneration;
    private int _navigationGeneration;
    private int _actionGeneration;
    private CancellationTokenSource? _navigation;

    private bool _isDemoOpen, _isConnected, _isWorking, _isLoading;
    private bool _showSidebar = true, _showMembers = true;
    private BackendWorkspace? _workspace;
    private ChannelAccess? _channelAccess;
    private Invite[] _invites = [];
    private ChannelOverride[] _overrides = [];
    private string? _createdInviteToken, _errorMessage, _selectedServerId, _selectedChannelId;
    private User? _currentUser, _profile;
    private Server[] _servers = [];
    private Channel[] _channels = [];
    private Message[] _messages = [];
    private Member[] _members = [];

    public AppViewModel(AppSettings settings) => Settings = settings;

    public AppSettings Settings { get; }

    public bool IsDemoOpen { get => _isDemoOpen; private set => Set(ref _isDemoOpen, value); }
    public bool IsConnected { get => _isConnected; private set => Set(ref _isConnected, value); }
    public bool IsWorking { get => _isWorking; private set => Set(ref _isWorking, value); }
    public bool IsLoading { get => _isLoading; private set => Set(ref _isLoading, value); }
    public bool IsSessionOpen => IsDemoOpen || IsConnected;
    public BackendWorkspace? Workspace { get => _workspace; private set => Set(ref _workspace, value); }
    public ChannelAccess? ChannelAccess { get => _channelAccess; private set => Set(ref _channelAccess, value); }
    public Invite[] Invites { get => _invites; private set => Set(ref _invites, value); }
    public ChannelOverride[] Overrides { get => _overrides; private set => Set(ref _overrides, value); }
    public string? CreatedInviteToken { get => _createdInviteToken; set => Set(ref _createdInviteToken, value); }
    public User? CurrentUser { get => _currentUser; private set => Set(ref _currentUser, value); }
    public User? Profile { get => _profile; set => Set(ref _profile, value); }
    public Server[] Servers { get => _servers; private set => Set(ref _servers, value); }
    public Channel[] Channels { get => _channels; private set => Set(ref _channels, value); }
    public Message[] Messages { get => _messages; private set => Set(ref _messages, value); }
    public Member[] Members { get => _members; private set => Set(ref _members, value); }
    public string? SelectedServerID { get => _selectedServerId; private set => Set(ref _selectedServerId, value); }
    public string? SelectedChannelID { get => _selectedChannelId; private set => Set(ref _selectedChannelId, value); }
    public string? ErrorMessage { get => _errorMessage; private set => Set(ref _errorMessage, value); }
    public bool ShowSidebar { get => _showSidebar; set => Set(ref _showSidebar, value); }
    public bool ShowMembers { get => _showMembers; set => Set(ref _showMembers, value); }

    public Server? SelectedServer => Array.Find(Servers, server => server.Id == SelectedServerID);
    public Channel? SelectedChannel => Array.Find(Channels, channel => channel.Id == SelectedChannelID);

    private ChannelKind KindOf(string channelId) =>
        Workspace?.RemoteChannels.FirstOrDefault(channel => channel.Id == channelId)?.Kind ?? ChannelKind.Text;

    public ChannelKind SelectedChannelKind => KindOf(SelectedChannelID ?? "");

    /// The Channel presentation record carries no kind, so the sidebar asks Rust's remote data.
    public bool IsVoiceChannel(string channelId) => KindOf(channelId) == ChannelKind.Voice;

    public string Draft
    {
        get => SelectedChannelID is { } id && _drafts.TryGetValue(id, out var draft) ? draft : "";
        set
        {
            if (SelectedChannelID is not { } id) return;
            _drafts[id] = value;
            Raise(nameof(Draft));
            Raise(nameof(CanSend));
        }
    }

    public bool CanSend => IsDemoOpen && SelectedChannelID is not null && Draft.Trim().Length > 0;

    public string StatusLabel => IsConnected ? "Connecté au backend" : "Conversations locales";

    // MARK: - demo session

    public async Task OpenDemoAsync()
    {
        if (IsLoading) return;
        CloseSession();
        IsLoading = true;
        ErrorMessage = null;
        int generation = _sessionGeneration;
        try
        {
            var client = await Task.Run(ChatClient.NewDemo);
            if (!StillCurrent(generation)) return;
            _client = client;
            CurrentUser = client.CurrentUser();

            // The relay captures the generation at subscription time so a replaced or cleared
            // listener cannot apply events from an abandoned session.
            int subscription = generation;
            client.SetEventListener(new EventRelay(_queue,
                payload => { if (subscription == _sessionGeneration) Apply(payload); }));

            Servers = await Task.Run(client.ListServers);
            if (!StillCurrent(generation)) return;
            if (Servers.Length > 0) SelectServer(Servers[0].Id);
            IsDemoOpen = true;
        }
        catch (Exception error)
        {
            if (!StillCurrent(generation)) return;
            CloseSession();
            ErrorMessage = Describe(error);
        }
        finally
        {
            if (StillCurrent(generation)) IsLoading = false;
        }
    }

    public void SelectServer(string id)
    {
        if (_backend is not null)
        {
            if (IsWorking) return;
            _navigationGeneration += 1;
            int request = _navigationGeneration;
            CancelNavigation();
            _navigation = StartNavigation(token => LoadWorkspaceAsync(id, request, token));
            return;
        }
        if (_client is not { } client) return;
        try
        {
            Channel[] next = client.ListChannels(id);
            SelectedServerID = id;
            Channels = next;
            SelectedChannelID = null;
            Messages = [];
            Members = [];
            ErrorMessage = null;
            var remembered = next.FirstOrDefault(channel => channel.Id == LastChannel(id)) ?? next.FirstOrDefault();
            if (remembered is not null) SelectChannel(remembered.Id);
        }
        catch (Exception error)
        {
            ErrorMessage = Describe(error);
        }
    }

    public void SelectChannel(string id)
    {
        if (_backend is { } backend)
        {
            if (IsWorking || !Channels.Any(channel => channel.Id == id)) return;
            _navigationGeneration += 1;
            int request = _navigationGeneration;
            int generation = _sessionGeneration;
            // Hide old controls immediately while the next channel's permissions load.
            SelectedChannelID = id;
            ChannelAccess = null;
            Overrides = [];
            RememberChannel(id);
            CancelNavigation();
            _navigation = StartNavigation(async token =>
            {
                try
                {
                    var access = await Task.Run(() => backend.ChannelAccess(id), token);
                    if (!Applies(generation, request, token)) return;
                    ChannelAccess = access;
                    ErrorMessage = null;
                }
                catch (Exception error)
                {
                    if (!Applies(generation, request, token)) return;
                    HandleBackendError(error);
                }
            });
            return;
        }
        if (_client is not { } client) return;
        try
        {
            Message[] nextMessages = client.ListMessages(id);
            Member[] nextMembers = client.ListMembers(id);
            SelectedChannelID = id;
            RememberChannel(id);
            Messages = nextMessages;
            Members = nextMembers;
            ErrorMessage = null;
        }
        catch (Exception error)
        {
            ErrorMessage = Describe(error);
        }
    }

    public void SendMessage()
    {
        if (_client is not { } client || SelectedChannelID is not { } channelId || !CanSend) return;
        try
        {
            var message = client.SendMessage(channelId, Draft);
            Upsert(message);
            _drafts[channelId] = "";
            Raise(nameof(Draft));
            Raise(nameof(CanSend));
            ErrorMessage = null;
        }
        catch (Exception error)
        {
            ErrorMessage = Describe(error);
        }
    }

    public void DeleteMessage(Message message)
    {
        if (_client is not { } client) return;
        try
        {
            client.DeleteMessage(message.ChannelId, message.Id);
            Messages = Array.FindAll(Messages, existing => existing.Id != message.Id);
            ErrorMessage = null;
        }
        catch (Exception error)
        {
            ErrorMessage = Describe(error);
        }
    }

    public void Retry()
    {
        ErrorMessage = null;
        if (_backend is not null) _ = RefreshBackendAsync();
        else if (SelectedChannelID is { } id) SelectChannel(id);
    }

    public void Apply(ChatEvent chatEvent)
    {
        switch (chatEvent)
        {
            case ChatEvent.MessageReceived received:
                if (received.Message.ChannelId == SelectedChannelID) Upsert(received.Message);
                break;
            case ChatEvent.MessageDeleted deleted:
                if (deleted.ChannelId == SelectedChannelID)
                    Messages = Array.FindAll(Messages, existing => existing.Id != deleted.MessageId);
                break;
            case ChatEvent.UserTyping:
                // The memory-only demo emits no typing traffic; the contract still allows it.
                break;
        }
    }

    private void Upsert(Message message)
    {
        int index = Array.FindIndex(Messages, existing => existing.Id == message.Id);
        var next = (Message[])Messages.Clone();
        if (index >= 0) next[index] = message;
        else
        {
            Array.Resize(ref next, next.Length + 1);
            next[^1] = message;
        }
        Messages = next;
    }

    public void CloseSession()
    {
        IsLoading = false;
        _sessionGeneration += 1;
        _navigationGeneration += 1;
        _actionGeneration += 1;
        CancelNavigation();

        _backend?.Close();
        _backend?.Dispose();
        _backend = null;
        IsConnected = false;
        IsWorking = false;
        Workspace = null;
        ChannelAccess = null;
        Invites = [];
        Overrides = [];
        CreatedInviteToken = null;

        if (_client is { } client)
        {
            try { client.ClearEventListener(); }
            catch (Exception) { }
            client.Close();
            client.Dispose();
        }
        _client = null;
        IsDemoOpen = false;
        CurrentUser = null;
        Servers = [];
        Channels = [];
        Messages = [];
        Members = [];
        SelectedServerID = null;
        SelectedChannelID = null;
        _drafts.Clear();
        _lastChannelByServer.Clear();
        Profile = null;
        ErrorMessage = null;
    }

    // MARK: - backend session

    public async Task AuthenticateAsync(string baseUrl, string email, string password, string? username)
    {
        if (IsLoading) return;
        CloseSession();
        IsLoading = true;
        ErrorMessage = null;
        int generation = _sessionGeneration;

        BackendClient client;
        try
        {
            client = await Task.Run(() => username is null
                ? BackendClient.Login(baseUrl, email, password)
                : BackendClient.Register(baseUrl, username, email, password));
        }
        catch (Exception error)
        {
            if (StillCurrent(generation))
            {
                HandleBackendError(error);
                IsLoading = false;
            }
            return;
        }

        if (!StillCurrent(generation))
        {
            // The session exists remotely but the UI already moved on: revoke it off the UI thread.
            var abandoned = client;
            _ = Task.Run(() => { try { abandoned.Logout(); } catch (Exception) { } });
            return;
        }

        _backend = client;
        CurrentUser = client.CurrentUser();
        IsConnected = true;
        IsLoading = false;
        await RefreshBackendAsync();
    }

    public async Task RefreshBackendAsync(string? preferredServerId = null)
    {
        if (_backend is not { } backend) return;
        _navigationGeneration += 1;
        int request = _navigationGeneration;
        int generation = _sessionGeneration;
        try
        {
            var next = await Task.Run(() => backend.ListServers());
            if (!StillCurrent(generation) || request != _navigationGeneration) return;
            Servers = next;
            var target = next.FirstOrDefault(server => server.Id == (preferredServerId ?? SelectedServerID))
                ?? next.FirstOrDefault();
            if (target is not null) await LoadWorkspaceAsync(target.Id, request, CancellationToken.None);
            else
            {
                ClearWorkspace();
                ErrorMessage = null;
            }
        }
        catch (Exception error)
        {
            if (!StillCurrent(generation) || request != _navigationGeneration) return;
            HandleBackendError(error);
        }
    }

    /// Mutations never add or remove servers, so reload only the selected workspace.
    public async Task RefreshWorkspaceAsync(string? preferredServerId = null)
    {
        string? id = preferredServerId ?? SelectedServerID;
        if (_backend is null || id is null)
        {
            await RefreshBackendAsync();
            return;
        }
        _navigationGeneration += 1;
        await LoadWorkspaceAsync(id, _navigationGeneration, CancellationToken.None);
    }

    private async Task LoadWorkspaceAsync(string id, int request, CancellationToken token)
    {
        if (_backend is not { } backend) return;
        int generation = _sessionGeneration;
        ClearWorkspace();
        try
        {
            var next = await Task.Run(() => backend.Workspace(id), token);
            if (!Applies(generation, request, token)) return;
            Workspace = next;
            SelectedServerID = id;
            Channels = next.Channels;
            Members = next.Members;
            var first = next.Channels.FirstOrDefault(channel => channel.Id == LastChannel(id))
                ?? next.Channels.FirstOrDefault();
            SelectedChannelID = first?.Id;
            if (first is null)
            {
                ErrorMessage = null;
                return;
            }
            RememberChannel(first.Id);
            ErrorMessage = null;
            var access = await Task.Run(() => backend.ChannelAccess(first.Id), token);
            if (!Applies(generation, request, token)) return;
            ChannelAccess = access;
        }
        catch (Exception error)
        {
            if (!Applies(generation, request, token)) return;
            HandleBackendError(error);
        }
    }

    private void ClearWorkspace()
    {
        Workspace = null;
        Channels = [];
        Members = [];
        Messages = [];
        SelectedServerID = null;
        SelectedChannelID = null;
        ChannelAccess = null;
        Invites = [];
        Overrides = [];
        CreatedInviteToken = null;
    }

    /// The UI passes an intent; Rust validates, authorizes and performs it.
    public Task<bool> PerformBackendAsync(Action<BackendClient> operation) =>
        PerformActionAsync(client =>
        {
            operation(client);
            return true;
        }, _ => Task.CompletedTask);

    public async Task<bool> PerformActionAsync<T>(Func<BackendClient, T> operation, Func<T, Task> onSuccess)
    {
        if (_backend is not { } backend || IsWorking) return false;
        IsWorking = true;
        int generation = _sessionGeneration;
        _actionGeneration += 1;
        int action = _actionGeneration;
        try
        {
            var result = await Task.Run(() => operation(backend));
            if (!StillCurrent(generation)) return false;
            ErrorMessage = null;
            await onSuccess(result);
            return StillCurrent(generation) && ErrorMessage is null;
        }
        catch (Exception error)
        {
            if (!StillCurrent(generation)) return false;
            HandleBackendError(error);
            return false;
        }
        finally
        {
            if (action == _actionGeneration) IsWorking = false;
        }
    }

    public Task<bool> CreateGuildAsync(string name) => RunAndSelectCreatedGuild(client => client.CreateGuild(name));

    public Task<bool> AcceptInviteAsync(string token) => RunAndSelectCreatedGuild(client => client.AcceptInvite(token));

    private async Task<bool> RunAndSelectCreatedGuild(Func<BackendClient, Guild> operation)
    {
        string? createdId = null;
        bool done = await PerformActionAsync(operation, guild =>
        {
            createdId = guild.Id;
            return Task.CompletedTask;
        });
        if (done) await RefreshBackendAsync(createdId);
        return done;
    }

    public async Task LoadInvitesAsync()
    {
        if (_backend is not { } backend || SelectedServerID is not { } id) return;
        int generation = _sessionGeneration;
        int request = _navigationGeneration;
        try
        {
            var next = await Task.Run(() => backend.ListInvites(id));
            if (!StillCurrent(generation) || request != _navigationGeneration) return;
            Invites = next;
        }
        catch (Exception error)
        {
            if (!StillCurrent(generation) || request != _navigationGeneration) return;
            HandleBackendError(error);
        }
    }

    /// No workspace refresh: reloading the workspace would clear the freshly created token.
    public async Task CreateInviteAsync(long expiresInSeconds, long? maxUses)
    {
        if (SelectedServerID is not { } id) return;
        await PerformActionAsync(
            client => client.CreateInvite(id, expiresInSeconds, maxUses),
            async created =>
            {
                CreatedInviteToken = created.Token;
                await LoadInvitesAsync();
            });
    }

    public async Task<ChannelAccess?> AccessForChannelAsync(string id)
    {
        if (_backend is not { } backend) return null;
        int generation = _sessionGeneration;
        try
        {
            var access = await Task.Run(() => backend.ChannelAccess(id));
            return StillCurrent(generation) ? access : null;
        }
        catch (Exception error)
        {
            if (StillCurrent(generation)) HandleBackendError(error);
            return null;
        }
    }

    public async Task LoadOverridesAsync()
    {
        if (_backend is not { } backend || SelectedChannelID is not { } id) return;
        if (ChannelAccess?.CanManageRoles is not true) return;
        int generation = _sessionGeneration;
        int request = _navigationGeneration;
        try
        {
            var next = await Task.Run(() => backend.ListOverrides(id));
            if (!StillCurrent(generation) || request != _navigationGeneration) return;
            Overrides = next;
        }
        catch (Exception error)
        {
            if (!StillCurrent(generation) || request != _navigationGeneration) return;
            HandleBackendError(error);
        }
    }

    public async Task LogoutAsync()
    {
        var backend = _backend;
        if (backend is null)
        {
            CloseSession();
            return;
        }
        // Local state drops immediately; remote revocation stays off the UI thread.
        _backend = null;
        CloseSession();
        int generation = _sessionGeneration;
        IsLoading = true;
        try
        {
            await Task.Run(backend.Logout);
        }
        catch (Exception error)
        {
            if (!StillCurrent(generation)) return;
            ErrorMessage = "Session locale fermée ; révocation distante non confirmée. " + DescribeBackend(error);
        }
        finally
        {
            backend.Dispose();
            if (StillCurrent(generation)) IsLoading = false;
        }
    }

    // MARK: - plumbing

    private bool StillCurrent(int generation) => generation == _sessionGeneration;

    private bool Applies(int generation, int request, CancellationToken token) =>
        StillCurrent(generation) && request == _navigationGeneration && !token.IsCancellationRequested;

    private void RememberChannel(string id)
    {
        if (SelectedServerID is { } server) _lastChannelByServer[server] = id;
    }

    private string? LastChannel(string serverId) =>
        _lastChannelByServer.TryGetValue(serverId, out var id) ? id : null;

    private void CancelNavigation()
    {
        _navigation?.Cancel();
        _navigation?.Dispose();
        _navigation = null;
    }

    private CancellationTokenSource StartNavigation(Func<CancellationToken, Task> work)
    {
        var source = new CancellationTokenSource();
        _ = RunAsync();
        return source;

        async Task RunAsync()
        {
            try { await work(source.Token); }
            catch (OperationCanceledException) { }
        }
    }

    private void HandleBackendError(Exception error)
    {
        var description = DescribeBackend(error);
        switch (error)
        {
            case BackendException.Http http when http.status == 401:
            case BackendException.SessionClosed:
                CloseSession();
                IsLoading = false;
                break;
        }
        ErrorMessage = description;
    }

    internal static string DescribeBackend(Exception error) => error switch
    {
        BackendException.Http http => http.detail,
        BackendException.InvalidInput invalid => invalid.detail,
        BackendException.Transport => "Le serveur est inaccessible. Vérifiez son adresse et votre connexion.",
        BackendException.InvalidResponse => "La réponse du serveur est invalide.",
        BackendException.SessionClosed => "Votre session a expiré. Reconnectez-vous.",
        _ => "Impossible de terminer cette action. Réessayez.",
    };

    internal static string Describe(Exception error) => error switch
    {
        ChatException.EmptyContent => "Écrivez un message avant de l’envoyer.",
        ChatException.DeletionForbidden => "Vous pouvez supprimer uniquement vos propres messages.",
        ChatException.UnknownIdentifier => "Ce salon ou ce message est introuvable.",
        ChatException.SessionClosed => "La session est fermée. Rouvrez la démonstration.",
        ChatException => "Une erreur interne est survenue. Réessayez.",
        _ => "Impossible de terminer cette action. Réessayez.",
    };
}
