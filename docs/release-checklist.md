# Release Checklist

## Build + Test
- [ ] Run `xcodebuild -scheme LongPlay -destination 'platform=macOS' test`.
- [ ] Smoke test menu bar behavior (open/close popover, play/pause, download).

## yt-dlp
- [ ] Verify bundled `Resources/yt-dlp` executes and returns a version.
- [ ] Confirm `YtDlpClient.minimumSupportedVersion` matches the bundled binary.

## Signing + Notarization
- [ ] Archive Release build.
- [ ] Sign with Developer ID Application.
- [ ] Submit for notarization and staple.

## Distribution
- [ ] Create `.zip` or `.dmg` artifact.
- [ ] Update Homebrew cask URL + SHA.
- [ ] Publish release notes.
