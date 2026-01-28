# Repository Guidelines

## Project Structure & Module Organization
- `docs/` holds product documentation; see `docs/prd.md` for the MVP scope and requirements.
- `Sources/` contains the SwiftUI menu bar app and services.
- `Tests/` contains UI tests (`Tests/FlowBarUITests`).
- `Resources/` stores build-fetched binaries (see Build section).

## Build, Test, and Development Commands
- Generate the Xcode project: `xcodegen generate`
- Build: `xcodebuild -scheme FlowBar -configuration Debug -derivedDataPath build`
- Test: `xcodebuild -scheme FlowBar -destination 'platform=macOS' test`
- The build runs `scripts/fetch-yt-dlp.sh` and `scripts/fetch-ffmpeg.sh` to fetch binaries into `Resources/bin` and copy them into the app bundle.

## Coding Style & Naming Conventions
- No repository-specific style guide is present yet. Prefer standard Swift formatting and SwiftUI conventions.
- When adding tooling (e.g., `swiftformat`, `swiftlint`), include the config files at the repo root and document how to run them in this section.

## Testing Guidelines
- UI tests live in `Tests/FlowBarUITests` (XCTest).
- The menu bar UI test may be skipped on some runners due to Accessibility permissions.

## Commit & Pull Request Guidelines
- No commit message conventions are recorded in this repo yet. If the team adopts a convention (e.g., Conventional Commits), update this section and provide examples.
- PRs should include: a clear description, linked issue or task (if any), and screenshots or screen recordings for UI changes.

## Architecture & Configuration Notes
- The product scope targets a macOS menu bar app using SwiftUI (`MenuBarExtra`) with download-first playback; consult `docs/prd.md` before implementation.
- `yt-dlp`, `ffmpeg`, and `ffprobe` are fetched at build time and executed from the app bundle; do not require Homebrew at runtime.
