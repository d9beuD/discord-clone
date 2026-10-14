# Gates: native macOS shell and portable Rust core

Scope: build and exercise the macOS demo through the real Rust bridge while preserving a platform-independent core.

- [x] G1: Rust behavior, formatting and lint checks pass
  CHECK: ./scripts/check-rust.sh
  EXPECT: RUST CHECKS PASSED
  EVIDENCE: 2026-10-14; shell=/bin/bash; cwd=discord-clone; exit=0; EXPECT=matched; output-sha256=4986928f94b68d2949a6550e2843468ffc14dea7a405cbe9feb0e1fe81569f14; output-bytes=2444; logs=.build/verification/

- [x] G2: A clean Xcode build generates bindings and links the Rust static library
  CHECK: ./scripts/build-macos.sh --clean
  EXPECT: MACOS BUILD PASSED
  EVIDENCE: 2026-10-14; shell=/bin/bash; cwd=discord-clone; exit=0; EXPECT=matched; output-sha256=7ea0ecafd932cf058304aaa01e5b28bbce8c40b7f62349938aae63e416829636; output-bytes=130725; logs=.build/verification/; Release build also exits 0; sha256=0a269e0198e6b565d454661166c94a47abc9903e4f714dc16af4dc0507e589fe

- [x] G3: Swift tests exercise the real bridge, event delivery, deduplication and shutdown
  CHECK: ./scripts/test-macos.sh
  EXPECT: MACOS TESTS PASSED
  EVIDENCE: 2026-10-14; shell=/bin/bash; cwd=discord-clone; exit=0; EXPECT=matched; output-sha256=8cd8b6c205b0bb651c53c4629e21edda355e44568048e6b553a8c4e94139305d; output-bytes=160127; logs=.build/verification/

- [ ] G4: Native UI exercises login, navigation, editing, profiles, settings and adaptive members
  CHECK: ./scripts/test-ui.sh
  EXPECT: UI TESTS PASSED
  EVIDENCE: exit=65 before any UI test starts; XCTest runner reports Timed out while enabling automation mode. Full log preserved at .build/verification/ui-tests.log. The suite compiles in the successful Swift test build.

- [x] G5: Light/dark appearance and keyboard/accessibility behavior are visually reviewed
  EVIDENCE: Native light workspace/profile and dark settings inspected via CUA. Return, Shift+Return, members shortcut and settings shortcut exercised on AZERTY. Native offscreen previews in .build/previews reviewed at 1180 and 900 points; compact layout hides members and retains readable messages/editor. Offscreen vibrancy/selection differs from the onscreen compositor, as documented in README.

- [x] G6: Documentation explains build, memory-only demo, FFI lifecycle and future Windows adapter
  EVIDENCE: README.md, docs/architecture.md and docs/ffi-contract.md reviewed against the implementation. Portable crates have no UniFFI/Swift/AppKit dependency; only apple-bridge maps FFI types. Both Xcode configurations build; binding version is pinned and Cargo.lock is present.

- [x] G4M: Native interactive demo is exercised through computer use
  EVIDENCE: CUA verified login/demo, empty salon, multiline input, restored per-channel draft, Return send, copy/paste, deletion returning to an empty salon, profile, member toggle and settings appearance. App was restarted after checks and left on the initial demo salon with the original system appearance preference restored. Session closure/reset is covered by Rust and Swift tests.

ABANDON: G4 XCTest UI runner cannot initialize automation mode on this host; rerun scripts/test-ui.sh on a working macOS automation environment. No OS security settings were changed to bypass this failure.

Validation summary: 6 met, 0 pending, 1 abandoned (G4). The abandoned automation gate is not claimed as passed.

## Native sidebar revision

Navigation now uses a three-column NavigationSplitView with native server/channel lists and SidebarCommands. Rust, session behavior and the member panel are unchanged.

Verification: Debug app and test targets compile, five Swift tests pass, Release build passes. Swift log SHA-256: ec03b44b01101c44e6835e4ac97913e4c340079c6d4ef7129fbfc6d37feead86. Logs: .build/verification/sidebar-*.log.

CUA verified selecting Rust & Friends and returning to L’Atelier, hiding/showing the sidebar using the system toolbar button, and adjusting the native server-column divider from 180 to 220 points and back. Native light workspace and 900-point offscreen layout reviewed. Automated UI execution retains the earlier G4 host limitation; its locators are updated for native lists.

## Server icon revision

The native server List now shows 48-point monogram icons in a compact sidebar, with circular inactive icons and a colored rounded selected icon. Full server names remain as tooltips/accessibility labels. The profile footer is icon-only.

Five Swift tests and the Release build pass; logs are in .build/verification/server-icons-*.log. CUA verified the icon-only layout, full native row accessibility names, and selection of Rust & Friends updating its channels/messages. The earlier automated UI runner limitation is unchanged.

## Native member inspector revision

Members now use the native SwiftUI inspector attached to the navigation container, with grouped Form sections, a 220–360-point resizable column and InspectorCommands. The toolbar toggle and existing keyboard shortcut share the same presentation state. The manual 1050-point hiding threshold is removed; the inspector remains available at compact widths.

