# Architecture

## Responsabilités et dépendances

SwiftUI et AppKit affichent l’application. `AppViewModel`, observable et isolé sur `MainActor`, possède sélection, brouillons, profil ouvert et erreurs de présentation. Swift ne crée ni données de démonstration ni règles de permission : ces éléments viennent de Rust.

La navigation macOS utilise un seul `NSSplitViewController` AppKit, exposé à SwiftUI par `NativeWorkspace`. Ses trois colonnes hébergent les vues SwiftUI : sidebar serveurs/salons, conversation et inspecteur des membres. La sidebar native utilise `NSSplitViewItem(sidebarWithViewController:)` et se redimensionne entre 240 et 400 points. La conversation garde au moins 360 points. Les tailles des colonnes appartiennent à AppKit ; les `NSHostingController` ne publient pas de contraintes automatiques de taille (`sizingOptions = []`). Cette disposition évite la boucle de contraintes rencontrée avec un `NavigationSplitView` imbriqué dans un `inspector` SwiftUI à la taille minimale de la fenêtre.

L’inspecteur utilise `NSSplitViewItem(inspectorWithViewController:)`, entre 220 et 360 points (260 par défaut). `allowsFullHeightLayout` et les séparateurs de toolbar `NSTrackingSeparatorToolbarItem` préservent sa présentation pleine hauteur, avec sa propre zone de barre d’outils. Les boutons natifs `NSButton` de la toolbar ciblent directement les actions `toggleSidebar` et `toggleInspector` du contrôleur, avec état, infobulle et libellé accessible reflétant la présentation. Les panneaux redimensionnent leurs voisins plutôt que la fenêtre (`preferResizingSiblingsWithFixedSplitView`). AppKit peut les replier lors du redimensionnement. Les observations de `isCollapsed` relaient les changements natifs vers l’état Swift ; les mises à jour Swift ne renvoient pas de notifications de présentation à SwiftUI. La sélection et les brouillons restent dans le ViewModel, et les visibilités restent liées à `AppViewModel.showSidebar` et `showMembers`. Les commandes du menu Présentation utilisent ces mêmes états, avec ⌃⌘S pour la sidebar et ⇧⌘M pour les membres.

Le rail des serveurs a une largeur fixe de 80 points et affiche des icônes à initiales fournies par Rust. La liste des salons prend la largeur restante de la sidebar. La sélection native et les noms accessibles sont conservés ; les noms complets apparaissent en infobulle. Les icônes utilisent des cercles au repos et une forme arrondie colorée pour le serveur sélectionné.

La limite de redimensionnement de 900 × 600 est appliquée par un délégué AppKit de fenêtre, via `MinimumWindowSize`. Il relaie les événements au délégué SwiftUI existant et limite les tailles proposées par `windowWillResize`. La vue SwiftUI englobante ne porte pas de `.frame(minWidth:minHeight:)` afin de conserver une seule source de géométrie pour les colonnes. Le hosting view racine désactive ces sondes automatiques lorsque son type le permet ; la géométrie native de la fenêtre reste la source de la taille disponible.

```text
SwiftUI / AppKit → AppViewModel → apple-bridge
                                  ├── core ← storage
                                  └── networking → core
```

- `core` contient modèles, erreurs, contrat `ChatRepository`, `ChatService` et événements. Il valide les messages et les permissions de suppression, et possède un dispatcher Tokio par session.
- `storage` implémente `ChatRepository` en mémoire. Les verrous et la sérialisation des mutations sont gérés par le service, pas par l’interface.
- `networking` fournit `demo_snapshot()`, une source déterministe de données initiales. Aucun HTTP ou WebSocket n’est inventé avant réception des contrats serveur.
- `apple-bridge` compose source démo, repository et service. Ses records/enums convertissent les modèles métier en types UniFFI. Seule cette crate connaît UniFFI.

Les getters renvoient des copies du cache et les commandes locales sont courtes et synchrones. Chaque mutation est sérialisée sous un verrou du service. Le cache est modifié avant la mise en file de l’événement ; le dispatcher relâche tous les verrous avant de rappeler le listener Swift. Des mutations suivantes peuvent déjà être appliquées lorsque le callback relit le cache : il obtient toujours son état le plus récent.

## Session et événements

Une session crée une bibliothèque cliente, un repository, un runtime Tokio à un worker et un listener. Le listener Swift n’a qu’une continuation `AsyncStream`, sans référence au client ni au ViewModel. Une tâche sur `MainActor` consomme les événements dans l’ordre et actualise le salon affiché. L’envoi retourne aussi le message créé ; la fusion par identifiant évite un doublon lorsque l’événement arrive.

Le service numérote les abonnements. Remplacer ou retirer le listener invalide les événements en attente de l’ancien abonnement. Un callback déjà commencé peut finir. Swift annule donc la tâche et termine le stream avant de retirer le listener puis de fermer le client. Une génération de session empêche une ancienne tâche d’appliquer un événement à une nouvelle session. La fermeture est idempotente et le runtime est arrêté sans bloquer le thread UI.

Les données sont perdues à la fermeture de session, de fenêtre ou d’application. Les brouillons sont des données de présentation éphémères. Le choix du thème est une préférence utilisateur macOS indépendante du cache métier.

## Build Apple

Le projet Xcode compile du Swift 6 avec les vérifications complètes de concurrence et cible macOS 27 sur Apple Silicon. Une phase lance `scripts/build-rust.sh` avant la compilation Swift :

1. Compiler `apple-bridge` pour `aarch64-apple-darwin` dans le profil demandé.
2. Exécuter le générateur du workspace, de même version UniFFI **0.32.2** que la bibliothèque.
3. Générer source Swift, header et modulemap dans `Generated/<configuration>`.
4. Copier la bibliothèque statique puis la lier à l’exécutable natif.

Les fichiers source et sorties de la phase sont déclarés dans le projet. La phase est exécutée à chaque build pour que Cargo puisse découvrir aussi les nouvelles dépendances et modules ; Cargo effectue ensuite son build incrémental. Le sandbox des scripts Xcode est désactivé pour permettre à Cargo d’accéder à ses caches. Aucun sandbox d’exécution ou mécanisme de distribution n’est configuré pour cette démo locale.

## Raccordement du backend

L’OpenAPI permettra d’implémenter les appels HTTP dans `networking`, puis de convertir leurs DTO en modèles de `core`. L’authentification réelle aura son propre cycle de vie et stockage sécurisé de jetons. Le format, l’authentification et les règles de reconnexion du WebSocket nécessitent leur documentation dédiée ; OpenAPI seul ne les définit pas nécessairement.

Le futur transport mettra à jour le repository et publiera les événements métier avec le même principe cache → événement. Les opérations réseau devront être asynchrones sans bloquer `MainActor` ; les getters actuels resteront des lectures du cache. Le contrat FFI local pourra évoluer avec les besoins du backend : il ne prétend pas figer ses DTO, sa pagination ou ses états de synchronisation.

SQLite remplacera le repository mémoire par une implémentation de `ChatRepository`. Aucun chemin de stockage Apple ou accès Keychain n’est intégré au domaine.

## Future interface Windows

Une interface WinUI 3 possédera son état et sa navigation dans ses propres ViewModels. Elle réutilisera `core`, `networking` et `storage`, avec un adaptateur dédié aux contraintes de son interop .NET. Elle ne dépendra pas de `apple-bridge`, des bindings Swift ou d’AppKit. Ne pas présumer d’un support C# fourni par UniFFI et ne pas ajouter de pont Windows avant cette étape.
