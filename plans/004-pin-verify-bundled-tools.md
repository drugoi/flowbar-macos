# Plan 004: Pin and verify bundled executable downloads

> **Executor instructions**: Follow this plan step by step. Run every verification command and confirm the expected result before moving to the next step. If anything in the "STOP conditions" section occurs, stop and report; do not improvise. When done, update the status row for this plan in `plans/README.md` unless a reviewer tells you they maintain the index.
>
> **Drift check (run first)**: `git diff --stat 6fa18b8..HEAD -- scripts/fetch-yt-dlp.sh scripts/fetch-deno.sh scripts/fetch-ffmpeg.sh scripts/fetch-sparkle-tools.sh scripts/build-ffmpeg-minimal.sh docs/distribution.md docs/release-checklist.md project.yml`
> If any in-scope file changed since this plan was written, compare the "Current state" excerpts against the live code before proceeding; on a mismatch, treat it as a STOP condition.

## Status

- **Priority**: P1
- **Effort**: M
- **Risk**: MED
- **Depends on**: none
- **Category**: security
- **Planned at**: commit `6fa18b8`, 2026-06-22

## Why this matters

FlowBar ships external executables inside the app bundle and then signs/notarizes the result. Several build scripts download those executables from remote release URLs without checksum verification; some URLs use `latest`, so a rebuild can silently ship different bits for the same source commit. This is a supply-chain risk and also hurts reproducibility.

## Current state

- `project.yml` runs fetch scripts before the app build:

```yaml
# project.yml:29
- name: Fetch yt-dlp
  script: scripts/fetch-yt-dlp.sh
...
- name: Fetch ffmpeg
  script: scripts/fetch-ffmpeg.sh
...
- name: Fetch deno
  script: scripts/fetch-deno.sh
```

- `yt-dlp` is fetched from a mutable `latest` URL:

```sh
# scripts/fetch-yt-dlp.sh:7
URL="https://github.com/yt-dlp/yt-dlp/releases/latest/download/yt-dlp_macos"
```

- Deno is fetched from mutable `latest` URLs:

```sh
# scripts/fetch-deno.sh:10
DENO_URL="https://github.com/denoland/deno/releases/latest/download/deno-aarch64-apple-darwin.zip"
```

- ffmpeg URLs are versioned but unchecked:

```sh
# scripts/fetch-ffmpeg.sh:16
FFMPEG_URL="https://evermeet.cx/ffmpeg/ffmpeg-7.0.1.zip"
FFPROBE_URL="https://evermeet.cx/ffmpeg/ffprobe-7.0.1.zip"
```

- Sparkle tools are versioned but unchecked:

```sh
# scripts/fetch-sparkle-tools.sh:19
ARCHIVE_URL="https://github.com/sparkle-project/Sparkle/releases/download/${SPARKLE_VERSION}/Sparkle-${SPARKLE_VERSION}.tar.xz"
```

- Existing release docs tell maintainers to fetch latest binaries manually:

```markdown
// docs/release-checklist.md:8
- [ ] Run `scripts/fetch-yt-dlp.sh` to download the latest binary.
```

## Commands you will need

| Purpose | Command | Expected on success |
|---------|---------|---------------------|
| Shell syntax | `sh -n scripts/fetch-yt-dlp.sh scripts/fetch-deno.sh scripts/fetch-ffmpeg.sh scripts/build-ffmpeg-minimal.sh` | exits 0 |
| Bash syntax | `bash -n scripts/fetch-sparkle-tools.sh scripts/build-release.sh scripts/release-github.sh scripts/generate-appcast.sh` | exits 0 |
| Check no latest URLs | `rg -n "releases/latest|latest/download" scripts docs project.yml` | no matches except historical docs explicitly explaining why latest is not used |
| Check checksum code | `rg -n "shasum -a 256|SHA256|checksum" scripts/fetch-*.sh` | matches in every fetch script that downloads binaries or archives |
| Build | `xcodebuild -scheme FlowBar -configuration Debug -derivedDataPath build` | exits 0 |

## Scope

**In scope**:

- `scripts/fetch-yt-dlp.sh`
- `scripts/fetch-deno.sh`
- `scripts/fetch-ffmpeg.sh`
- `scripts/fetch-sparkle-tools.sh`
- `scripts/build-ffmpeg-minimal.sh` only if you add source tarball checksum verification
- `docs/distribution.md`
- `docs/release-checklist.md`
- `project.yml` only if script input/output files change

**Out of scope**:

- Replacing yt-dlp, Deno, ffmpeg, or Sparkle.
- Changing app runtime behavior.
- Committing downloaded binaries under `Resources/bin/`; they must remain ignored.
- Automating GitHub release publishing.

## Git workflow

- Branch: `codex/004-pin-verify-bundled-tools`
- Commit style if committing: `build: verify bundled tool downloads`
- Do not push or open a PR unless instructed.

## Steps

### Step 1: Add checksum verification helpers to fetch scripts

Add a small POSIX-shell-compatible helper to the `sh` scripts and a Bash equivalent to `fetch-sparkle-tools.sh`:

