# Release Checklist

## Build + Test
- [ ] Run `xcodebuild -scheme LongPlay -destination 'platform=macOS' test`.
- [ ] Smoke test menu bar behavior (open/close popover, play/pause, download).

## yt-dlp
- [ ] Run `scripts/fetch-yt-dlp.sh` to download the latest binary.
- [ ] Verify `Resources/bin/yt-dlp` executes and returns a version.
- [ ] Confirm `YtDlpClient.minimumSupportedVersion` matches the fetched binary.

## ffmpeg
- [ ] Run `scripts/fetch-ffmpeg.sh` to download `ffmpeg` and `ffprobe`.
- [ ] Verify `Resources/bin/ffmpeg` and `Resources/bin/ffprobe` are executable.

## Signing + Notarization
- [ ] Sign with Developer ID Application.
- [ ] Submit for notarization, staple, and validate.
- [ ] Confirm `spctl` accepts the app (or run `scripts/verify-zip.sh dist/LongPlay-<version>.zip`).

## Distribution
- [ ] Create `.zip` or `.dmg` artifact.
- [ ] Update Homebrew cask URL + SHA.
- [ ] Publish release notes.

## Versioning
- [ ] Ensure the Git tag (`TAG=vX.Y.Z`) matches the intended app version.
