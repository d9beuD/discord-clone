# Contrat Swift / C# ↔ Rust

UniFFI 0.32.2 génère `ChatBridge.swift` et le module C `ChatBridgeFFI` pour macOS, et `chat_bridge.cs` (namespace `DiscordClone.Bridge`) pour l’app WinUI 3 — un seul contrat, deux langages. La source générée est compilée dans le module applicatif `DiscordClone`. Les identifiants sont des chaînes opaques, jamais des indices de sélection ou pointeurs.

## Modèles

| Type | Champs |
| --- | --- |
| `Server` | `id`, `name`, `initials`, `description` |
| `Channel` | `id`, `serverId`, `name`, `topic` |
| `User` | `id`, `displayName`, `initials`, `bio` |
| `Member` | `user`, `role`, `online` |
| `Message` | `id`, `channelId`, `author`, `content`, `createdAtMs` |

Les records Swift sont immuables et `Sendable`. `createdAtMs` représente des millisecondes UTC depuis l’époque Unix. L’affichage utilise la locale et le fuseau macOS. Les messages de démonstration ont des identifiants `seed-*` ; les nouveaux messages ont des identifiants `local-*`, uniques dans une session.

## API cliente

```swift
let client = try ChatClient.newDemo()
try client.currentUser() -> User
try client.listServers() -> [Server]
try client.listChannels(serverId: String) -> [Channel]
try client.listMessages(channelId: String) -> [Message]
try client.listMembers(channelId: String) -> [Member]
try client.sendMessage(channelId: String, content: String) -> Message
try client.deleteMessage(channelId: String, messageId: String)
try client.setEventListener(listener: ChatEventListener)
try client.clearEventListener()
client.close()
```

Ces signatures décrivent l’usage ; elles ne forment pas un bloc Swift compilable. Tous les appels sauf `close` peuvent lever `ChatError`. `close` est idempotent ; les opérations suivantes lèvent `SessionClosed`. Un salon vide renvoie une liste vide, tandis qu’un identifiant inconnu lève une erreur. Un message ne contenant que des espaces Unicode est rejeté ; tout contenu valide conserve son texte original, ses espaces et ses nouvelles lignes.

`ChatError` expose les cas générés **`UnknownIdentifier(id:)`, `EmptyContent`, `DeletionForbidden`, `SessionClosed`, `Internal(reason:)`**. Le ViewModel les traduit en textes français. L’interface ne propose la suppression que pour l’utilisateur courant ; Rust vérifie indépendamment cette permission.

## Événements et abonnement

```swift
enum ChatEvent {
    case messageReceived(message: Message)
    case messageDeleted(channelId: String, messageId: String)
    case userTyping(channelId: String, userId: String)
}

protocol ChatEventListener: AnyObject, Sendable {
    func onEvent(event: ChatEvent) throws
}
```

Les déclarations ci-dessus résument le contrat généré. `UserTyping` est représentable mais n’est pas émis dans cette démo. Il n’y a qu’un listener actif par client ; le remplacer invalide l’abonnement précédent. Les événements sont livrés dans l’ordre des mutations depuis le worker Tokio, jamais directement depuis le thread UI. Ils ne constituent pas un journal persistant et ne sont pas rejoués : utiliser les getters pour charger les snapshots.

Le callback doit être court et sûr depuis plusieurs threads. `EventRelay` appelle uniquement `continuation.yield(event)` ; la consommation SwiftUI s’effectue sur `MainActor`. Un échec de callback est traduit en `EventDeliveryError` et ne provoque pas de panic FFI ni d’annulation d’une mutation déjà enregistrée.

Le cache est mis à jour avant publication. Le retour de `sendMessage` et `messageReceived` décrivent le même message : faire un upsert par identifiant. Un événement d’un autre salon ne doit pas modifier la liste affichée ; les getters restituent ce salon lorsqu’il est ensuite sélectionné.

À la fermeture : annuler la tâche Swift, terminer sa continuation, retirer le listener puis appeler `close`. Un callback déjà en cours peut finir après désabonnement ; un stream terminé rejette ces livraisons. Ne jamais créer un listener conservant fortement le client qui le possède.

## Évolution

Ce contrat est celui du cache local de la première version. Les endpoints, jetons, pagination, pièces jointes et états de synchronisation attendent l’OpenAPI et le protocole WebSocket. Les modèles métier ne portent pas de derives UniFFI : la crate `chat-bridge` les convertit une seule fois, et chaque langage n’ajoute que sa projection locale (Swift et C# consumant le même contrat).


## REST backend contract

`BackendClient.login(base_url, email, password)` and `.register(base_url, username, email, password)` create an independent remote session. Credentials enter Rust once; the bearer token never crosses the FFI boundary. Generated community records preserve IDs, channel kinds/positions, role masks, member assignments and invitation/override metadata. `workspace(guild_id)` also returns existing `Server`/`Channel`/`Member` presentation records and Rust-computed management capabilities.

The bridge exposes the published guild/channel CRUD, member leave/kick, role CRUD/assignment, invitation create/list/revoke/accept, channel permission and override operations, authenticated profile, plus `backend_health`. `BackendError` distinguishes invalid input, HTTP status/Problem Details, transport failure, invalid response and closed session. A 401 invalidates the Rust session and returns Swift to login; other errors preserve the session and report the failed action. The UI never falls back to demo on a network failure.

Unlike the local demo getters, these operations perform blocking I/O and **must run off the UI thread**. `AppViewModel` uses `Task.detached`, checks session/navigation generations before applying results, disables overlapping mutations and keeps request-bound form values outside sendable closures. `close()` is local/idempotent; `logout()` performs remote revocation then clears the token even on failure. Window/app closure calls only local `close()`; passwords/tokens are not persisted.

No remote message/event API is exposed because it is absent from the currently served OpenAPI. `ChatClient` and its event subscription contract remain exclusive to the independent demo.


## C# projection (WinUI 3)

The same contract reads differently in C# because `uniffi-bindgen-cs` uses its own naming conventions; `apps/windows` is written against these generated names, not the Swift ones above.

| Rust / Swift | Generated C# |
| --- | --- |
| `ChatClient.newDemo()` | `ChatClient.NewDemo()` (static) |
| `try client.listMessages(channelId:) -> [Message]` | `Message[] ListMessages(string channelId)` |
| `Server` / `BackendWorkspace` records | positional `record` with PascalCase properties, arrays for `Vec` |
| `createdAtMs: u64` | `ulong CreatedAtMs` |
| `Option<T>` | nullable `string?` / `long?` |
| `throw ChatError` / `BackendError` | `ChatException` / `BackendException` with nested variant classes (`BackendException.Http.status` is a lowercase `ushort` field) |
| `setEventListener` protocol | `ChatEventListener` interface implemented in C# |
| object lifetime | `IDisposable`; `Dispose()` releases the Rust `Arc`, `Close()` only invalidates the session |

Every FFI method is synchronous, so the C# `AppViewModel` wraps each one in `Task.Run` — equivalent to `Task.detached` — and applies results only while its session/navigation generation still matches. Events arrive on the Rust Tokio worker and hop to the UI thread through `DispatcherQueue.TryEnqueue`, carrying the subscription generation captured at registration time. Order, upsert-by-id and the "no listener holds its client" rule are unchanged.

Generator quirks worth preserving: bindings are produced in `--library` mode from a host-built cdylib (so generation works on any OS), `uniffi-bindgen-cs` must be installed with `cargo install --locked`, and its config only honours a top-level `[bindings.csharp]` table plus a verbatim lowercase `access_modifier`. See [architecture](architecture.md) for details.
