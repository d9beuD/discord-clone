# Architecture

## Responsabilités et dépendances

SwiftUI et AppKit affichent l’application. `AppViewModel`, observable et isolé sur `MainActor`, possède sélection, brouillons, profil ouvert et erreurs de présentation. Swift ne crée ni données de démonstration ni règles de permission : ces éléments viennent de Rust.

La navigation macOS utilise un seul `NSSplitViewController` AppKit, exposé à SwiftUI par `NativeWorkspace`. Ses trois colonnes hébergent les vues SwiftUI : sidebar serveurs/salons, conversation et inspecteur des membres. La sidebar native utilise `NSSplitViewItem(sidebarWithViewController:)` et se redimensionne entre 240 et 400 points. La conversation garde au moins 360 points. Les tailles des colonnes appartiennent à AppKit ; les `NSHostingController` ne publient pas de contraintes automatiques de taille (`sizingOptions = []`). Cette disposition évite la boucle de contraintes rencontrée avec un `NavigationSplitView` imbriqué dans un `inspector` SwiftUI à la taille minimale de la fenêtre.

L’inspecteur utilise `NSSplitViewItem(inspectorWithViewController:)`, entre 220 et 360 points (260 par défaut). `allowsFullHeightLayout` et les séparateurs de toolbar `NSTrackingSeparatorToolbarItem` préservent sa présentation pleine hauteur, avec sa propre zone de barre d’outils. Les boutons natifs `NSButton` de la toolbar ciblent directement les actions `toggleSidebar` et `toggleInspector` du contrôleur, avec état, infobulle et libellé accessible reflétant la présentation. Les panneaux redimensionnent leurs voisins plutôt que la fenêtre (`preferResizingSiblingsWithFixedSplitView`). AppKit peut les replier lors du redimensionnement. Les observations de `isCollapsed` relaient les changements natifs vers l’état Swift ; les mises à jour Swift ne renvoient pas de notifications de présentation à SwiftUI. La sélection et les brouillons restent dans le ViewModel, et les visibilités restent liées à `AppViewModel.showSidebar` et `showMembers`. Les commandes du menu Présentation utilisent ces mêmes états, avec ⌃⌘S pour la sidebar et ⇧⌘M pour les membres.

Le rail des serveurs a une largeur fixe de 80 points et affiche des icônes à initiales fournies par Rust. La liste des salons prend la largeur restante de la sidebar. La sélection native et les noms accessibles sont conservés ; les noms complets apparaissent en infobulle. Les icônes utilisent des cercles au repos et une forme arrondie colorée pour le serveur sélectionné.

La limite de redimensionnement de 900 × 600 est appliquée par un délégué AppKit de fenêtre, via `MinimumWindowSize`. Il relaie les événements au délégué SwiftUI existant et limite les tailles proposées par `windowWillResize`. La vue SwiftUI englobante ne porte pas de `.frame(minWidth:minHeight:)` afin de conserver une seule source de géométrie pour les colonnes. Le hosting view racine désactive ces sondes automatiques lorsque son type le permet ; la géométrie native de la fenêtre reste la source de la taille disponible.

```text
SwiftUI / AppKit ─┐
                  ├─→ chat-bridge → core ← storage
WinUI 3 / C# ─────┘                 ↑
                                 networking → core
```

- `core` contient modèles, erreurs, contrat `ChatRepository`, `ChatService` et événements. Il valide les messages et les permissions de suppression, et possède un dispatcher Tokio par session.
- `storage` implémente `ChatRepository` en mémoire. Les verrous et la sérialisation des mutations sont gérés par le service, pas par l’interface.
- `networking` fournit `demo_snapshot()` et `BackendSession`, le transport REST basé sur reqwest. Les DTO de communauté et validations de noms/permissions appartiennent à `core::community`. Aucun contrat de messagerie ou WebSocket n’est inventé.
- `chat-bridge` compose source démo, repository et service, et expose `BackendClient` pour les sessions distantes. Ses records/enums convertissent les modèles métier en types UniFFI. Seule cette crate connaît UniFFI. Elle n’est plus spécifique à Apple : le même contrat est généré en Swift et en C#.

Les getters renvoient des copies du cache et les commandes locales sont courtes et synchrones. Chaque mutation est sérialisée sous un verrou du service. Le cache est modifié avant la mise en file de l’événement ; le dispatcher relâche tous les verrous avant de rappeler le listener Swift. Des mutations suivantes peuvent déjà être appliquées lorsque le callback relit le cache : il obtient toujours son état le plus récent.

