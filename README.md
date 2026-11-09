# Discord Clone

A native **macOS 27+** chat application built with **SwiftUI and AppKit**, powered by a portable **Rust** core through **UniFFI**. The same Rust contract also drives a **WinUI 3** (C#) application for Windows through `uniffi-bindgen-cs`.

The application connects to the published REST backend for authentication and community management. An independent local demo provides three servers, channels, members, and message histories. This is an independent Discord-style application; it does not connect to Discord or use its API. The interface is currently in French.

## Build and run

Requirements:

- macOS 27 or later, on Apple Silicon.
- Xcode 27, with its command-line tools selected.
- Rust 1.88 or later, installed through rustup.
- The `aarch64-apple-darwin` Rust target.

```sh
rustup target add aarch64-apple-darwin
open apps/macos/DiscordClone.xcodeproj
```

In Xcode, select the **DiscordClone** scheme and **My Mac** destination, then run with **⌘R**. The build phase compiles Rust, generates Swift bindings, and links the static library automatically. UniFFI and its generator share the pinned **0.32.2** version; no global generator installation is required. The initial build downloads Cargo dependencies.

You can also build from the terminal:

```sh
./scripts/build-macos.sh
open .build/macos/Build/Products/Debug/DiscordClone.app
```

For a Release build:

```sh
xcodebuild -project apps/macos/DiscordClone.xcodeproj \
  -scheme DiscordClone -configuration Release \
  -destination 'platform=macOS,arch=arm64' \
  -derivedDataPath .build/macos CODE_SIGN_IDENTITY=- build
```

Builds use local ad hoc signing. An Apple Developer account is not required to run the app locally; distribution and notarization are not configured.

## Build and run (Windows)

The WinUI 3 app reuses the same Rust crates and the same UniFFI contract. Requirements: **Windows 11 24H2 (build 26100) or later**, x64, .NET 9 SDK, Visual Studio 2022 with the "Universal Windows Platform development" workload, Rust 1.88 with the `x86_64-pc-windows-msvc` target, and bash (Git for Windows is enough). The project pins **Windows App SDK 2.6.5** (1.8 left servicing on 2026-09-24). The 24H2 floor is deliberate: below Windows 11 22000 Mica silently degrades to a solid colour, and Segoe Fluent Icons plus 24H2-era WinRT APIs then need no version guards.

Install the C# bindings generator once. `--locked` is required: without it Cargo resolves `uniffi_bindgen` 0.32.2, which no longer matches the generator's expected API and fails to compile.

The generated bindings use `[LibraryImport]` P/Invoke with `unsafe` blocks and `stackalloc`, so `apps/windows` sets `<AllowUnsafeBlocks>true</AllowUnsafeBlocks>`. Without that property the build fails with roughly 130 `CS0227` errors pointing at the generated file, not at your code.

```sh
cargo install --locked uniffi-bindgen-cs \
  --git https://github.com/NordSecurity/uniffi-bindgen-cs --tag v0.12.0+v0.32.0
```

Bindings are read from a compiled library, so they can also be generated on macOS or Linux:

```sh
./scripts/build-windows.sh          # writes apps/windows/Generated/chat_bridge.cs
```

On Windows, build the native DLL and the app together:

```powershell
./scripts/build-windows.ps1                 # Debug
./scripts/build-windows.ps1 -Release -Publish
```

The script copies `chat_bridge.dll` next to `DiscordClone.Windows.exe` because the generated bindings P/Invoke that library by name. The app is unpackaged (`WindowsPackageType = None`), so it runs without dev mode, MSIX, or a certificate, and `.cargo/config.toml` links the CRT statically so no VC++ redistributable is needed.

**Status:** the app has never been launched or visually reviewed — WinUI 3 needs an interactive Windows session, and this repository's development machine is a Mac without a .NET SDK. CI does compile it; see [Verification](#verification).

## Connect to the backend

Start the backend, then use **Connexion** or **Créer un compte** with its origin (default `http://localhost:3000`). Remote origins must use HTTPS; HTTP is allowed only for loopback addresses. Account names contain 3–32 ASCII letters, digits, underscores, hyphens or dots; registration passwords contain 15–128 Unicode characters. Server, channel and role names support Unicode.

- Use **+** in the server rail to create a server or join with an invitation code.
- Use **Gérer** to rename/delete an owned server or leave another server; create, rename, reorder and delete text/voice channels; manage roles and member assignments; expel members; create/revoke invitations; and inspect or edit channel permission overrides.
- Rust computes available management controls from the current roles and channel permission endpoint. The backend remains authoritative and may reject actions when permissions have changed. Destructive actions require confirmation.
- **Actualiser** reloads the selected community. Mutations reload it after success. Requests run outside `MainActor`, have a 15-second timeout, and discard responses from superseded selections or closed sessions. Authentication expiry/revocation returns to the login screen.
- **Se déconnecter** in Settings immediately clears local data and requests remote token revocation. If revocation cannot be confirmed, the login screen reports it. Closing the window/app only discards the in-memory token; the remote session expires according to the backend's policy. No password or session token is persisted, and no automatic login is implemented.
- Invitations expire after 1–604,800 seconds and may allow 1–1,000,000 uses, or unlimited uses. The code appears only after creation, is shareable, and is discarded when the management sheet closes. Listing invitations returns metadata only.

The OpenAPI document served at `http://localhost:3000/api/v1/openapi.json` on 2026-10-14 exposes authentication, communities, roles, members, channels, permission overrides, invitations and health. **It exposes no messaging, WebSocket, audio, video or presence routes.** Connected text and voice channels therefore show an explicit availability notice and no message composer. Member lists make no online/offline claim. The local demo remains available for conversations.

All networking, JSON decoding, credentials, URL/identifier validation and community permissions live in Rust (`core` and `networking`). SwiftUI/AppKit and WinUI 3 own only presentation and user intent; the shared `bridge` crate maps the generated UniFFI contract for both languages.

## Explore the demo

Choose **Ouvrir la démo** (Open demo) on the login screen. The demo does not contact the backend; its data and credentials are separate from real sign-in.

- Navigate servers and channels using native lists. Server icons display initials, with full names available through tooltips and accessibility labels. **⌘1**, **⌘2**, and **⌘3** switch servers.
- Show or hide the left sidebar independently of the full-height member inspector using their toolbar controls or the View menu. **⌃⌘S** toggles the sidebar; **⇧⌘M** toggles members.
- Resize the sidebar between 240 and 400 points and the inspector between 220 and 360 points. The server icon rail stays 80 points wide. A single AppKit split controller manages the panes and keeps the conversation readable without growing the window when panels reopen. The window minimum is **900 × 600**.
- Send with **Return**; insert a new line with **Shift+Return**. Whitespace-only messages are rejected, and drafts are preserved per channel during the session.
- Use a message's context menu to copy it or delete your own messages.
- Click an avatar or member to open a read-only profile.
- Open Settings with **⌘,** to choose system, light, or dark appearance, or close the demo session.

Messages remain in memory. Closing the session, main window, or application resets the demo. Only the appearance preference is persisted. No incoming replies or typing indicators are simulated.

## Architecture

Swift owns navigation and presentation state. Rust owns business data, validation, storage, and events. The shared Rust crates have no dependency on UniFFI, Swift, AppKit, or macOS APIs; FFI types and conversions live in the Apple adapter.

```text
crates/
  core/          Portable models, repository contracts, chat service, and events
  networking/    REST backend transport and deterministic demo data
  storage/       In-memory repository; future persistent storage adapter
  bridge/        Shared UniFFI API, conversions, composition, and pinned binding generator
apps/macos/
  App/           Application and scenes
  Features/      Login, Servers, Channels, Chat, Members, Settings
  Components/    Avatars, AppKit message editor, and native pane controller
  ViewModels/    MainActor-isolated observable presentation state
  Tests/         Swift tests using the real Rust bridge
  UITests/       Native interaction scenarios
apps/windows/
  App.xaml / MainWindow.xaml       WinUI 3 shell, theme, minimum size, shortcuts
  Features/                        Login, Servers, Channels, Chat, Members, Community, Settings
  ViewModels/                      AppViewModel port and the event relay
  Presentation/                    Settings store, dialog helpers, observable base
  Generated/                       chat_bridge.cs (gitignored, generated by build-windows.sh)
scripts/         Build, project generation, and verification
docs/           Architecture and FFI contract
```

The Xcode project and shared scheme are checked in and open directly. After adding or removing Swift files, regenerate the project without additional dependencies:

```sh
python3 scripts/generate-xcode-project.py
```

Bindings are generated separately for Debug and Release. Generated bindings, build products, and local Xcode user data are excluded from Git. `Cargo.lock` is checked in.

See [architecture](docs/architecture.md) and the [Swift–Rust contract](docs/ffi-contract.md) for responsibilities, event delivery, REST integration and session cleanup.

## Verification

```sh
./scripts/check-rust.sh         # Formatting, Clippy, and Rust tests
./scripts/check-windows.sh      # Rust type-check for x86_64-pc-windows-msvc where possible
./scripts/build-macos.sh --clean
./scripts/test-macos.sh         # Swift tests with the real Rust bridge
./scripts/test-ui.sh            # XCTest UI scenarios and screenshots
./scripts/verify.sh             # Run all checks above
```

Windows-specific checks:

```sh
./scripts/build-windows.sh      # Generate apps/windows/Generated/chat_bridge.cs (any host)
./scripts/build-windows.ps1     # Native DLL + bindings + dotnet build (Windows only)
```

`.github/workflows/windows-build.yml` runs the Windows build on a `windows-latest` runner because this repository's development machine cannot: it executes `check-rust.sh` natively (which links `chat_bridge.dll` with the static CRT), installs `uniffi-bindgen-cs`, then builds the DLL, bindings and WinUI app through `build-windows.ps1`, uploading the log and the output folder. The job proves **compile and link only** — it never launches `DiscordClone.Windows.exe`, since WinUI 3 requires an interactive desktop, so launch, Mica rendering and dialog behaviour still need a human on a Windows 11 24H2 machine. `live_backend` stays ignored in CI: it mutates the real backend and leaves accounts the API cannot delete.

The verification scripts cover formatting, Clippy, portable domain and HTTP fixture tests, generated Swift bindings and native Swift tests. Backend tests also check responsive login, canceled login revocation, logout and native renders through the real Rust bridge. The pane regression test opens and closes panels twenty times at **900 × 600**, checking stable window dimensions, a readable conversation, native inspector controls, presentation synchronization, minimum-size enforcement, delegate forwarding, and toolbar cleanup.

Swift tests also produce light, dark, and compact offscreen previews in `.build/previews/`. Offscreen rendering does not always reproduce macOS composited materials and selection highlights accurately.

The Windows side is verified only as far as a macOS host allows, and `check-windows.sh` says so instead of passing silently: the C# bindings are really generated from the compiled library, and `chat-core` plus `chat-storage` type-check for `x86_64-pc-windows-msvc`. `chat-networking` and `chat-bridge` cannot be cross-checked here because `ring`, reached through reqwest → rustls, compiles C for the target and needs the Windows SDK (`cargo-xwin`) — which is not installed.

The CI job closes exactly that gap: on Windows it builds and tests every crate, links `chat_bridge.dll` with the static CRT, generates the bindings from that DLL, and restores Windows App SDK 2.6.5 under `net9.0-windows10.0.26100.0` — all of which succeeded on the first run. That same run rejected two assumptions I could not test locally (`GridSplitter` is UWP-only, and comma-separated `KeyboardAccelerator.Modifiers` text does not parse), both now fixed. Still unproven: the C# compilation itself, the app launching, and how Mica, dialogs and the layout actually render — those need an interactive Windows 11 24H2 session.

UI tests require an unlocked macOS graphical session and the automation permissions requested by Xcode. XCTest results and screenshots are stored in `.build/macos/Logs/Test/`. On the development machine, the UI runner times out before executing its scenarios (`Timed out while enabling automation mode`). Native interactions were checked separately; the automated UI suite still needs execution on a working automation host. `verify.sh` reports this failure instead of hiding it.

## Current scope

Authentication and all published community REST routes are implemented. Persistent sessions/SQLite, remote messaging, WebSocket, attachments, audio/video and Windows are outside the currently served API.

An opt-in integration test exercises the real backend using two isolated accounts, removes its guild and revokes its sessions:

```sh
cargo test --locked -p chat-networking --test live_backend -- --ignored
```

Set `DISCORD_BACKEND_URL` to test another origin. The backend has no account-deletion endpoint: each run leaves two unused accounts with `client-owner-*` / `client-member-*` addresses on `example.invalid`. Ordinary tests use local HTTP fixtures and never modify real backend data. Verification evidence for this integration is recorded in `GATES-backend.md`.

The Rust core is reused today by a **WinUI 3** interface (`apps/windows`) through the shared `bridge` crate: Windows consumes the same UniFFI contract as macOS and depends on neither the Swift bindings nor AppKit.
