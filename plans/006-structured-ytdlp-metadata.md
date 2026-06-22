# Plan 006: Parse yt-dlp metadata as structured JSON

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report; do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer tells you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat 6fa18b8..HEAD -- Sources/FlowBar/Services/YtDlpClient.swift Sources/FlowBar/Services/MetadataResolver.swift Tests/FlowBarTests`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/001-isolate-ui-tests.md`
- **Category**: bug
- **Planned at**: commit `6fa18b8`, 2026-06-22

## Why this matters

`YtDlpClient.resolveMetadata` currently parses two text lines from yt-dlp and discards any output line starting with `[`. A valid YouTube title can begin with `[`, and yt-dlp can emit warnings or extra lines in ways that make line-count parsing brittle. yt-dlp can produce structured JSON, so FlowBar should decode metadata instead of scraping human-oriented text output.

## Current state

- Metadata currently requests two printed fields:

```swift
// Sources/FlowBar/Services/YtDlpClient.swift:152
let args = baseArgs(playerClients: "web") + [
    "--print", "%(title)s",
    "--print", "%(duration)s",
    "--skip-download",
    "--quiet",
```

- The parser filters non-empty lines and drops any line starting with `[`:

```swift
// Sources/FlowBar/Services/YtDlpClient.swift:165
let parsedLines = output
    .split(separator: "\n")
    .map(String.init)
    .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
    .filter { line in
        guard !line.isEmpty else { return false }
        if line.hasPrefix("WARNING:") || line.hasPrefix("[") || line.hasPrefix("ERROR:") {
            return false
        }
        return true
    }
```

- The parser rejects more than two lines:

```swift
// Sources/FlowBar/Services/YtDlpClient.swift:179
guard parsedLines.count <= 2 else {
    throw YtDlpError.invalidOutput
}
```

- There are no unit tests for `YtDlpClient` metadata parsing:

```text
rg -n "YtDlpClient" Tests
# no test file exercises metadata parsing
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Focused tests | `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests/YtDlpClientMetadataTests` | exits 0 |
| Unit tests | `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests` | exits 0 |
| Full tests | `RUN_NETWORK_TESTS=0 xcodebuild -scheme FlowBar -destination 'platform=macOS' test` | exits 0 or documented UI Accessibility skips only |

## Scope

**In scope**:

- `Sources/FlowBar/Services/YtDlpClient.swift`
- `Sources/FlowBar/Services/MetadataResolver.swift` only if error mapping needs a small adjustment
- `Tests/FlowBarTests/YtDlpClientMetadataTests.swift` (create)

**Out of scope**:

- Download format selection.
- Process output draining; plan 007 handles that.
- Changing user-facing metadata fallback behavior in `MenuBarContentView`.
- Adding real network tests for yt-dlp.

## Git workflow

- Branch: `codex/006-structured-ytdlp-metadata`
- Commit style if committing: `fix: parse yt-dlp metadata json`
- Do not push or open a PR unless instructed.

## Steps

### Step 1: Add a unit-testable JSON parser

In `YtDlpClient.swift`, add an internal static helper, visible to `@testable import FlowBar`, similar to:

```swift
static func parseMetadataJSON(_ output: String) throws -> YtDlpMetadata
```

Decode a small `Decodable` struct with:

- `title: String`
- `duration: Double?`

Trim title whitespace and reject empty titles with `YtDlpError.invalidOutput`. Accept missing/null duration as nil.

If yt-dlp emits non-JSON warnings before JSON, prefer making the run command suppress warnings rather than implementing ad hoc text stripping. If stripping is still required, only parse the first complete JSON object and add tests for that behavior.

**Verify**: create `Tests/FlowBarTests/YtDlpClientMetadataTests.swift` with parser tests and run `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests/YtDlpClientMetadataTests` -> exits 0.

### Step 2: Switch resolveMetadata to JSON output

Change `resolveMetadata(url:)` to ask yt-dlp for JSON metadata. Prefer `--dump-single-json` with `--skip-download`, `--quiet`, `--no-playlist`, `--socket-timeout 8`, `--retries 1`, and `--no-warnings`.

Do not change `baseArgs(playerClients:)` unless required. Keep the returned public type `YtDlpMetadata(title:durationSeconds:)` unchanged.

**Verify**: `rg -n -- "--print|%\\(title\\)s|%\\(duration\\)s" Sources/FlowBar/Services/YtDlpClient.swift` -> no matches in `resolveMetadata`.

### Step 3: Add regression tests for title edge cases

Add tests covering:

- JSON with title `"[Focus] Deep Work Mix"` and duration `3600`.
- JSON with title containing leading/trailing whitespace.
- JSON with `duration: null`.
- JSON with empty or whitespace-only title throws `YtDlpError.invalidOutput`.
- Invalid JSON throws `YtDlpError.invalidOutput`.

Keep tests offline; do not invoke the real `yt-dlp` binary.

**Verify**: `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests/YtDlpClientMetadataTests` -> exits 0.

### Step 4: Run the unit suite

Run all unit tests to ensure URL validation, library decoding, cache eviction, and parser tests still pass together.

**Verify**: `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests` -> exits 0.

## Test plan

- New offline parser tests in `YtDlpClientMetadataTests`.
- Existing `MetadataResolver` behavior should be preserved because it wraps `client.resolveMetadata(url:)`.
- No real YouTube or network test is required for this plan.

## Done criteria

- [ ] `resolveMetadata(url:)` uses structured JSON output from yt-dlp.
- [ ] Text-line parsing and `line.hasPrefix("[")` filtering are removed from metadata parsing.
- [ ] Offline tests cover bracket-leading titles, null duration, empty title, and invalid JSON.
- [ ] Unit tests pass.
- [ ] `plans/README.md` status row updated.

## STOP conditions

Stop and report back if:

- The bundled yt-dlp version targeted by the repo does not support the chosen JSON output flag.
- JSON output includes fields under names other than `title` and `duration` for YouTube videos.
- Making the parser testable requires exposing broad process-running internals instead of a small parser helper.
- Plan 007 has already rewritten the process runner in a way that changes how `resolveMetadata` should be updated.

## Maintenance notes

Keep the JSON parser narrow. Do not decode the full yt-dlp schema; only decode fields FlowBar uses. Future metadata fields should add parser tests first.