## Session et événements

Une session crée une bibliothèque cliente, un repository, un runtime Tokio à un worker et un listener. Le listener Swift n’a qu’une continuation `AsyncStream`, sans référence au client ni au ViewModel. Une tâche sur `MainActor` consomme les événements dans l’ordre et actualise le salon affiché. L’envoi retourne aussi le message créé ; la fusion par identifiant évite un doublon lorsque l’événement arrive.

Le service numérote les abonnements. Remplacer ou retirer le listener invalide les événements en attente de l’ancien abonnement. Un callback déjà commencé peut finir. Swift annule donc la tâche et termine le stream avant de retirer le listener puis de fermer le client. Une génération de session empêche une ancienne tâche d’appliquer un événement à une nouvelle session. La fermeture est idempotente et le runtime est arrêté sans bloquer le thread UI.

Les données sont perdues à la fermeture de session, de fenêtre ou d’application. Les brouillons sont des données de présentation éphémères. Le choix du thème est une préférence utilisateur macOS indépendante du cache métier.

## Build Apple

Le projet Xcode compile du Swift 6 avec les vérifications complètes de concurrence et cible macOS 27 sur Apple Silicon. Une phase lance `scripts/build-rust.sh` avant la compilation Swift :

1. Compiler `chat-bridge` pour `aarch64-apple-darwin` dans le profil demandé.
2. Exécuter le générateur du workspace, de même version UniFFI **0.32.2** que la bibliothèque.
3. Générer source Swift, header et modulemap dans `Generated/<configuration>`.
4. Copier la bibliothèque statique puis la lier à l’exécutable natif.

Les fichiers source et sorties de la phase sont déclarés dans le projet. La phase est exécutée à chaque build pour que Cargo puisse découvrir aussi les nouvelles dépendances et modules ; Cargo effectue ensuite son build incrémental. Le sandbox des scripts Xcode est désactivé pour permettre à Cargo d’accéder à ses caches. Aucun sandbox d’exécution ou mécanisme de distribution n’est configuré pour cette démo locale.

## Raccordement du backend

`BackendSession` utilise le contrat REST effectivement publié sur `http://localhost:3000/api/v1/openapi.json`. Cette session Rust possède le client HTTP, le jeton Bearer en mémoire et le profil renvoyé à l’authentification. Les redirections sont refusées, les URL contenant des identifiants/chemins/query sont rejetées et HTTP est limité à la boucle locale. Le délai de connexion est de cinq secondes et celui d’une requête de quinze secondes. Les erreurs Problem Details sont converties en erreurs typées ; aucun jeton ou mot de passe n’est exposé aux bindings Swift.

`BackendClient` est un adaptateur UniFFI distinct de `ChatClient`, ce qui préserve les règles et événements de la démo. `workspace()` charge serveur, salons, membres et rôles ; Rust calcule les droits de gestion du serveur et convertit les modèles vers la présentation existante. Les droits effectifs de chaque salon viennent de `/permissions/@me` ; l’autorisation finale de chaque action reste au backend. Aucun rôle par défaut ne peut être supprimé/renommé par les contrôles UI. Une invitation conserve son code uniquement dans la présentation jusqu’à fermeture de la feuille ; le backend ne retourne le code qu’à sa création.

Les méthodes FFI REST sont synchrones, mais chaque appel HTTP Swift passe par `Task.detached`, hors de `MainActor`. Les générations de session et navigation empêchent une réponse ancienne de modifier une nouvelle sélection ou session. Les mutations bloquent uniquement les contrôles concernés et rechargent le serveur courant. `close()` invalide le jeton local sans I/O ; `logout()` le révoque côté backend et le supprime localement même si le serveur est inaccessible. Une connexion annulée après création du jeton tente également sa révocation. Le transport refuse une réponse arrivée après fermeture.

Une session distante ne fabrique ni messages ni présence. Les salons texte/vocaux sont navigables et administrables, mais leurs conversations restent indisponibles tant que le serveur ne publie pas ces routes. Le rafraîchissement est explicite et après mutation ; aucune synchronisation temps réel ni reconnexion automatique n’est supposée.

SQLite remplacera le repository mémoire par une implémentation de `ChatRepository`. Aucun chemin de stockage Apple ou accès Keychain n’est intégré au domaine.

## Interface Windows (WinUI 3)

