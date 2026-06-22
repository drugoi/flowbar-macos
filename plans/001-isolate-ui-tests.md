# Plan 001: Isolate UI tests from real user data and network downloads

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report; do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer tells you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat 6fa18b8..HEAD -- Sources/FlowBar/UI/FlowBarApp.swift Sources/FlowBar/Services/AppPaths.swift Tests/FlowBarUITests/FlowBarUITests.swift Tests/FlowBarTests/LibraryStoreCacheEvictionTests.swift`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: tests / dx
- **Planned at**: commit `6fa18b8`, 2026-06-22

## Why this matters

The default test command in `AGENTS.md` is `xcodebuild -scheme FlowBar -destination 'platform=macOS' test`. Today, the UI-test app constructs a normal `LibraryStore`, which uses the default Application Support and Caches locations unless `AppPaths` overrides are set. The UI test that downloads a YouTube URL also runs by default on local machines because it is only skipped when CI is set and `RUN_NETWORK_TESTS` is not set. A local verification run can therefore add, download, evict, or delete real FlowBar user data.

## Current state

- `Sources/FlowBar/Services/AppPaths.swift` centralizes the Application Support and Caches locations and has test override hooks:

```swift
// Sources/FlowBar/Services/AppPaths.swift:5
static var overrideApplicationSupportDirectory: URL?
static var overrideCachesDirectory: URL?
```

- `Sources/FlowBar/UI/FlowBarApp.swift` detects UI testing but enters the test app without configuring path overrides:

```swift
// Sources/FlowBar/UI/FlowBarApp.swift:7
let env = ProcessInfo.processInfo.environment
let isUITestRun = env["XCTestConfigurationFilePath"] != nil
if isUITestRun || env["UITESTING"] == "1" || ProcessInfo.processInfo.arguments.contains("-ui-testing") {
    NSApplication.shared.setActivationPolicy(.regular)
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    FlowBarUITestApp.main()
}
```

- The UI-test delegate creates `LibraryStore()` immediately, which loads from `AppPaths.libraryFileURL()`:

```swift
// Sources/FlowBar/UI/FlowBarApp.swift:58
private let libraryStore = LibraryStore()
private let playbackController = PlaybackController()
private let downloadManager = DownloadManager()
private let updateManager = UpdateManager(updatesEnabled: false)
```

- `Tests/FlowBarUITests/FlowBarUITests.swift` launches the app with only the generic UI-testing flag:

```swift
// Tests/FlowBarUITests/FlowBarUITests.swift:130
app.launchArguments = ["-ui-testing", "-ApplePersistenceIgnoreState", "YES"]
app.launchEnvironment["UITESTING"] = "1"
```

- The network/download UI test runs by default outside CI:

```swift
// Tests/FlowBarUITests/FlowBarUITests.swift:67
let shouldRunNetworkTests = env["RUN_NETWORK_TESTS"] == "1" || env["CI"] == nil
if !shouldRunNetworkTests {
    throw XCTSkip("Network download test disabled. Set RUN_NETWORK_TESTS=1 to enable.")
}
```

- Unit tests already use temp `AppPaths` overrides directly; preserve this pattern:

```swift
// Tests/FlowBarTests/LibraryStoreCacheEvictionTests.swift:18
AppPaths.overrideApplicationSupportDirectory = support
AppPaths.overrideCachesDirectory = caches
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Generate project | `xcodegen generate` | exits 0 |
| Unit tests | `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests` | exits 0 |
| UI smoke tests | `RUN_NETWORK_TESTS=0 xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarUITests/testTabNavigationAndEmptyState` | exits 0 or skips only for documented Accessibility/menu-bar runner reasons |
| Full declared test | `RUN_NETWORK_TESTS=0 xcodebuild -scheme FlowBar -destination 'platform=macOS' test` | exits 0 or has only documented UI Accessibility skips; it must not start the YouTube download test |

## Scope

**In scope**:

- `Sources/FlowBar/UI/FlowBarApp.swift`
- `Sources/FlowBar/Services/AppPaths.swift` only if a small helper is needed
- `Tests/FlowBarUITests/FlowBarUITests.swift`
- `Tests/FlowBarTests/LibraryStoreCacheEvictionTests.swift` only if shared cleanup helpers are moved or adjusted

