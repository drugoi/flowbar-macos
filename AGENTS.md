# Repository Guidelines

## Project Structure & Module Organization
- `docs/` holds product documentation; see `docs/prd.md` for the MVP scope and requirements.
- Source code, tests, and assets are not yet present in this repository; add new top-level folders as the implementation begins (e.g., `Sources/`, `Tests/`, `Assets/`).

## Build, Test, and Development Commands
No build or test scripts are defined yet. When bootstrapping the app, document the primary commands here (for example, `xcodebuild` or `swift test`) and keep them aligned with the Xcode project or Swift Package layout.

## Coding Style & Naming Conventions
- No repository-specific style guide is present yet. Prefer standard Swift formatting and SwiftUI conventions.
- When adding tooling (e.g., `swiftformat`, `swiftlint`), include the config files at the repo root and document how to run them in this section.

## Testing Guidelines
- There are no test targets defined yet. When tests are added, note the framework (e.g., XCTest) and conventions such as `*Tests.swift` files and mirror directory structure (e.g., `Tests/LongPlayTests/`).
- Document any coverage thresholds or required suites (unit, UI) once established.

## Commit & Pull Request Guidelines
- No commit message conventions are recorded in this repo yet. If the team adopts a convention (e.g., Conventional Commits), update this section and provide examples.
- PRs should include: a clear description, linked issue or task (if any), and screenshots or screen recordings for UI changes.

## Architecture & Configuration Notes
- The product scope targets a macOS menu bar app using SwiftUI (`MenuBarExtra`) with download-first playback; consult `docs/prd.md` before implementation.
- If `yt-dlp` (or similar) is integrated, ensure it is invoked via argument arrays (no shell execution) and document any required install steps.
