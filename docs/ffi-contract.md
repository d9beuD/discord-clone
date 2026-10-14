# Contrat Swift ↔ Rust

UniFFI 0.32.2 génère `ChatBridge.swift` et le module C `ChatBridgeFFI`. La source générée est compilée dans le module applicatif `DiscordClone`. Les identifiants sont des chaînes opaques, jamais des indices de sélection ou pointeurs.

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

Ce contrat est celui du cache local de la première version. Les endpoints, jetons, pagination, pièces jointes et états de synchronisation attendent l’OpenAPI et le protocole WebSocket. Les modèles métier ne portent pas de derives UniFFI : les futurs adaptateurs Swift et WinUI 3 gardent leurs propres contrats d’interop.