**Out of scope**:

- Any changes to production download behavior.
- Any changes to `LibraryStore` persistence semantics.
- Any changes to app UI layout.

## Git workflow

- Branch: `codex/001-isolate-ui-tests`
- Commit style if committing: use conventional commits, for example `test: isolate ui test storage`.
- Do not push or open a PR unless instructed.

## Steps

### Step 1: Add a UI-test storage bootstrap before any LibraryStore is created

In `Sources/FlowBar/UI/FlowBarApp.swift`, add a small private helper that reads a launch environment variable such as `FLOWBAR_UI_TEST_ROOT`. When present, set:

- `AppPaths.overrideApplicationSupportDirectory = <root>/ApplicationSupport`
- `AppPaths.overrideCachesDirectory = <root>/Caches`

Call the helper inside the UI-test branch of `FlowBarMain.main()` before `FlowBarUITestApp.main()` is invoked. Do not set overrides for normal production launches.

If you cannot guarantee that this runs before `UITestAppDelegate` creates `LibraryStore`, convert the delegate's stored service properties to `lazy var` or initialize them after the override is configured. Keep `UpdateManager(updatesEnabled: false)` for UI tests.

**Verify**: `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests` -> exits 0.

### Step 2: Launch UI tests with a unique temp root

In `Tests/FlowBarUITests/FlowBarUITests.swift`, create a unique temp directory per test run, pass it through `app.launchEnvironment["FLOWBAR_UI_TEST_ROOT"]`, and delete it in `tearDown`.

Use `FileManager.default.temporaryDirectory` or `NSTemporaryDirectory()` and a UUID-named child directory. Keep `UITESTING=1` and `-ui-testing`.

**Verify**: `RUN_NETWORK_TESTS=0 xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarUITests/testTabNavigationAndEmptyState` -> exits 0 or skips only for runner Accessibility/menu-bar limitations.

### Step 3: Make network UI tests opt-in only

Change `testDownloadAndPlaybackForKnownURL` so it runs only when `RUN_NETWORK_TESTS=1`. Remove the `|| env["CI"] == nil` local-default behavior.

The skip message should be explicit: "Set RUN_NETWORK_TESTS=1 to enable network download tests."

**Verify**: `RUN_NETWORK_TESTS=0 xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarUITests/testDownloadAndPlaybackForKnownURL` -> exits 0 with that test skipped, not failed.

### Step 4: Confirm the default test command no longer downloads

Run the default test command with network tests disabled.

**Verify**: `RUN_NETWORK_TESTS=0 xcodebuild -scheme FlowBar -destination 'platform=macOS' test` -> exits 0 or only reports documented UI runner skips; it must not attempt a YouTube download.

## Test plan

- Add or adjust UI-test helper state in `Tests/FlowBarUITests/FlowBarUITests.swift`.
- Keep the existing unit test pattern in `LibraryStoreCacheEvictionTests` as the exemplar for temp path isolation.
- Run the unit and UI smoke commands above.

## Done criteria

- [ ] UI-test launches pass `FLOWBAR_UI_TEST_ROOT` or an equivalent env var.
- [ ] UI-test app configures `AppPaths` overrides before any `LibraryStore()` is constructed.
- [ ] `testDownloadAndPlaybackForKnownURL` runs only with `RUN_NETWORK_TESTS=1`.
- [ ] The default full test command with `RUN_NETWORK_TESTS=0` does not start a network download.
- [ ] No files outside the in-scope list and `plans/README.md` are modified.
- [ ] `plans/README.md` status row updated.

## STOP conditions

Stop and report back if:

- The UI-test app no longer has a separate `FlowBarUITestApp` / `UITestAppDelegate` path.
- You cannot configure `AppPaths` before `LibraryStore()` is constructed without touching production launch behavior.
- UI-test path isolation appears to require changing `LibraryStore` semantics.
- The full test command starts a YouTube download even with `RUN_NETWORK_TESTS=0`.

## Maintenance notes

Future UI tests that create tracks, downloads, or settings must use the same temp root. Reviewers should scrutinize the launch order carefully: the override must happen before service construction, not after.

