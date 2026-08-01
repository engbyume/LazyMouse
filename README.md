# LazyMouse

<p align="center">
  <img src="assets/AppIcon.svg" alt="LazyMouse logo showing two overlapping mice" width="180">
</p>

LazyMouse is a macOS menu bar utility for showing one customizable cursor overlay. The overlay uses the native macOS arrow shape at a slightly larger scale and can click, double-click, drag, right-click, and scroll. By default, the built-in trackpad remains attached to the regular macOS cursor while the external mouse moves the red cursor. The **Swap mouse and trackpad** button reverses those assignments.

## Requirements

- macOS 14 or newer
- Swift 5.9 or newer
- An external mouse exposed by macOS as a standard Generic Desktop Mouse HID device
- A stable code-signing identity for local packaging, so macOS can retain Input Monitoring authorization across rebuilds

LazyMouse enumerates standard Generic Desktop pointer devices and exclusively captures the external mouse. In the default assignment, its HID input drives the red cursor while the built-in trackpad stays with macOS. In the swapped assignment, tagged synthetic events route the captured external mouse to the regular cursor while an event tap isolates trackpad movement, clicks, drags, and two-finger scrolling for the red cursor. Red-cursor interactions are delivered before the regular cursor position is restored on the next main-loop turn, so target apps receive the complete action without leaving the regular cursor displaced. Both routes preserve left, right, and middle buttons plus vertical and horizontal scrolling. If the external mouse disconnects while the trackpad owns the red cursor, LazyMouse immediately releases the trackpad back to the regular cursor.

## Run from source

```sh
swift test
swift run LazyMouse
```

HID discovery and exclusive mouse capture may require **System Settings > Privacy & Security > Input Monitoring** on the current macOS configuration; LazyMouse includes a shortcut to that pane when no device is visible. If the Bluetooth mouse was connected before LazyMouse started, use **Rescan mice** in the menu. With one display, assign the mouse to **Free - all displays**. The app does not claim notarization and should be treated as a locally built developer utility.

Overlay interaction requires **System Settings > Privacy & Security > Accessibility**. LazyMouse requests CoreGraphics event-posting access at startup and shows the exact readiness state in its menu. Use **Request Click Access** if clicks, drags, or scrolling are unavailable, then relaunch LazyMouse after enabling it.

## Build and install the macOS app

The repository includes the full-color app logo at `assets/AppIcon.svg`, the transparent menu-bar template at `assets/AppIconMenu.svg`, and a packaging script. Packaging requires `rsvg-convert` from `librsvg`; with Homebrew, install it with `brew install librsvg`. The script builds a release executable, creates `LazyMouse.app`, generates `AppIcon.icns`, signs the local bundle with the stable `LazyMouse Local Development` identity when available, installs it in `/Applications`, and can launch it through LaunchServices:

```sh
./build_app.sh --open
```

To build and install without opening it:

```sh
./build_app.sh
```

The script uses the ignored `.build` directory for temporary packaging output and installs the app at `/Applications/LazyMouse.app`, leaving one user-facing app. The icon is intentionally text-free so the two-mouse mark remains legible in Finder, GitHub, and at small menu sizes. Packaging requires the stable `LazyMouse Local Development` identity by default because ad-hoc signatures invalidate Input Monitoring authorization after rebuilds. Set `SIGNING_IDENTITY` to another unique valid local identity when needed. `ALLOW_ADHOC_SIGNING=1` is available only as an explicit diagnostic escape hatch and is not suitable for mouse capture.

## Verification log

The current local verification passes include:

- `swift test`: 16 tests passed.
- Signed interaction integration test: the swapped trackpad tap captured and suppressed move, click, and scroll input; both cursor routes delivered left-click, drag, right-click, and scroll to an independent AppKit target; regular-cursor movement and red-route cursor restoration also passed.
- `git diff --check`: passed.
- `./build_app.sh`: release build, stable signing, bundle verification, and install passed.
- Installed bundle: `/Applications/LazyMouse.app`.
- The app bundle uses the stable `LazyMouse Local Development` signature so Input Monitoring can persist across rebuilds.

After launch, the menu-bar status should read **External mouse isolated** when the external mouse is captured. The menu labels the current owners of **Red cursor** and **Regular cursor**. Use **Swap mouse and trackpad** to exchange them. LazyMouse remembers the assignment only when the external mouse is available and automatically returns the trackpad to the regular cursor if that mouse disconnects.
