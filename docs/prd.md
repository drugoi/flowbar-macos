# LongPlay — Product Requirements Document (PRD)

**Author:** (rewrite by ChatGPT)  
**Version:** 1.1 (MVP-focused)  
**Date:** 2026-01-05  

---

## 1. Introduction

### 1.1 Vision
Provide a simple, unobtrusive, resource-light macOS menu bar app that lets users play **long-form YouTube audio** (music mixes, ambient soundscapes, long podcasts) **without keeping a browser open**, optimized for “set it and forget it” listening.

### 1.2 Product overview
**LongPlay** is a native macOS **menu bar** application (no Dock presence) with a compact **popover UI** for:
- adding YouTube links to a personal library,
- downloading audio for offline playback,
- controlling playback,
- resuming playback where the user left off.

The MVP explicitly uses a **download-first** model to avoid stream URL expiration and enable reliable long sessions.

---

## 2. The problem
Users listen to long-form audio on YouTube while working or studying. A browser-based experience is:
- resource heavy (video playback + tab overhead),
- intrusive (full window for audio-only),
- fragile for long sessions (focus/media key reliability, occasional stalls),
- non-persistent (hard to keep a curated personal library).

LongPlay provides a small, native, persistent alternative.

---

## 3. Target audience
- **Primary:** students, developers, writers, designers, office workers using YouTube as background audio.
- **Secondary:** casual listeners who want a lightweight “audio player for long YouTube videos.”

---

## 4. Goals & success metrics

### 4.1 Goals
1. **Reliable long listening**
2. **Fast access + minimal UI**
3. **Persistent personal library**
4. **Daily-use utility**

### 4.2 MVP metrics (benchmarks)
Define and validate on a baseline Apple Silicon machine (e.g., M1):
- **Idle:** CPU ~0%, RAM < 50 MB
- **Playing downloaded audio:** CPU < 1% avg, RAM < 120 MB
- **Downloading:** CPU < 10% avg (peaks allowed), RAM < 200 MB
- **Responsiveness:** popover opens < 200 ms after click (warm), < 800 ms after cold start

Product metrics:
- % users adding ≥ 1 item to **My Library**
- % sessions with successful resume from saved position
- # playback/download errors per 100 sessions (target: low and trending down)

---

## 5. MVP scope (explicit)

### 5.1 Supported (MVP)
- **YouTube VOD only** (public videos).
- Audio-only extraction and download.
- Playback from local cached audio files.
- Per-track playback position persistence + resume.
- Library management (add, rename, delete, remove download, clear downloads).
- Search + scroll within the library list.

### 5.2 Not supported (MVP)
- Live / 24-7 streams
- Login-required, members-only, paid, private, or age-restricted videos
- Playlists as input (single video URL only)
- Audio export/sharing as a user-facing feature
- Auto-updater (skipped for MVP)

---

## 6. Platform, distribution, and compliance

### 6.1 Platform
- **macOS minimum:** macOS 13.0 (Ventura) to enable modern SwiftUI APIs.
- **UI framework:** **SwiftUI**
- **App type:** menu bar app using `MenuBarExtra` with **window-style** popover UI.

### 6.2 Distribution
- **Not on Mac App Store** (direct distribution).
- MVP distribution via **Homebrew Cask**.
- Engineering should plan for **code signing and notarization** for a low-friction user install experience.

### 6.3 Policy / legal risk
- The app interacts with YouTube content using `yt-dlp`-like extraction. This may violate YouTube Terms of Service.
- This is an accepted project risk; avoid marketing language that frames the product as a “downloader.”
- Downloads are used as an **internal cache** for playback reliability.

---

## 7. User experience (MVP)

### 7.1 Menu bar behavior
- App runs exclusively from the menu bar.
- No Dock icon (accessory app / agent).
- Menu bar icon reflects app state:
  - **Idle**
  - **Resolving**
  - **Downloading**
  - **Playing**
  - **Paused**
  - **Error**

### 7.2 Popover layout (minimal)
Popover sections (top to bottom):
1. **Now Playing**
   - Track title (1–2 lines, truncation)
   - Play/Pause, Stop
   - Status line: e.g., “Downloading 42%”, “Ready offline”, “Error: …”
2. **Search**
   - Search field filtering Featured + My Library
3. **Tracks**
   - **Featured** (predefined list, non-editable)
   - **My Library** (user-added)
   - Scrollable list
   - Per-item actions (button or context menu): Play, Remove Download, Delete
4. **Add New**
   - URL field (required)
   - Display name field (optional; fallback to resolved title)
   - Add button
5. **Utilities**
   - Clear Downloads
   - Copy Diagnostics
   - Quit

### 7.3 Keyboard and focus
- Popover supports keyboard navigation:
  - ⏎ to confirm Add
  - ⎋ to close popover
  - Search focus on open is optional but should be consistent.

---

## 8. Functional requirements (MVP)

### 8.1 Menu bar app
- **M-1:** App runs as menu bar only; no main window in normal use.
- **M-2:** Clicking menu bar icon opens the popover UI.
- **M-3:** Menu bar icon reflects global app state.
- **M-4:** “Quit” fully exits the app.

### 8.2 URL validation
- **V-1:** Accept only `http(s)` URLs with hosts in allowlist: `youtube.com`, `www.youtube.com`, `youtu.be`.
- **V-2:** Reject unsupported URLs with clear error text.
- **V-3:** Store the canonical URL (normalize if possible).