```sh
verify_sha256() {
  file="$1"
  expected="$2"
  actual="$(/usr/bin/shasum -a 256 "$file" | awk '{print $1}')"
  if [ "$actual" != "$expected" ]; then
    echo "Checksum mismatch for $file" >&2
    echo "Expected: $expected" >&2
    echo "Actual:   $actual" >&2
    exit 1
  fi
}
```

Use `/usr/bin/shasum` on macOS. Do not use Homebrew-only tools.

**Verify**: `sh -n scripts/fetch-yt-dlp.sh scripts/fetch-deno.sh scripts/fetch-ffmpeg.sh` and `bash -n scripts/fetch-sparkle-tools.sh` -> both exit 0.

### Step 2: Replace mutable latest URLs with pinned versions

For `yt-dlp`, introduce explicit variables near the top:

```sh
YTDLP_VERSION="YYYY.MM.DD"
YTDLP_SHA256="<64 hex chars>"
URL="https://github.com/yt-dlp/yt-dlp/releases/download/${YTDLP_VERSION}/yt-dlp_macos"
```

For Deno, introduce:

```sh
DENO_VERSION="x.y.z"
DENO_AARCH64_SHA256="<64 hex chars>"
DENO_X86_64_SHA256="<64 hex chars>"
```

and use versioned GitHub release URLs such as:

```sh
https://github.com/denoland/deno/releases/download/v${DENO_VERSION}/deno-aarch64-apple-darwin.zip
```

For ffmpeg/ffprobe, keep the explicit `7.0.1` version unless you intentionally update it, but add separate checksums for both zip files.

For Sparkle tools, keep `SPARKLE_VERSION="${SPARKLE_VERSION:-2.8.1}"` but add an archive checksum for the default version. If maintainers override `SPARKLE_VERSION`, require them to also override the matching checksum env var.

To get a checksum when updating a version, download the asset to a temp file and run:

```sh
/usr/bin/shasum -a 256 /path/to/downloaded-asset
```

Record only the checksum, not any signing secrets.

**Verify**: `rg -n "releases/latest|latest/download" scripts docs project.yml` -> no matches except a deliberate doc note that mutable latest URLs are not allowed.

### Step 3: Verify every downloaded archive before extraction or install

Call `verify_sha256` immediately after each `curl` succeeds and before `chmod`, `unzip`, `tar`, or `cp`.

For scripts that skip downloads when an existing binary is present, do not checksum existing cached binaries unless the script also records the source asset checksum somewhere. The critical requirement is that newly downloaded bytes are checked before being copied into `Resources/bin`.

**Verify**: `rg -n "verify_sha256" scripts/fetch-yt-dlp.sh scripts/fetch-deno.sh scripts/fetch-ffmpeg.sh scripts/fetch-sparkle-tools.sh` -> each fetch script has at least one call.

### Step 4: Add temp-output hooks so fetch scripts can be tested safely

Where practical, let scripts override output dirs with env vars, for example:

- `RESOURCES_BIN_DIR="${RESOURCES_BIN_DIR:-$ROOT_DIR/Resources/bin}"`
- `TOOLS_DIR` already exists in `fetch-sparkle-tools.sh`; keep it.

Use those vars in place of hard-coded destination dirs. Preserve default behavior for Xcode prebuild scripts.

**Verify**: run each fetch script once with a temp output dir where feasible:

```sh
tmp="$(mktemp -d)"
RESOURCES_BIN_DIR="$tmp/bin" scripts/fetch-deno.sh
test -x "$tmp/bin/deno"
rm -rf "$tmp"
```

Expected: exits 0 and installs into the temp dir. If a fetch takes too long or the network is unavailable, record the failure and at least complete syntax and checksum-code verification.

### Step 5: Update docs

Update release docs so they no longer tell maintainers to fetch "latest". Explain:

- Tool versions are pinned in fetch scripts.
- Updating a tool means changing version and SHA256 together.
- A checksum mismatch must stop the release.

**Verify**: `rg -n "latest binary|latest/download|releases/latest" docs scripts` -> no stale instructions except an explicit warning against mutable latest URLs.

## Test plan

- Run syntax checks for all changed scripts.
- Run at least one temp-dir fetch smoke test if network is available.
- Run the Debug build to prove Xcode prebuild script defaults still work.

## Done criteria

- [ ] No build script downloads from `releases/latest` or `latest/download`.
- [ ] Every downloaded binary/archive is verified with SHA256 before extraction/copy/signing.
- [ ] Fetch scripts can be smoke-tested without writing to the real `Resources/bin` when env overrides are provided.
- [ ] Docs describe the pinned-version update workflow.
- [ ] `xcodebuild -scheme FlowBar -configuration Debug -derivedDataPath build` exits 0.
- [ ] `Resources/bin` downloaded binaries are not committed.
- [ ] `plans/README.md` status row updated.

## STOP conditions

Stop and report back if:

- An upstream tool does not publish stable release URLs for the needed macOS artifact.
- A required checksum cannot be reproduced from a fresh download.
- Xcode prebuild scripts cannot use temp-output hooks without breaking normal build output files.
- The fix requires replacing a tool rather than pinning/verifying the current one.

## Maintenance notes

Reviewers should verify that version and checksum changes appear together. A future release automation plan can move these values into a single manifest, but this plan should keep the change simple and reviewable.

