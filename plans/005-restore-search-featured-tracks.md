# Plan 005: Restore library search and Featured tracks

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report; do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer tells you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat 6fa18b8..HEAD -- Sources/FlowBar/Models/Library.swift Sources/FlowBar/Models/Track.swift Sources/FlowBar/Services/LibraryStore.swift Sources/FlowBar/UI/MenuBarContentView.swift Tests/FlowBarTests Tests/FlowBarUITests docs/prd.md README.md`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P2
- **Effort**: M
- **Risk**: MED
- **Depends on**: `plans/001-isolate-ui-tests.md`
- **Category**: bug
- **Planned at**: commit `6fa18b8`, 2026-06-22

## Why this matters

FlowBar advertises a searchable library and a non-editable Featured list, but the current UI only displays `userLibrary` and does not expose a search field. The implementation plan even marks search and Featured as done, which makes this easy to miss in follow-up work. Users with more than a few tracks cannot filter the library, and first-time users see an empty app instead of the curated starting content described in the PRD.

## Current state

- README promise:

```markdown
// README.md:11
- Simple library with search
```

- PRD search and Featured requirements:

```markdown
// docs/prd.md:121
2. **Search**
   - Search field filtering Featured + My Library
3. **Tracks**
   - **Featured** (predefined list, non-editable)
   - **My Library** (user-added)