Five Swift tests pass, including wide/compact native renders, and the Release build passes. Debug app and both test targets compile. Logs are in .build/verification/inspector-tests.log and inspector-release.log.

CUA verified the onscreen native inspector, toolbar hide, keyboard show, resizing from 260 to 300 points and back, and opening/closing Alex’s profile from the member list. Light/dark onscreen renders and compact offscreen previews were reviewed. The system appearance preference was restored and the Release demo is left open with the inspector visible. Automated UI execution retains the earlier G4 host limitation.

## Sidebar and inspector coexistence fix

The server icon rail and channel List now share one native navigation sidebar. This gives the system sidebar toolbar button enough room; it no longer overflows from a 96-point first navigation column. The icon rail stays at 80 points and the whole sidebar resizes from 240 to 400 points. The inspector belongs to the conversation detail column. Sidebar and inspector presentation remain independent.

Five Swift tests and the Release build pass; logs are in .build/verification/sidebar-restoration-*.log. The offscreen snapshot harness now uses a resizable window, waits for native layout and reapplies the requested viewport before capture. The 900-point snapshot retains servers, channels, conversation and members; it was visually reviewed with the existing compositor limitations.

CUA verified the final Release build has a visible native sidebar button at the left, sidebar hide/show while members remain displayed, and inspector hide/show while the sidebar button and lists remain displayed. A dedicated UI regression test compiles in the test build; its execution retains the earlier G4 host limitation. The demo is left open with both panels visible.

## Full-height inspector with native sidebar

The inspector modifier now wraps the NavigationSplitView instead of the conversation detail column. This restores its full-height native presentation, including the title-bar region. The combined server/channel sidebar remains unchanged, so its native system toolbar button stays visible.

Five Swift tests, including the 900-point native snapshot, and the Release build pass. Logs: .build/verification/full-height-inspector-*.log. CUA visually verified the inspector extends through the title-bar region without the main toolbar's horizontal separator, the sidebar toggle remains visible, and each panel hides/shows independently. The demo is left open with both panels. The earlier G4 automation host limitation remains.

## Window resizing crash fix

The reported crash contains the AppKit constraint-update exception. A new native window regression test reproduced the same exception with the outer SwiftUI minimum-size frame, after enlarging the split panes and reducing the window. The outer frame is removed; windowWillResize now enforces the minimum independently through an AppKit delegate which forwards the original delegate's callbacks. Root hosting size probes are disabled when available.

Six Swift tests pass. The regression exercises three cycles from 1180 × 780 through 1040 × 680 to 900 × 600 with enlarged panels; it verifies the minimum-size clamp, session survival and delegate forwarding. The Release build passes. Evidence: .build/verification/resize-before.log, resize-tests.log and resize-release.log.

CUA verified the final Release demo opens with the native sidebar and full-height inspector and survives enlarging both panes. Actual mouse dragging could not be exercised because coordinate actions were rejected by the computer-use tool's active-state check; this is not claimed as passed. The existing XCTest UI runner limitation also remains.

## Repeated pane toggles at minimum size

The user's 2026-10-14 16:46:36 report aborts on the main thread in NSWindow constraint updates, with NSHostingView size constraints invalidating layout repeatedly. The expanded regression test reproduced both window growth and the same NSGenericException when reopening the nested SwiftUI panels after restoring 900 × 600. Evidence: .build/verification/panel-cycles-before.log.

NativeWorkspace now hosts the SwiftUI sidebar, conversation and members in a single AppKit NSSplitViewController. Pane hosts disable automatic sizing constraints; explicit native minimum widths fit within 900 points. Both panels resize their siblings rather than the window. The native inspector stays full height through tracking separators in an AppKit toolbar. Native toolbar buttons, Swift presentation state and menu commands stay synchronized; stale queued native observations are discarded. Toolbar cleanup uses its weak owning-window reference.

Six Swift tests pass, including twenty pane cycles at 900 × 600 after expanding the dividers. The regression asserts stable window width and height, conversation width >= 360, sidebar state synchronization, native inspector-button action dispatch, minimum resize clamping, delegate forwarding and toolbar cleanup. The light/dark/compact offscreen render checks pass with the previously documented compositor limitations. Debug app and unit/UI test targets compile, and the Release build passes. Logs: .build/verification/panel-cycles-tests.log and panel-cycles-release.log.

CUA verified the native full-height inspector, independent panel toolbar toggles at 900 points, the members keyboard shortcut, corrected menu presentation labels and sidebar menu action, and opening Settings. Final native NSButton toggles expose AXCheckBox state; UI test locators now match that role. XCTest UI execution and manual mouse dragging retain their earlier host limitations. Closing Settings during the extra dark-appearance check made the CUA window selection time out; a process sample showed an idle main run loop, not an app freeze, and no new crash report appeared. The dark appearance is not claimed as visually verified; the original persisted system appearance was restored through the app's defaults domain.
