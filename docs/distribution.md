# Distribution Guide

## Code Signing
1. Create an Apple Developer ID Application certificate.
2. Set `DEVELOPMENT_TEAM` in `project.yml` or Xcode.
3. Build release:
   - `xcodebuild -scheme LongPlay -configuration Release -archivePath build/LongPlay.xcarchive archive`
4. Export the app:
   - `xcodebuild -exportArchive -archivePath build/LongPlay.xcarchive -exportOptionsPlist Config/ExportOptions.plist -exportPath build/export`

## Notarization
1. Create an app-specific password and set an app store connect API key or use `notarytool`.
2. Submit:
   - `xcrun notarytool submit build/export/LongPlay.app --keychain-profile "AC_NOTARY" --wait`
3. Staple:
   - `xcrun stapler staple build/export/LongPlay.app`

## Homebrew Cask
- Provide a signed, notarized `.zip` or `.dmg` hosted over HTTPS.
- Example cask snippet:
  - `url "https://example.com/LongPlay-0.1.0.zip"`
  - `sha256 "<sha256>"`
  - `name "LongPlay"`
  - `app "LongPlay.app"`

## Notes
- This app uses `LSUIElement` to stay menu-bar only.
- Keep distribution artifacts outside the repo.