`apps/windows` est un projet C# non appareillé (`WindowsPackageType = None`, `net9.0-windows10.0.26100.0`, plancher `10.0.26100.0` — Windows 11 24H2, x64, Windows App SDK **2.6.5**) qui réutilise `core`, `networking` et `storage` via la **même crate `chat-bridge`** que macOS. Il ne dépend ni des bindings Swift ni d’AppKit ; ses propres ViewModels portent son état et sa navigation.

Le plancher 24H2 est un choix assumé : sous la build 22000, Mica retombe silencieusement sur une couleur pleine, et l’étage courant permet d’utiliser Segoe Fluent Icons et les API WinRT récentes sans garde `ApiInformation`. La fenêtre pose `MicaBackdrop Kind="BaseAlt"` ; les surfaces du workspace utilisent `LayerFillColorDefaultBrush` et la racine reste transparente, sinon la matière ne se voit pas. Les bandeaux d’erreur sont des `InfoBar`, les champs numériques des `NumberBox` (un champ vide ou invalide y vaut `NaN`, d’où l’unique passage par `WholeNumber`), et la préférence d’apparence est stockée par `ApplicationData.GetForUnpackaged(publisher, product)` — API de la 2.2.0, dont le mauvais chemin de registre a été corrigé en 2.3.1.

Les bindings C# viennent de `uniffi-bindgen-cs` (NordSecurity), tag `v0.12.0+v0.32.0`, aligné sur UniFFI 0.32. L’exécutable s’installe avec `cargo install --locked` : sans `--locked`, le générateur résout `uniffi_bindgen` 0.32.2 et sa compilation échoue sur des signatures d’API changées entre 0.32.0 et 0.32.2. `scripts/build-windows.sh` lit les bindings dans la cdylib **du poste courant** (`--library`), donc la génération marche aussi bien sur macOS que sur Windows ; seule la DLL `chat_bridge.dll` et l’app .NET se construisent sur Windows (`scripts/build-windows.ps1`).

Deux quirks du générateur sont compensés dans `crates/bridge/uniffi.toml` : il ignore les surcharges par crate `[crates.<nom>.bindings.csharp]` que le générateur Swift honore (d’où une table `[bindings.csharp]` au niveau racine), et il insère `access_modifier` verbatim, donc la valeur doit être le mot-clé minuscule `public`. Sans cela les records générés restent `internal` et le binding XAML réflexif ne les voit pas.

Le pont C# expose des méthodes en PascalCase, des tableaux, des records à propriétés PascalCase, des objets `IDisposable` à comptage de références, des exceptions `ChatException`/`BackendException` (variants imbriqués) et une interface de callback `ChatEventListener`. `EventRelay` n’utilise qu’un `DispatcherQueue.TryEnqueue` et capture la génération d’abonnement : un événement d’une session remplacée ne peut pas revenir dans l’UI. `AppViewModel` réplique fidèlement l’homologue Swift (générations session/navigation/action, `Task.Run` pour chaque appel FFI bloquant, textes d’erreurs français identiques) ; Rust calcule toujours les droits, aucune arithmétique de masques n’existe côté C#.

WinUI 3 n’offre pas de taille minimale de fenêtre native : `MainWindow` applique un plancher 900 × 600 en corrigeant chaque redimensionnement via `AppWindow`. Aucun `app.manifest` n’est fourni — WinUI gère la conscience DPI, et un manifeste qui la répète est un conflit d’affichage à l’exécution.

Deux écarts de parité avec macOS, constatés par le premier build CI et assumés plutôt que bricolés : `GridSplitter` est un type UWP absent de WinUI 3, donc les volets ont une largeur fixe et ne font que se replier — la plage de redimensionnement 240–400 et 220–360 n’existe pas côté Windows ; et le compilateur de markup refuse `Modifiers="Control,Alt"`, donc les raccourcis Ctrl+Alt+S et Ctrl+Shift+M sont construits en code-behind.

**Vérification à ce jour** : sur ce poste macOS, les checks Rust passent et les bindings C# sont réellement générés depuis la cdylib. Le job `windows-build.yml` apporte ce que ce poste ne peut pas prouver : `cargo test` natif sous Windows, liaison réelle de `chat_bridge.dll` avec la CRT statique, génération des bindings depuis la DLL Windows, et restauration NuGet de Windows App SDK 2.6.5 sur `net9.0-windows10.0.26100.0`. Le compilateur de markup a déjà rejeté deux hypothèses (GridSplitter, texte des modificateurs), corrigées ci-dessus. Reste à prouver : la compilation C# elle-même, le markup des pages non encore atteint par cette passe, puis le lancement, le rendu Mica et le comportement des dialogues — qui supposent une session interactive Windows 11 24H2.