### 8.3 Resolve metadata and audio source
- **R-1:** Integrate `yt-dlp` (or equivalent) to:
  - validate video availability (within MVP scope),
  - extract metadata (title, duration),
  - choose an audio-only format suitable for download.
- **R-2:** On resolve failures, show a user-facing error and allow retry.

### 8.4 Download-first playback model
- **D-1:** Audio is downloaded into an app-managed cache directory.
- **D-2:** Download progress is shown in the popover.
- **D-3:** User can cancel an in-progress download.
- **D-4:** On download completion, the item is marked “Ready offline”.
- **D-5:** On download failure:
  - set item state to “Failed”
  - show error summary + Retry
- **D-6:** Cache management:
  - per-item “Remove Download”
  - global “Clear Downloads”
  - (Optional for MVP) max cache size and eviction policy (if not implemented, document that cache is manual).

### 8.5 Playback controls
- **P-1:** Basic controls: Play/Pause and Stop.
- **P-2:** Only one track plays at a time.
- **P-3:** Selecting a track starts playback (or sets current and requires Play—choose one; MVP default: **starts playback**).
- **P-4:** Playback is audio-only and uses local downloaded file.
- **P-5:** Display currently playing title.

### 8.6 Playback position persistence (core MVP)
- **Pos-1:** Persist playback position per track (`seconds`).
- **Pos-2:** Resume from last position when user plays that track again.
- **Pos-3:** Save position periodically (e.g., every 5–10 seconds), and on pause/stop/quit.
- **Pos-4:** Stop behavior (MVP decision):
  - **Stop resets position to 0** for that track.
  - Pause retains position.

### 8.7 Library management
- **L-1:** App ships with a predefined **Featured** list of 3–5 items (non-editable).
- **L-2:** Users can add items to **My Library** via URL input.
- **L-3:** Users can set a custom display name.
- **L-4:** Users can delete items from My Library (also removes associated download).
- **L-5:** Persist library locally across launches.

### 8.8 Search + scrolling
- **S-1:** Track list is scrollable.
- **S-2:** Search filters both Featured and My Library by display name and resolved title.

### 8.9 Diagnostics
- **Diag-1:** “Copy Diagnostics” copies last N log lines to clipboard.
- **Diag-2:** Logs include resolve/download/playback events and errors (no personal data beyond URLs the user entered).

---

## 9. Data model & persistence

### 9.1 Track model (recommended fields)
Each track item stores:
- `id: UUID`
- `sourceURL: URL`
- `videoId: String` (derived)
- `displayName: String`
- `resolvedTitle: String?`
- `durationSeconds: Double?`
- `addedAt: Date`
- `lastPlayedAt: Date?`
- `playbackPositionSeconds: Double`
- `downloadState: enum { notDownloaded, resolving, downloading, downloaded, failed }`
- `downloadProgress: Double?`
- `localFilePath: String?`
- `fileSizeBytes: Int64?`
- `lastError: String?`

### 9.2 Persistence approach (MVP)
- Store the library as JSON in `Application Support` (versioned schema).
- Store small preferences in `UserDefaults` (e.g., cache size setting if present).
- Audio files stored in `Caches` directory.

---

## 10. Non-functional requirements

### 10.1 Performance
Meet the benchmark budgets in section 4.2.

### 10.2 Reliability
- Graceful behavior on:
  - no internet
  - YouTube video removed/unavailable
  - transient network errors mid-download
  - low disk space

### 10.3 Security
- Never execute user input via shell; call `yt-dlp` with argument arrays.
- Validate input URLs (section 8.2).

### 10.4 Privacy
- No analytics by default.
- No data leaves device.
- If crash reporting is added later: opt-in and documented.

### 10.5 Accessibility
- All controls have accessibility labels.
- Usable via keyboard navigation in the popover.

---

## 11. Error handling requirements (MVP)

### 11.1 User-facing errors
For each category, show:
- short message,
- “Retry” action (where applicable),
- link to diagnostics (“Copy Diagnostics”).

Categories:
- invalid URL / unsupported host
- resolve failed (video unavailable / restricted)
- download failed (network, throttling, file error)
- playback failed (file missing/corrupt)

### 11.2 Retry strategy
- Retry is user-initiated in MVP.
- Optional: include simple backoff for immediate retry storms.

---

## 12. Featured content (MVP)
Selected featured list (subject to availability):
1. Lofi hip hop radio (DWcJFNfaw9c)
2. Ambient space music (lCOF9LN_Zxs)
3. Classical focus mix (2OEL4P1Rz04)

Criteria (for future refresh):
- reputable channels
- long duration (≥ 1 hour)
- minimal takedown risk
- mix of ambient + music + focus

---

## 13. Milestones (suggested)
1. **Prototype**: MenuBarExtra popover + AVAudio playback from local file
2. **Resolve + download**: `yt-dlp` integration + progress + cancel
3. **Library**: persistence + CRUD + featured list
4. **Resume**: position tracking + resume rules
5. **Polish**: states + errors + diagnostics + search
6. **Distribution**: Homebrew cask packaging, signing/notarization plan

---

## 14. Open questions
Resolved for MVP:
1. Minimum macOS version: 13.0 (Ventura).
2. Cache policy: manual-only for MVP (no eviction).
3. Stop behavior: Stop resets position to 0.
4. Featured list: three items selected (see section 12).

---
