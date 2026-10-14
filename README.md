# Discord Clone

A native **macOS 27+** chat application built with **SwiftUI and AppKit**, powered by a portable **Rust** core through **UniFFI**.

The project currently provides an interactive, local demo with three servers, channels, members, and message histories. A real backend will be integrated later. This is an independent Discord-style application; it does not connect to Discord or use its API. The demo interface is currently in French.

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

## Explore the demo

Choose **Ouvrir la démo** (Open demo) on the login screen. Real sign-in is disabled, and the login form neither sends nor stores credentials.

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
  networking/    Deterministic demo data; future HTTP/WebSocket transport
  storage/       In-memory repository; future persistent storage adapter
  apple-bridge/  UniFFI API, conversions, composition, and pinned binding generator
apps/macos/
  App/           Application and scenes
  Features/      Login, Servers, Channels, Chat, Members, Settings
  Components/    Avatars, AppKit message editor, and native pane controller
  ViewModels/    MainActor-isolated observable presentation state
  Tests/         Swift tests using the real Rust bridge
  UITests/       Native interaction scenarios
scripts/         Build, project generation, and verification
docs/           Architecture and FFI contract
```

The Xcode project and shared scheme are checked in and open directly. After adding or removing Swift files, regenerate the project without additional dependencies:

```sh
python3 scripts/generate-xcode-project.py
```

Bindings are generated separately for Debug and Release. Generated bindings, build products, and local Xcode user data are excluded from Git. `Cargo.lock` is checked in.

See [architecture](docs/architecture.md) and the [Swift–Rust contract](docs/ffi-contract.md) for responsibilities, event delivery, session cleanup, and the future backend integration.

## Verification

```sh
./scripts/check-rust.sh         # Formatting, Clippy, and Rust tests
./scripts/build-macos.sh --clean
./scripts/test-macos.sh         # Swift tests with the real Rust bridge
./scripts/test-ui.sh            # XCTest UI scenarios and screenshots
./scripts/verify.sh             # Run all checks above
```

Development verification passed Debug and Release builds, Clippy, five Rust tests, and six Swift unit tests. The pane regression test opens and closes panels twenty times at **900 × 600**, checking stable window dimensions, a readable conversation, native inspector controls, presentation synchronization, minimum-size enforcement, delegate forwarding, and toolbar cleanup.

Swift tests also produce light, dark, and compact offscreen previews in `.build/previews/`. Offscreen rendering does not always reproduce macOS composited materials and selection highlights accurately.

UI tests require an unlocked macOS graphical session and the automation permissions requested by Xcode. XCTest results and screenshots are stored in `.build/macos/Logs/Test/`. On the development machine, the UI runner times out before executing its scenarios (`Timed out while enabling automation mode`). Native interactions were checked separately; the automated UI suite still needs execution on a working automation host. `verify.sh` reports this failure instead of hiding it.

## Current scope

Real authentication, HTTP/WebSocket networking, SQLite, attachments, audio/video, and Windows are not implemented. The HTTP contract awaits the backend OpenAPI specification; the WebSocket contract will be defined separately.

The Rust core remains reusable by a future **WinUI 3** interface through its own adapter. Windows will not depend on the Apple bridge, Swift bindings, or AppKit.
