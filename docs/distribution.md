# Distribution Guide

## Code Signing
1. Create a `Developer ID Application` certificate in Xcode or Keychain.
2. Ensure `DEVELOPMENT_TEAM` matches your Team ID.
3. Build and re-sign (embedded binaries + timestamped signature):
   - `scripts/build-release.sh`
4. Output bundle and zip:
   - `build/Build/Products/Release/LongPlay.app`
   - `dist/LongPlay-<version>.zip`

## Notarization
1. Create an app-specific password.
2. Store credentials once:
   - `xcrun notarytool store-credentials notarytool --apple-id "you@icloud.com" --team-id K6H76QJBE9 --password "app-specific-password"`
3. Build + notarize:
   - `NOTARIZE=1 scripts/build-release.sh`

## Homebrew Cask
- Provide a signed, notarized `.zip` or `.dmg` hosted over HTTPS.
- Example cask snippet:
  - `url "https://example.com/LongPlay-0.1.0.zip"`
  - `sha256 "<sha256>"`
  - `name "LongPlay"`
  - `app "LongPlay.app"`

## Notes
- This app uses `LSUIElement` to stay menu-bar only.
- `yt-dlp` is fetched at build time from `https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos` into `Resources/bin/yt-dlp`.
- `ffmpeg` and `ffprobe` are fetched at build time into `Resources/bin/` for audio conversion.
- Keep `Resources/bin/*` out of git; they are generated during builds.
- Refresh `minimumSupportedVersion` in `YtDlpClient` to match the fetched version.
- Keep distribution artifacts outside the repo.
