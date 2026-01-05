# LongPlay Implementation Plan

## PRD Analysis (Condensed)
- Product: macOS menu bar app (no Dock icon) with SwiftUI `MenuBarExtra` and a compact popover.
- Core flows: add YouTube URL -> resolve metadata -> download audio -> play from cache -> persist playback position and library.
- Must be resilient, low-resource, and responsive; download-first model avoids stream expiration.
- Storage: JSON library in Application Support, audio files in Caches, small prefs in UserDefaults.
- Key risks: `yt-dlp` integration and URL validation, cache management, and long-session playback stability.

## Architecture Overview
- App shell: SwiftUI `MenuBarExtra` + window-style popover; App runs as accessory (no Dock icon).
- Data model: `Track` + enums for download state; library is a versioned JSON file.
- Services:
  - `LibraryStore` (CRUD + persistence)
  - `URLValidator` (allowlist + normalization)
  - `MetadataResolver` (yt-dlp wrapper)
  - `DownloadManager` (progress/cancel)
  - `PlaybackController` (AVAudioPlayer, position persistence)
  - `DiagnosticsLogger` (ring buffer + copy)
- UI: Now Playing, Search, Tracks (Featured + Library), Add New, Utilities.

## Milestones and Task Checklist

### M1: App Shell + Core Models
- [x] Decide minimum macOS version and update settings.
- [x] Create app target with `MenuBarExtra` and popover layout skeleton.
- [x] Implement `Track`, `Library`, and download state enums.
- [x] Add `Featured` seed list (placeholder IDs/URLs).

### M2: Persistence + URL Validation
- [x] Implement `LibraryStore` with JSON schema versioning.
- [x] Add `URLValidator` with allowlisted hosts and normalization.
- [x] Implement `DiagnosticsLogger` + copy-to-clipboard.

### M3: Resolve + Download
- [x] Integrate `yt-dlp` wrapper using argument arrays (no shell execution).
- [x] Extract metadata (title, duration) and select audio-only format.
- [x] Download audio to Caches with progress updates and cancel support.
- [x] Detect missing `yt-dlp` and surface install guidance.
- [x] Add global error banner with retry and diagnostics for yt-dlp failures.

### M4: Playback + Resume
- [x] Add `PlaybackController` using `AVAudioPlayer`.
- [x] Persist playback position periodically and on pause/stop/quit.
- [x] Enforce single-track playback.
- [x] Ensure Stop resets persisted position to 0.
- [x] Start playback on track selection (default behavior).
- [x] Surface playback failures (missing/corrupt file) with retry and diagnostics.

### M5: UI Polish + UX
- [x] Bind UI to state and service events.
- [x] Add error surfaces with Retry and Diagnostics.
- [x] Add search filtering.
- [x] Add keyboard shortcuts.
- [x] Add confirmations for destructive actions.
- [x] Reflect app state in menu bar icon (idle/resolving/downloading/playing/paused/error).
- [x] Expand Featured list to 3–5 stable items.
- [x] Set consistent focus on open (search or URL field).
- [x] Add rename UI for library items.
- [x] Add accessibility labels for primary controls.

### M6: Distribution Prep
- [ ] Document code signing and notarization steps.
- [ ] Homebrew cask packaging outline.

### M7: Reliability + Policy
- [x] Handle no-internet / offline states with user-facing errors.
- [x] Handle removed/unavailable videos with clear messaging and retry.
- [x] Handle low disk space failures during download.
- [ ] Document cache policy (manual vs eviction) in UI or docs.

## Immediate Next Steps (This Sprint)
- [x] Scaffold `Sources/LongPlay` with core models and persistence stubs.
- [x] Add URL validation, diagnostics logger, and JSON storage layout.
- [x] Draft menu bar SwiftUI skeleton (no styling yet).
- [x] Create Xcode project and set minimum macOS target.
- [x] Wire build settings and app bundle identifier.
