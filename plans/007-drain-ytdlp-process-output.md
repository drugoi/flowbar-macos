# Plan 007: Drain yt-dlp process output reliably

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report; do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer tells you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat 6fa18b8..HEAD -- Sources/FlowBar/Services/YtDlpClient.swift Tests/FlowBarTests`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/006-structured-ytdlp-metadata.md`
- **Category**: bug
- **Planned at**: commit `6fa18b8`, 2026-06-22

## Why this matters

The async yt-dlp runner accumulates stdout/stderr using `readabilityHandler`, then clears the handlers in the process termination handler and resumes with whatever string has been appended so far. Readability handlers are asynchronous; without a final pipe drain at termination, the last bytes of stdout or stderr can be missed. That can cause invalid metadata output, missing progress/error text, and misleading user-facing failure messages.

## Current state

- The async runner sets readability handlers:

```swift
// Sources/FlowBar/Services/YtDlpClient.swift:314
outputHandle.readabilityHandler = { handle in
    let data = handle.availableData
    guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
    outputQueue.async {
        output.append(chunk)
    }
```

- The stderr handler follows the same pattern:

```swift
// Sources/FlowBar/Services/YtDlpClient.swift:329
errorHandle.readabilityHandler = { handle in
    let data = handle.availableData
    guard !data.isEmpty, let chunk = String(data: data, encoding: .utf8) else { return }
    outputQueue.async {
        output.append(chunk)
    }
}
```

- On termination, handlers are removed and the queued string is returned, but there is no final `readDataToEndOfFile` drain:

```swift
// Sources/FlowBar/Services/YtDlpClient.swift:338
process.terminationHandler = { proc in
    outputHandle.readabilityHandler = nil
    errorHandle.readabilityHandler = nil
    outputQueue.async {
        if proc.terminationStatus == 0 {
            continuation.resume(returning: output)
        } else {
            continuation.resume(throwing: YtDlpError.executionFailed(output))
        }
    }
}
```

- Synchronous helper methods do drain the pipe after process exit:

```swift
// Sources/FlowBar/Services/YtDlpClient.swift:365
let data = pipe.fileHandleForReading.readDataToEndOfFile()
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Focused tests | `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests/YtDlpProcessRunnerTests` | exits 0 |
| Unit tests | `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests` | exits 0 |
| Full tests | `RUN_NETWORK_TESTS=0 xcodebuild -scheme FlowBar -destination 'platform=macOS' test` | exits 0 or documented UI Accessibility skips only |

## Scope

**In scope**:

- `Sources/FlowBar/Services/YtDlpClient.swift`
- `Tests/FlowBarTests/YtDlpProcessRunnerTests.swift` (create)

**Out of scope**:

- Changing yt-dlp arguments.
- Changing metadata parsing from text to JSON; plan 006 handles that.
- Replacing `Process` with a third-party process library.
- Adding real network/download tests.

## Git workflow

- Branch: `codex/007-drain-ytdlp-process-output`
- Commit style if committing: `fix: drain yt-dlp process output`
- Do not push or open a PR unless instructed.

## Steps

### Step 1: Extract a small testable process-runner boundary

Refactor the private `run(_ args:progress:)` implementation enough to test output capture without invoking yt-dlp. A reasonable shape is an internal helper in `YtDlpClient.swift`, for example:

```swift
struct YtDlpProcessRunner {
    static func run(executableURL: URL, arguments: [String], progress: ((Double?) -> Void)? = nil) async throws -> String
}
```

Keep it in the same file unless the code becomes too large. Production `YtDlpClient.run(_:)` should call this helper after resolving the executable URL and arguments.

**Verify**: `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests` -> exits 0.

### Step 2: Drain stdout and stderr after process termination

In the process termination handler:

1. Set both readability handlers to nil.
2. Drain any remaining data from both file handles with `readDataToEndOfFile()`.
3. Append those chunks through the same synchronization mechanism used by readability handlers.
4. Resume the continuation only after all queued appends and final drain appends have completed.

Protect against double-resume if cancellation and termination race. A simple lock/queue-isolated `didResume` flag is acceptable.

Do not block the main actor. The runner should remain usable from async tasks.

**Verify**: `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests` -> exits 0.

### Step 3: Preserve cancellation behavior

Keep `withTaskCancellationHandler` and `process.terminate()` behavior. If you add a `didResume` guard, cancellation must not resume the continuation directly; termination should still produce the final cancellation/failure outcome once the process exits.

**Verify**: add a focused test that starts a long-running process, cancels the task, and asserts it completes without hanging or double-resuming. Run `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests/YtDlpProcessRunnerTests` -> exits 0.

### Step 4: Add offline process output tests

Create `Tests/FlowBarTests/YtDlpProcessRunnerTests.swift`.

Use `/bin/sh` only in tests to produce controlled stdout/stderr, for example:

```sh
/bin/sh -c 'printf "stdout-final"; printf "stderr-final" >&2'
```

Test cases:

- Successful process returns stdout and stderr chunks, including final bytes.
- Failing process throws `YtDlpError.executionFailed` and the error message includes stderr final bytes.
- Cancelled process exits without hanging.

Keep the helper internal and testable via `@testable import FlowBar`; do not expose it in app UI.

**Verify**: `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests/YtDlpProcessRunnerTests` -> exits 0.

## Test plan

- New offline tests in `YtDlpProcessRunnerTests`.
- Existing parser tests from plan 006 should still pass.
- No real yt-dlp or YouTube network access is needed.

## Done criteria

- [ ] Async process runner drains stdout and stderr after process termination.
- [ ] Continuation cannot be resumed twice during cancellation/termination races.
- [ ] Offline tests cover success output, failure output, and cancellation.
- [ ] Unit tests pass.
- [ ] `plans/README.md` status row updated.

## STOP conditions

Stop and report back if:

- Plan 006 has not landed and this refactor would conflict with metadata parsing changes.
- The process runner cannot be made testable without exposing broad public API.
- Cancellation tests hang or are flaky after two reasonable attempts.
- Capturing both stdout and stderr together breaks progress parsing in downloads.

## Maintenance notes

Reviewer focus should be on continuation lifetime, output synchronization, and cancellation. Future process-running changes should keep offline tests; relying on real yt-dlp for this behavior will make failures slow and non-deterministic.

