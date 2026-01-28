# Updates (Sparkle)

FlowBar uses Sparkle (stable feed) to support **Check for Updates** and automatic background update checks.

## Feed
- The app reads the appcast URL from `SUFeedURL` in `Config/Info.plist`.
- For GitHub Pages project sites, the default URL is:
  - `https://<owner>.github.io/<repo>/appcast.xml`
- Add the Sparkle public key to `SUPublicEDKey` in `Config/Info.plist`.

## Keys (EdDSA)
Sparkle signs update archives using an Ed25519 key. Keep the private key secret.

1. Fetch Sparkle tools:
   - `scripts/fetch-sparkle-tools.sh`
2. Generate a keypair (run locally):
   - `build/sparkle-tools/2.8.1/bin/generate_keys`
   - Copy the `public key` output into `SUPublicEDKey` in `Config/Info.plist`.
3. Store the private key securely and export it when generating/publishing the appcast:
   - `export SPARKLE_ED25519_PRIVATE_KEY="<private key contents>"`

## Appcast generation
After building a release zip into `dist/`:
- Generate `dist/appcast.xml`:
  - `TAG=v0.1.0 scripts/generate-appcast.sh`
  - Requires `SPARKLE_ED25519_PRIVATE_KEY` (set `ALLOW_UNSIGNED_APPCAST=1` for local testing only).

The generator reads update archives from `dist/` and will incrementally update an existing `appcast.xml` if present.

## Publishing to GitHub Pages
Publish `appcast.xml` to the `gh-pages` branch:
- `TAG=v0.1.0 scripts/publish-appcast.sh`

Or publish after creating a GitHub Release:
- `TAG=v0.1.0 PUBLISH_APPCAST=1 scripts/release-github.sh`
