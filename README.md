# SnapMark

A lightweight, fully offline macOS menu-bar screenshot tool with a built-in annotation editor.
macOS 14+, Apple Silicon and Intel. No network access, no account, no analytics.

## Install
Download the latest `SnapMark-vX.Y.Z.zip` from [Releases](../../releases), unzip, and move
`SnapMark.app` to Applications.

Builds are not notarized yet, so macOS will warn on first launch. Right-click the app → **Open**,
or run:

```bash
xattr -dr com.apple.quarantine /Applications/SnapMark.app
```

Then allow **Screen Recording** in System Settings → Privacy & Security.

## Default shortcuts
- ⌘⇧2 — region → clipboard
- ⌘⇧3 — region → editor (turn off macOS's built-in screenshot shortcuts first)

All shortcuts are configurable in Settings.

## Build from source
```bash
scripts/build_app.sh      # universal build in build/SnapMark.app
swift test
```

## Releasing
```bash
git tag v0.1.0 && git push origin v0.1.0
```
GitHub Actions runs the tests, builds the universal app and publishes the release.
