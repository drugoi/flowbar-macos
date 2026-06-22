# Plan 009: Update cache policy documentation

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report; do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer tells you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat 6fa18b8..HEAD -- docs/cache-policy.md docs/release-checklist.md docs/distribution.md README.md Sources/FlowBar/Models/Library.swift Sources/FlowBar/UI/MenuBarContentView.swift`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P3
- **Effort**: S
- **Risk**: LOW
- **Depends on**: `plans/003-cache-file-lifecycle-path-safety.md`
- **Category**: docs
- **Planned at**: commit `6fa18b8`, 2026-06-22

## Why this matters

The cache policy docs say FlowBar uses manual-only cache management with no automatic eviction or size limit. The current app model and Settings UI include a default 5 GB cache limit, a minimum 1 GB limit, and automatic least-recently-played eviction. Stale docs are worse than missing docs for release/support work because maintainers will make incorrect promises and checklist decisions.

## Current state

- Stale docs:

```markdown
// docs/cache-policy.md:3
FlowBar uses a manual cache policy for the MVP:
- Downloads are stored in `~/Library/Caches/FlowBar/`.
- There is no automatic eviction or size limit.
- Users can remove individual downloads or clear all downloads from the Utilities section.
```

- Current model has cache limits:

```swift
// Sources/FlowBar/Models/Library.swift:4
static let currentSchemaVersion = 2
static let defaultCacheLimitBytes: Int64 = 5 * 1024 * 1024 * 1024
static let minimumCacheLimitBytes: Int64 = 1 * 1024 * 1024 * 1024
```

- Current UI exposes cache limit and auto-eviction:

```swift
// Sources/FlowBar/UI/MenuBarContentView.swift:730
SettingsCard(title: "Storage") {
...
Text("Cache limit")
Text("Auto-evict least-recently-played downloads.")
...
Stepper(value: cacheLimitGBBinding, in: 1...50, step: 1)
```

- Release checklist does not mention cache policy verification:

```markdown
// docs/release-checklist.md:21
## Distribution
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Stale text check | `rg -n "manual-only|manual cache policy|no automatic eviction|no automatic eviction or size limit" docs README.md` | no stale matches |
| Current values check | `rg -n "5 GB|1 GB|least-recently-played|cache limit|Clear Downloads" docs/cache-policy.md docs/release-checklist.md` | matches updated docs |
| Markdown file check | `sed -n '1,220p' docs/cache-policy.md` | shows current cache behavior clearly |

## Scope

**In scope**:

- `docs/cache-policy.md`
- `docs/release-checklist.md`
- `docs/distribution.md` only if it repeats stale cache claims
- `README.md` only if it repeats stale cache claims

**Out of scope**:

- Changing cache implementation.
- Changing UI copy.
- Updating screenshots.
- Editing PRD historical scope unless the maintainer explicitly wants PRD updated to reflect post-MVP changes.

## Git workflow

- Branch: `codex/009-update-cache-policy-docs`
- Commit style if committing: `docs: update cache policy`
- Do not push or open a PR unless instructed.

## Steps

### Step 1: Rewrite cache-policy.md to match current behavior

Update `docs/cache-policy.md` to state:

- Downloads are stored in `~/Library/Caches/FlowBar/`.
- The default cache limit is 5 GB.
- The minimum configurable cache limit is 1 GB.
- The Settings UI allows 1-50 GB.
- FlowBar auto-evicts least-recently-played downloaded tracks when cache size exceeds the limit.
- The currently playing track is excluded from eviction when the app enforces limits after a download.
- Users can remove individual downloads and clear all downloads.

If plan 003 has landed, also mention that per-track delete removes its cached audio and cache deletion is confined to FlowBar's cache directory.

**Verify**: `rg -n "manual-only|manual cache policy|no automatic eviction|no automatic eviction or size limit" docs/cache-policy.md` -> no matches.

### Step 2: Update release checklist

Add a short cache-management checklist under Build + Test or a new Storage section:

- Confirm cache limit UI displays expected default.
- Smoke test Clear Downloads.
- If changing cache code, run `FlowBarTests/LibraryStoreCacheEvictionTests`.

Do not add a manual step that requires deleting real user data.

**Verify**: `rg -n "LibraryStoreCacheEvictionTests|Cache limit|Clear Downloads" docs/release-checklist.md` -> matches.

### Step 3: Check for other stale cache claims

Search docs and README for old manual-only language. Update only if the text is actively wrong.

**Verify**: `rg -n "manual-only|manual cache policy|no automatic eviction|no automatic eviction or size limit" docs README.md` -> no stale matches.

## Test plan

- This is a docs-only plan. Use the `rg` commands as machine-checkable verification.
- No app build is required unless source files are touched accidentally; source files should not be modified.

## Done criteria

- [ ] `docs/cache-policy.md` describes current automatic LRU cache eviction and configurable limits.
- [ ] `docs/release-checklist.md` includes cache-management verification.
- [ ] No stale manual-only cache claims remain in docs or README.
- [ ] No source files are modified.
- [ ] `plans/README.md` status row updated.

## STOP conditions

Stop and report back if:

- Plan 003 changes cache semantics in a way that contradicts the current values.
- Source code values no longer match 5 GB default, 1 GB minimum, or 1-50 GB UI range.
- The maintainer wants `docs/prd.md` preserved as historical MVP scope and not updated; do not edit it without explicit direction.

## Maintenance notes

Future cache changes should update docs in the same PR. Reviewers should compare docs against `Library.defaultCacheLimitBytes`, `Library.minimumCacheLimitBytes`, and `cacheLimitGBBinding`.

