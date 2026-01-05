# Release Checklist

## Build + Test
- [ ] Run `xcodebuild -scheme LongPlay -destination 'platform=macOS' test`.
- [ ] Smoke test menu bar behavior (open/close popover, play/pause, download).

## yt-dlp
- [ ] Run `scripts/fetch-yt-dlp.sh` to download the latest binary.
- [ ] Verify `Resources/yt-dlp` executes and returns a version.
- [ ] Confirm `YtDlpClient.minimumSupportedVersion` matches the fetched binary.

## Signing + Notarization
- [ ] Archive Release build.
- [ ] Sign with Developer ID Application.
- [ ] Submit for notarization and staple.

## Distribution
- [ ] Create `.zip` or `.dmg` artifact.
- [ ] Update Homebrew cask URL + SHA.
- [ ] Publish release notes.
