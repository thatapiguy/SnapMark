<p align="center">
  <img src="docs/images/icon.png" width="128" alt="SnapMark icon">
</p>

<h1 align="center">SnapMark</h1>

<p align="center">
  A small, fast screenshot tool for your Mac menu bar, with built-in markup.<br>
  Capture, annotate, copy. Everything stays on your Mac.
</p>

<p align="center">
  <a href="../../releases/latest"><b>Download the latest release</b></a>
  · macOS 14 Sonoma or later · Apple Silicon and Intel
</p>

<p align="center">
  <img src="docs/images/editor-example.png" width="720" alt="A screenshot marked up with a box, an arrow, a text label and a blurred area">
</p>
<p align="center"><sub>Boxes, arrows, text and redaction, all made inside SnapMark.</sub></p>

## Why SnapMark

- **Quick:** press a shortcut, drag a box, and the screenshot is on your clipboard.
- **Markup built in:** arrows, boxes, text and pixelate for hiding private info, with no second app.
- **Private by design:** no account, no analytics, no network. The app is sandboxed with no internet access at all.
- **Light:** under 2 MB, lives in the menu bar, and has no Dock icon.

## Install

1. Download `SnapMark-vX.Y.Z.zip` from the [latest release](../../releases/latest) and unzip it.
2. Drag **SnapMark** into your **Applications** folder.
3. Open it. macOS will say it can't verify the app, because SnapMark isn't notarized yet. **Right-click the app, choose Open, then click Open.** You only need to do this once.
   If you'd rather use Terminal: `xattr -dr com.apple.quarantine /Applications/SnapMark.app`
4. Follow the welcome window and allow **Screen Recording**. macOS requires this for any app that takes screenshots. If macOS asks you to restart the app, use the **Restart SnapMark** button.

## Taking a screenshot

SnapMark sits in your menu bar (the viewfinder icon). Press a shortcut, then drag over the area you want. A magnifier shows the exact pixels, and the selection size updates as you drag. Press **Esc** or right-click to cancel.

| Shortcut | What happens |
|---|---|
| **⌘⇧2** | Capture a region and **copy it** to the clipboard |
| **⌘⇧3** | Capture a region and **open it in the editor** |

You can change these, or add your own, in **Settings → Shortcuts**. Each shortcut pairs a capture with an action: copy, open the editor, save to a folder, or copy and save.

> **Using ⌘⇧3 / ⌘⇧4 / ⌘⇧5?** macOS owns those keys for its own screenshots. To use them in SnapMark, turn the built-in ones off in *System Settings → Keyboard → Keyboard Shortcuts → Screenshots*. SnapMark warns you in Settings when a shortcut clashes.

## The editor

Every mark you add is an object. Click it to move, resize, recolor or delete it, and undo as many times as you like.

| Key | Tool | Key | Tool |
|---|---|---|---|
| **V** | Select / move | **B** | Pixelate (hide sensitive info) |
| **A** | Arrow | **T** | Text |
| **R** | Rectangle | **C** | Crop |

| Shortcut | Action |
|---|---|
| **⌘↩** | Copy the image and close (the main action) |
| **⌘C** / **⌘S** / **⇧⌘S** | Copy / Save / Save As |
| **⌘Z** / **⇧⌘Z** | Undo / Redo |
| **⌘=** / **⌘−** / **⌘0** | Zoom in / out / fit (pinch works too) |
| **Esc** | Close (asks first if you have unsaved edits) |

Images are exported at full native resolution, so Retina screenshots stay sharp. Pixelated areas are permanently flattened into the exported image, so the hidden content can't be recovered from the copy or file.

By default, saved screenshots go to `~/Pictures/SnapMark`. Pick another folder and a file-name template in **Settings → General**.

## Troubleshooting

**Nothing happens when I press the shortcut.**
Check that no other app, or macOS itself, uses the same keys (see the note above). A yellow warning icon next to a shortcut in Settings means it is already taken.

**SnapMark says Screen Recording is on, but captures fail.**
macOS ties the permission to the exact app build, so after replacing or updating SnapMark the old permission can go stale. Quit SnapMark and run:

```bash
tccutil reset ScreenCapture com.snapmark.app
```

Then open SnapMark again and re-allow Screen Recording. Make sure there is only one copy of the app on your Mac.

**macOS warns about the app every time I update.**
Releases aren't signed with a paid Apple Developer ID yet. Right-click → Open each time, or use the `xattr` command above.

## Privacy

SnapMark makes no network connections and collects nothing. Screenshots stay on your Mac, on your clipboard, or in the folder you choose. The app runs in the macOS sandbox without any network permission, so the system itself blocks internet access.

## What's next

Window and full-screen capture, repeat last region, timed capture, a floating thumbnail with drag-out, and capture history are planned next, followed by OCR, pin-to-screen, a color picker and more.

## For developers

```bash
scripts/build_app.sh        # universal app in build/SnapMark.app
swift test                  # unit tests
swift scripts/make_icon.swift            # regenerate Support/AppIcon.icns
scripts/make_demo_screenshot.sh          # regenerate docs/images/editor-example.png
```

Requires the Swift 5.10+ toolchain. The app is a Swift package (`SnapMarkCore` holds the testable logic, `SnapMark` is the app) with no third-party dependencies.

To publish a release, push a version tag. GitHub Actions runs the tests, builds the universal app and attaches it to a new release:

```bash
git tag v0.2.0 && git push origin v0.2.0
```

Builds are ad-hoc signed. Screen Recording permission is tied to the signature, so when rebuilding locally pass `SIGN_IDENTITY="Apple Development: …"` to keep the permission between builds.
