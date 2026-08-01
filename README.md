# LazyMouse

<p align="center">
  <img src="assets/AppIcon.svg" alt="LazyMouse logo showing two overlapping mice" width="180">
</p>

LazyMouse is a macOS menu bar utility that gives an external mouse and the built-in trackpad independent cursor positions. Both routes can hover, click, double-click, drag, right-click, and scroll. By default, the trackpad owns the regular cursor while the external mouse owns the customizable red cursor. The **Swap mouse and trackpad** button reverses those assignments.

## Requirements

- macOS 14 or newer
- Swift 5.9 or newer
- An external mouse exposed by macOS as a standard Generic Desktop Mouse HID device
- A stable code-signing identity for local packaging, so macOS can retain Input Monitoring authorization across rebuilds

LazyMouse enumerates standard Generic Desktop pointer devices and exclusively captures the external mouse. An event tap isolates trackpad movement, clicks, drags, and two-finger scrolling. Both input routes are then posted at their own stored desktop positions, preserving left, right, and middle buttons plus vertical and horizontal scrolling.

macOS exposes one native system pointer, so LazyMouse uses that pointer for whichever logical cursor acted most recently and draws the parked cursor at its independent position. When the customizable cursor is active, a color accent identifies the native pointer while the parked regular cursor remains visible. When the regular cursor is active, the larger native-shaped color cursor is drawn at its parked position. This keeps exactly two arrow pointers visible instead of leaving a third native arrow over a duplicate overlay. If the external mouse disconnects, LazyMouse immediately releases the trackpad back to normal single-cursor behavior.

## Run from source

```sh
swift test
swift run LazyMouse
```

HID discovery and exclusive mouse capture may require **System Settings > Privacy & Security > Input Monitoring** on the current macOS configuration; LazyMouse includes a shortcut to that pane when no device is visible. If the Bluetooth mouse was connected before LazyMouse started, use **Rescan mice** in the menu. With one display, assign the mouse to **Free - all displays**. The app does not claim notarization and should be treated as a locally built developer utility.

Overlay interaction requires **System Settings > Privacy & Security > Accessibility**. LazyMouse requests CoreGraphics event-posting access at startup and shows the exact readiness state in its menu. Use **Request Click Access** if clicks, drags, or scrolling are unavailable, then relaunch LazyMouse after enabling it.

## Build and install the macOS app

The repository includes the full-color app logo at `assets/AppIcon.svg`, the transparent menu-bar template at `assets/AppIconMenu.svg`, and a packaging script. The same two-mouse mark is used in the README, application bundle, and menu bar. Packaging requires `rsvg-convert` from `librsvg`; with Homebrew, install it with `brew install librsvg`. The script builds a release executable with warnings treated as errors, creates `LazyMouse.app`, generates `AppIcon.icns`, signs the local bundle with the stable `LazyMouse Local Development` identity when available, installs it in `/Applications`, and can launch it through LaunchServices:

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

- `swift test`: 18 tests passed.
- `swift build -c release -Xswiftc -warnings-as-errors`: passed.
- Signed interaction integration test: trackpad capture passed movement, click, and scroll checks; two independent cursor positions each posted move, left-click, drag, right-click, and scroll events, for 14 successful posts total.
- `git diff --check`: passed.
- `./build_app.sh`: release build, stable signing, bundle verification, and install passed.
- Installed bundle: `/Applications/LazyMouse.app`.
- The app bundle uses the stable `LazyMouse Local Development` signature so Input Monitoring can persist across rebuilds.
- The live process reports exclusive capture for one external mouse and an installed, visible AppKit status item.

After launch, click the two-mouse menu-bar icon. The status should read **External mouse isolated** when the external mouse is captured. The menu labels the current owners of **Red cursor** and **Regular cursor**, exposes a native color well for the customizable cursor, and keeps its named status item visible across launches. Use **Swap mouse and trackpad** to exchange the devices. LazyMouse remembers the assignment only when the external mouse is available and automatically returns the trackpad to the regular cursor if that mouse disconnects.
