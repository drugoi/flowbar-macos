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
- [ ] Decide minimum macOS version and update settings.
- [ ] Create app target with `MenuBarExtra` and popover layout skeleton.
- [ ] Implement `Track`, `Library`, and download state enums.
- [ ] Add `Featured` seed list (placeholder IDs/URLs).

### M2: Persistence + URL Validation
- [ ] Implement `LibraryStore` with JSON schema versioning.
- [ ] Add `URLValidator` with allowlisted hosts and normalization.
- [ ] Implement `DiagnosticsLogger` + copy-to-clipboard.

### M3: Resolve + Download
- [ ] Integrate `yt-dlp` wrapper using argument arrays (no shell execution).
- [ ] Extract metadata (title, duration) and select audio-only format.
- [ ] Download audio to Caches with progress updates and cancel support.

### M4: Playback + Resume
- [ ] Add `PlaybackController` using `AVAudioPlayer`.
- [ ] Persist playback position periodically and on pause/stop/quit.
- [ ] Enforce single-track playback.

### M5: UI Polish + UX
- [ ] Bind UI to state and service events.
- [ ] Add error surfaces with Retry and Diagnostics.
- [ ] Add search filtering and keyboard shortcuts.

### M6: Distribution Prep
- [ ] Document code signing and notarization steps.
- [ ] Homebrew cask packaging outline.

## Immediate Next Steps (This Sprint)
- Scaffold `Sources/LongPlay` with core models and persistence stubs.
- Add URL validation, diagnostics logger, and JSON storage layout.
- Draft menu bar SwiftUI skeleton (no styling yet).
