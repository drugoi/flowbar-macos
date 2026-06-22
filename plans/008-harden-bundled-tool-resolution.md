# Plan 008: Harden bundled tool resolution at runtime

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report; do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer tells you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat 6fa18b8..HEAD -- Sources/FlowBar/Services/YtDlpClient.swift Sources/FlowBar/UI/MenuBarContentView.swift scripts/fetch-yt-dlp.sh scripts/fetch-ffmpeg.sh scripts/fetch-deno.sh docs/distribution.md`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: S-M
- **Risk**: MED
- **Depends on**: `plans/004-pin-verify-bundled-tools.md`
- **Category**: security / bug
- **Planned at**: commit `6fa18b8`, 2026-06-22

## Why this matters

FlowBar is documented as shipping yt-dlp, ffmpeg, ffprobe, and Deno inside the app bundle so users do not need Homebrew or PATH setup. At runtime, however, `YtDlpClient` can fall back to `/usr/bin/env yt-dlp`, which may execute an unrelated user-installed binary. It also attempts to chmod the bundled yt-dlp at runtime; a signed/notarized app should ship executable permissions correctly and fail clearly if the bundle is damaged.

## Current state

- Distribution docs promise bundled tools:

```markdown
// docs/distribution.md:49
- `yt-dlp` is fetched at build time from `https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos` into `Resources/bin/yt-dlp`.
- `ffmpeg` and `ffprobe` are fetched at build time into `Resources/bin/` for audio conversion.
```

- `YtDlpClient.isAvailable()` tries to chmod bundled yt-dlp if it is not executable:

```swift
// Sources/FlowBar/Services/YtDlpClient.swift:78
if !FileManager.default.isExecutableFile(atPath: bundled.path) {
    DiagnosticsLogger.shared.log(level: "warning", message: "yt-dlp not executable, attempting to fix permissions.")
    do {
        try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: bundled.path)
```

- If no bundled executable URL exists, `isAvailable()` and `fetchVersion()` use `/usr/bin/env`:

```swift
// Sources/FlowBar/Services/YtDlpClient.swift:94
let process = Process()
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = [executable, "--version"]
```

- Async execution also falls back to `/usr/bin/env`:

```swift
// Sources/FlowBar/Services/YtDlpClient.swift:291
process.executableURL = URL(fileURLWithPath: "/usr/bin/env")
process.arguments = [executable] + args
```

- Error copy currently says PATH:

```swift
// Sources/FlowBar/Services/YtDlpClient.swift:11
return "yt-dlp is not installed or not found in PATH."
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Focused tests | `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests/YtDlpToolResolutionTests` | exits 0 |
| Unit tests | `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests` | exits 0 |
| Source check | `rg -n "/usr/bin/env|setAttributes\\(\\[\\.posixPermissions" Sources/FlowBar/Services/YtDlpClient.swift` | no production fallback/chmod matches, or only explicit test/development fallback guarded by a named option |
| Build | `xcodebuild -scheme FlowBar -configuration Debug -derivedDataPath build` | exits 0 |

## Scope

**In scope**:

- `Sources/FlowBar/Services/YtDlpClient.swift`
- `Sources/FlowBar/UI/MenuBarContentView.swift` only for user-facing error copy if needed
- `Tests/FlowBarTests/YtDlpToolResolutionTests.swift` (create)
- Fetch scripts only if permissions are not set reliably after plan 004

**Out of scope**:

- Removing bundled tools.
- Changing download format or metadata arguments.
- Replacing Process execution.
- Requiring Homebrew at runtime.

## Git workflow

- Branch: `codex/008-harden-bundled-tool-resolution`
- Commit style if committing: `fix: require bundled yt-dlp at runtime`
- Do not push or open a PR unless instructed.

## Steps

### Step 1: Introduce an explicit tool resolution policy

Add a small explicit policy to `YtDlpClient`, for example:

```swift
enum ToolResolutionMode {
    case bundledOnly
    case bundledOrPATH
}
```

Default `YtDlpClient()` should use `.bundledOnly`. If tests or local developer utilities need PATH fallback, they must opt in explicitly with `.bundledOrPATH`. Do not let production UI call sites use PATH fallback.

For testability, factor executable URL resolution into a small internal helper that can be tested with temp files and injected bundle URLs.

**Verify**: `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests` -> exits 0.

### Step 2: Remove runtime chmod repair

Change `isAvailable()` so a bundled yt-dlp that exists but is not executable logs an error and returns false. Do not call `FileManager.setAttributes([.posixPermissions: ...])` at runtime.

Ensure fetch scripts still `chmod +x` downloaded tools at build time. If plan 004 changed output hooks, preserve chmod behavior there.

**Verify**: `rg -n "setAttributes\\(\\[\\.posixPermissions|attempting to fix permissions" Sources/FlowBar/Services/YtDlpClient.swift` -> no matches.

### Step 3: Make bundled-only failures clear

Update `YtDlpError.notInstalled` and UI messages so they do not tell users to fix PATH. Suggested copy:

```text
Bundled yt-dlp is missing or cannot run. Reinstall or update FlowBar.
```

Keep the existing `MenuBarContentView` notice consistent:

```swift
// Sources/FlowBar/UI/MenuBarContentView.swift:124
title: "yt-dlp not found",
message: "Bundled binary missing. Reinstall or update FlowBar.",
```

**Verify**: `rg -n "PATH|Homebrew|not installed" Sources/FlowBar docs README.md` -> no runtime user-facing instruction implies Homebrew/PATH is required.

### Step 4: Guard any remaining PATH fallback

If you keep `/usr/bin/env` fallback for local tests or development, it must be unreachable from normal app construction. Enforce this with tests:

- Default `YtDlpClient()` or default resolver mode resolves bundled only.
- PATH fallback is used only when the explicit fallback mode is passed.
- Non-executable bundled file returns unavailable rather than chmodding.

Use temp files for resolver tests; do not invoke real yt-dlp.

**Verify**: `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests/YtDlpToolResolutionTests` -> exits 0.

## Test plan

- New offline resolver tests in `YtDlpToolResolutionTests`.
- Unit suite for parser/process tests from plans 006 and 007.
- Debug build to ensure bundled executable paths still resolve after Xcode prebuild scripts copy resources.

## Done criteria

- [ ] Production `YtDlpClient()` requires bundled yt-dlp.
- [ ] Runtime no longer chmods bundled executables.
- [ ] PATH fallback, if retained, is explicit and covered by tests.
- [ ] User-facing missing-tool copy points to reinstall/update, not Homebrew or PATH.
- [ ] Unit tests and Debug build pass.
- [ ] `plans/README.md` status row updated.

## STOP conditions

Stop and report back if:

- Plan 004 has not landed and fetch scripts still cannot guarantee executable permissions.
- Xcode Debug builds cannot bundle yt-dlp reliably, making bundled-only mode break normal development.
- Tests require invoking the real user PATH `yt-dlp`.
- Removing PATH fallback breaks an explicitly supported distribution mode documented elsewhere.

## Maintenance notes

Any future "custom yt-dlp path" feature should be explicit user preference with clear trust boundaries. Do not reintroduce silent PATH fallback for production.

