# Plan 002: Make production FlowBar a menu-bar-only app

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report; do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer tells you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat 6fa18b8..HEAD -- Config/Info.plist Sources/FlowBar/UI/FlowBarApp.swift project.yml FlowBar.xcodeproj`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/001-isolate-ui-tests.md`
- **Category**: bug
- **Planned at**: commit `6fa18b8`, 2026-06-22

## Why this matters

FlowBar is documented and architected as a menu bar app with no Dock presence. The production `Info.plist` currently does not set `LSUIElement`, and production launch does not set an accessory activation policy either. That means a normal build can show as a regular Dock app, contradicting the PRD and README.

## Current state

- PRD requirement:

```markdown
// docs/prd.md:105
- App runs exclusively from the menu bar.
- No Dock icon (accessory app / agent).
```

- `Config/Info.plist` currently contains bundle and Sparkle keys but no `LSUIElement`:

```xml
<!-- Config/Info.plist:21 -->
<key>SUFeedURL</key>
<string>https://flowbar.drugoi.dev/appcast.xml</string>
<key>SUPublicEDKey</key>
<string>4ztKXXySBM8HH4ioS4AJrP5MJuMM2BMX5o4Zd+qpv/M=</string>
```

- A read-only check during audit returned no `LSUIElement` key:

```text
plutil -extract LSUIElement raw Config/Info.plist
Config/Info.plist: Could not extract value, error: No value at that key path or invalid key path: LSUIElement
```

- UI tests deliberately switch to a regular app/window path; preserve that:

```swift
// Sources/FlowBar/UI/FlowBarApp.swift:9
if isUITestRun || env["UITESTING"] == "1" || ProcessInfo.processInfo.arguments.contains("-ui-testing") {
    NSApplication.shared.setActivationPolicy(.regular)
    NSRunningApplication.current.activate(options: [.activateIgnoringOtherApps, .activateAllWindows])
    FlowBarUITestApp.main()
}
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Plist lint | `plutil -lint Config/Info.plist` | `Config/Info.plist: OK` |
| Key check | `plutil -extract LSUIElement raw Config/Info.plist` | prints `true` |
| Generate project | `xcodegen generate` | exits 0 |
| Build | `xcodebuild -scheme FlowBar -configuration Debug -derivedDataPath build` | exits 0 |
| UI smoke | `RUN_NETWORK_TESTS=0 xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarUITests/testMenuBarOpensPopover` | exits 0 or skips only for Accessibility/menu-bar runner limitations |

## Scope

**In scope**:

- `Config/Info.plist`
- `Sources/FlowBar/UI/FlowBarApp.swift` only if the existing UI-test regular activation path needs preserving after the plist change
- `project.yml` only if XcodeGen needs explicit plist-related settings
- Generated `FlowBar.xcodeproj` only if `xcodegen generate` changes it

**Out of scope**:

- Redesigning app launch.
- Removing the UI-test regular window path.
- Changing Sparkle, signing, or updater configuration.

## Git workflow

- Branch: `codex/002-menu-bar-only-info`
- Commit style if committing: `fix: make flowbar menu-bar only`
- Do not push or open a PR unless instructed.

## Steps

### Step 1: Add LSUIElement to the production plist

Add this key to `Config/Info.plist`:

```xml
<key>LSUIElement</key>
<true/>
```

Place it near the other top-level app identity keys, not inside Sparkle-specific entries. Do not add `LSBackgroundOnly`; FlowBar still needs a UI popover/window.

**Verify**: `plutil -lint Config/Info.plist && plutil -extract LSUIElement raw Config/Info.plist` -> plist OK and prints `true`.

### Step 2: Regenerate the Xcode project if needed

Run XcodeGen because this repo declares `project.yml` as the source of truth and commits `FlowBar.xcodeproj`.

**Verify**: `xcodegen generate` -> exits 0.

### Step 3: Confirm UI-test activation still works

Run the UI smoke test after plan 001 has landed.

**Verify**: `RUN_NETWORK_TESTS=0 xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarUITests/testMenuBarOpensPopover` -> exits 0 or skips only for documented Accessibility/menu-bar runner reasons.

## Test plan

- No new unit test is required for a plist key.
- Use `plutil` as the machine-checkable assertion.
- Run one UI smoke test to ensure the `LSUIElement` production setting does not break the dedicated UI-test window path.

## Done criteria

- [ ] `Config/Info.plist` contains `LSUIElement` set to true.
- [ ] `plutil -lint Config/Info.plist` exits 0.
- [ ] `plutil -extract LSUIElement raw Config/Info.plist` prints `true`.
- [ ] UI-test launch still uses the regular window test harness.
- [ ] No unrelated source files are modified.
- [ ] `plans/README.md` status row updated.

## STOP conditions

Stop and report back if:

- The app has moved away from `Config/Info.plist` as the app target plist.
- Adding `LSUIElement` makes the UI-test harness unable to open its test window after plan 001.
- XcodeGen removes or rewrites unrelated project settings unexpectedly.

## Maintenance notes

Reviewers should check the built app manually once before release: launch FlowBar and confirm it appears only in the menu bar, not the Dock. Keep the UI-test regular activation path separate from production behavior.