```

- PRD selected Featured videos:

```markdown
// docs/prd.md:283
1. Lofi hip hop radio (DWcJFNfaw9c)
2. Ambient space music (lCOF9LN_Zxs)
3. Classical focus mix (2OEL4P1Rz04)
```

- The current track list only shows user tracks:

```swift
// Sources/FlowBar/UI/MenuBarContentView.swift:553
if !filteredLibrary.isEmpty {
    Text("My Library")
...
ForEach(filteredLibrary) { track in
```

- `filteredLibrary` is not filtered:

```swift
// Sources/FlowBar/UI/MenuBarContentView.swift:938
private var filteredLibrary: [Track] {
    libraryStore.library.userLibrary
}
```

- The default library has no Featured seed list:

```swift
// Sources/FlowBar/Services/LibraryStore.swift:285
static func makeDefaultLibrary() -> Library {
    return Library(userLibrary: [])
}
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Generate project | `xcodegen generate` | exits 0 |
| Unit tests | `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests` | exits 0 |
| UI tests | `RUN_NETWORK_TESTS=0 xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarUITests` | exits 0 or documented UI Accessibility skips only |
| Full tests | `RUN_NETWORK_TESTS=0 xcodebuild -scheme FlowBar -destination 'platform=macOS' test` | exits 0 or documented UI Accessibility skips only |

## Scope

**In scope**:

- `Sources/FlowBar/Models/Library.swift`
- `Sources/FlowBar/Models/Track.swift` only if you need a small Codable default for new model state
- `Sources/FlowBar/Services/LibraryStore.swift`
- `Sources/FlowBar/UI/MenuBarContentView.swift`
- `Tests/FlowBarTests/*`
- `Tests/FlowBarUITests/FlowBarUITests.swift`

**Out of scope**:

- Playlist import.
- A new visual redesign of the popover.
- Changing download, playback, or metadata semantics except where required to make Featured tracks persist download state.
- Deleting or rewording PRD requirements to hide missing behavior.

## Git workflow

- Branch: `codex/005-restore-search-featured-tracks`
- Commit style if committing: `feat: restore search and featured tracks`
- Do not push or open a PR unless instructed.

## Steps

### Step 1: Add persistent Featured storage without making tracks user-editable

Preferred model: add `featuredLibrary: [Track]` to `Library`, bump `currentSchemaVersion`, and decode old libraries by seeding the PRD Featured tracks when the field is missing. Keep `userLibrary` as the only list affected by user delete/rename actions.

Use stable UUIDs for seed tracks so SwiftUI identity and persisted updates are deterministic. Use canonical YouTube URLs:

- `https://www.youtube.com/watch?v=DWcJFNfaw9c`
- `https://www.youtube.com/watch?v=lCOF9LN_Zxs`
- `https://www.youtube.com/watch?v=2OEL4P1Rz04`

If you choose a different model, it must still preserve a Featured track's downloaded state across launches and prevent Featured tracks from being deleted as user tracks.

**Verify**: add or update `LibraryDecodingTests` so decoding a schema-v2 library without Featured data produces three Featured tracks and preserves existing user tracks. Run `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests/LibraryDecodingTests` -> exits 0.

### Step 2: Teach LibraryStore to read and update both lists safely

Update `LibraryStore.trackById`, `track(withId:)`, and the private replacement logic so downloads, metadata, and playback position can update Featured tracks as well as user tracks.

Keep `removeTrack(_:)` scoped to `userLibrary` only. If a caller attempts to remove a Featured track, it should not remove it from the Featured list. If plan 003 has landed, use its safe cache removal helper for any downloaded Featured file removal path.

**Verify**: add unit coverage proving `updateTrack` can update a Featured track and `removeTrack` does not remove Featured tracks. Run `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests` -> exits 0.

### Step 3: Add a search field to the Listen tab

In `MenuBarContentView`, add `@State private var searchText = ""`. Place a compact search field in the Listen tab before `trackListSection`, matching the existing quiet SwiftUI style. The field should filter by:

- `displayName`
- `resolvedTitle`
- `videoId`

Filtering should be case-insensitive and trim whitespace. Empty search shows all tracks.

Do not reuse the Add URL `FocusField.url` for search unless you also extend the enum cleanly; avoid breaking Add form focus.

**Verify**: `xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarTests` -> exits 0.

### Step 4: Render Featured and My Library separately

Update `trackListSection` to show:

- `Featured` header and filtered Featured rows when any Featured rows match.
- `My Library` header and filtered user rows when any user rows match.
- Empty state when both filtered lists are empty.

For Featured rows, call `TrackRow` with `isUserTrack: false`, no rename action, and no delete action. Download/play/retry/cancel/remove-download actions should still work if the model supports persisted Featured download state.

**Verify**: `RUN_NETWORK_TESTS=0 xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarUITests/testTabNavigationAndEmptyState` -> exits 0 or documented UI Accessibility skip only.

### Step 5: Add UI coverage for visible search and Featured surface

Extend `FlowBarUITests` with a no-network test that launches the isolated test app, opens the Listen tab, and asserts:

- A search field exists.
- The `Featured` header exists.
- At least one known Featured title or video ID is visible.

If direct text-field accessibility is brittle, add explicit accessibility identifiers to the search field and section headers.

**Verify**: `RUN_NETWORK_TESTS=0 xcodebuild -scheme FlowBar -destination 'platform=macOS' test -only-testing:FlowBarUITests` -> exits 0 or documented UI Accessibility skips only.

## Test plan

- Unit tests for schema migration/default Featured seeding.
- Unit tests for updating Featured tracks and preventing Featured deletion.
- UI tests for search field and Featured header visibility.
- Existing URL parser, URL validator, and cache tests must still pass.

## Done criteria

- [ ] A fresh library contains the three PRD Featured tracks.
- [ ] Featured tracks are non-editable/non-deletable in UI.
- [ ] Featured download/progress/playback state can persist across launch.
- [ ] Search filters both Featured and user library by display name, resolved title, and video ID.
- [ ] Empty search shows all tracks; unmatched search shows a clear empty state.
- [ ] Unit and UI smoke tests pass with `RUN_NETWORK_TESTS=0`.
- [ ] `plans/README.md` status row updated.

## STOP conditions

Stop and report back if:

- The persisted `Library` schema has changed since this plan and already includes a Featured model.
- Preserving Featured download state requires a larger storage redesign than adding a `featuredLibrary` list.
- UI tests cannot be isolated because plan 001 is not complete.
- The PRD Featured video IDs are no longer acceptable product choices and require maintainer input.

## Maintenance notes

Future playlist/import work should decide whether imported items go into My Library only. Reviewers should check that Featured tracks cannot be deleted or renamed, but can still be downloaded and played.

