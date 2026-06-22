# Plan 003: Make cache deletion complete and path-confined

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report; do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer tells you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat 6fa18b8..HEAD -- Sources/FlowBar/Services/LibraryStore.swift Tests/FlowBarTests/LibraryStoreCacheEvictionTests.swift Sources/FlowBar/UI/MenuBarContentView.swift Sources/FlowBar/Models/Track.swift`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/001-isolate-ui-tests.md`
- **Category**: bug / security
- **Planned at**: commit `6fa18b8`, 2026-06-22

## Why this matters

The UI tells users that deleting a track removes the track and its downloaded audio, but `LibraryStore.removeTrack` only removes the JSON entry. Separately, `removeDownload` and cache eviction trust the persisted `localFilePath` and call `FileManager.removeItem(atPath:)` directly. A corrupted or hand-edited library file could point `localFilePath` outside FlowBar's cache and cause FlowBar to delete an arbitrary user file when removing downloads or enforcing cache limits.

## Current state

- The delete dialog promises download removal:

```swift
// Sources/FlowBar/UI/MenuBarContentView.swift:200
DialogCard(title: "Delete track?", message: "This removes the track and any downloaded audio.") {
```

- The confirmed delete only removes the library record:

```swift
// Sources/FlowBar/UI/MenuBarContentView.swift:209
libraryStore.removeTrack(deleteCandidate)
```

- `LibraryStore.removeTrack` does not delete a cached file:

```swift
// Sources/FlowBar/Services/LibraryStore.swift:85
func removeTrack(_ track: Track) {
    library.userLibrary.removeAll { $0.id == track.id }
    save()
}
```

- `removeDownload` deletes the path stored in the track:

```swift
// Sources/FlowBar/Services/LibraryStore.swift:90
func removeDownload(for track: Track) {
    guard let path = track.localFilePath else { return }
    do {
        try FileManager.default.removeItem(atPath: path)
```

- Cache eviction also deletes persisted paths:

```swift
// Sources/FlowBar/Services/LibraryStore.swift:177
guard let path = track.localFilePath else { continue }
...
try FileManager.default.removeItem(atPath: path)
```

- The cache directory helper already centralizes the intended deletion boundary:

```swift
// Sources/FlowBar/Services/AppPaths.swift:23
static func cachesDirectory() throws -> URL {
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Focused tests | `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests/LibraryStoreCacheEvictionTests` | exits 0 |
| Unit tests | `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests` | exits 0 |
| Full tests | `RUN_NETWORK_TESTS=0 xcodebuild -scheme FlowBar -destination 'platform=macOS' test` | exits 0 or only documented UI runner skips |

## Scope

**In scope**:

- `Sources/FlowBar/Services/LibraryStore.swift`
- `Tests/FlowBarTests/LibraryStoreCacheEvictionTests.swift`
- `Sources/FlowBar/UI/MenuBarContentView.swift` only if UI call sites need a renamed API

**Out of scope**:

- Changing the `Track` JSON schema.
- Moving the cache directory.
- Rewriting cache eviction policy beyond path confinement.
- Changing playback or download manager behavior.

## Git workflow

- Branch: `codex/003-cache-file-lifecycle-path-safety`
- Commit style if committing: `fix: confine cache file deletion`
- Do not push or open a PR unless instructed.

## Steps

### Step 1: Add a single safe cached-file deletion path

In `LibraryStore`, add a private helper used by all per-track cache deletion paths. It should:

- Return nil when `track.localFilePath` is nil.
- Resolve the cache directory with `AppPaths.cachesDirectory()`.
- Convert the persisted path to a file URL.
- Standardize or resolve symlinks for both the cache directory and target path.
- Confirm the target is inside the FlowBar cache directory before deleting.
- If the target path is outside the cache directory, log a warning with the track video ID only and do not delete the file.

Keep user-entered URLs out of warning text unless already used elsewhere; diagnostics currently may include URLs, but this helper does not need them.

**Verify**: `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests/LibraryStoreCacheEvictionTests` -> exits 0.

### Step 2: Make removeDownload use the safe helper

Update `removeDownload(for:)` so it deletes only through the safe helper. Whether or not the file existed, if the track points inside FlowBar's cache, reset the track's download state and save. If the path is outside the cache, leave the external file untouched and reset the track only if that is necessary to recover from corrupted state; log that recovery.

Do not call `FileManager.removeItem(atPath:)` directly from this method anymore.

**Verify**: `rg -n "removeItem\\(atPath:" Sources/FlowBar/Services/LibraryStore.swift` -> only allowed remaining match is in the shared safe helper, not in `removeDownload` or duplicated call sites.

### Step 3: Make removeTrack remove its cached file before deleting the record

Update `removeTrack(_:)` to remove the associated cached file through the same safe helper before removing the track from `library.userLibrary`. Preserve existing behavior that the track record is removed even if the cached file is already missing. If deletion fails for a file inside the cache, set `lastError`, log the failure, and do not silently claim success.

**Verify**: `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests/LibraryStoreCacheEvictionTests` -> exits 0.

### Step 4: Make cache eviction use the same path confinement

Update `enforceCacheLimit(excludingTrackId:)` so it cannot delete paths outside `AppPaths.cachesDirectory()`. Reuse the helper or extract a second private helper if the eviction code needs to know file size before deletion. Keep the LRU candidate ordering unchanged.

**Verify**: `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests/LibraryStoreCacheEvictionTests` -> exits 0.

### Step 5: Add regression tests

In `LibraryStoreCacheEvictionTests`, add tests covering:

- `removeTrack(_:)` removes a downloaded file under the temp caches directory and removes the track from the library.
- `removeDownload(for:)` does not delete a file outside the temp caches directory when `localFilePath` is corrupted.
- `enforceCacheLimit(excludingTrackId:)` does not delete outside-cache paths and still handles inside-cache candidates.

Follow the existing temp directory setup in that file.

**Verify**: `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests/LibraryStoreCacheEvictionTests` -> exits 0 and includes the new tests.

## Test plan

- Extend `LibraryStoreCacheEvictionTests`.
- Use temp support/cache directories via existing `AppPaths.override...` pattern.
- Add at least one outside-cache file under the temp root but not under the cache directory, then assert it still exists after the operation.

## Done criteria

- [ ] Deleting a track removes its cached audio file when the file is inside FlowBar's cache.
- [ ] Per-track download removal and eviction cannot delete files outside `AppPaths.cachesDirectory()`.
- [ ] Existing LRU cache eviction behavior still passes.
- [ ] Focused and full unit tests pass.
- [ ] No JSON schema migration is introduced.
- [ ] `plans/README.md` status row updated.

## STOP conditions

Stop and report back if:

- `localFilePath` has been removed or replaced by a different cache identity model.
- Safe path confinement appears to require changing the persisted `Track` schema.
- Deleting missing files is currently relied on to surface a user-facing error that this plan would suppress.
- Tests cannot isolate cache paths because plan 001 has not landed.

## Maintenance notes

Any future method that deletes cached media should go through the same helper. Reviewers should look for direct `FileManager.removeItem(atPath:)` calls in `LibraryStore` and reject new ones unless they are confined to the shared helper.

