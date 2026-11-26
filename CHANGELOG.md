# Changelog

## 0.1.7 — 2026-11-26

- Long YouTube tracks can start playing while the offline copy is still downloading. Playback and the offline cache share the same AAC data when a compatible stream is available.
- Seeking can fetch audio that has not been cached yet. Cancelling the download keeps playback running, and retrying the last interrupted download in the same session reuses the audio already saved.
- FlowBar retries audio requests after a temporary connection loss and keeps verified data for a manual retry when needed.
- The player and library show the track title as soon as it is available, along with download progress. Incoming metadata preserves names you set yourself.
- Improved search discovery for the FlowBar website.
