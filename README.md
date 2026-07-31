# LazyMouse

<img src="assets/AppIcon.svg" alt="LazyMouse logo showing two overlapping mice" width="180">

LazyMouse is a macOS menu bar utility for showing one customizable cursor overlay for one external physical mouse. The overlay uses the native macOS arrow shape at a slightly larger scale. The built-in trackpad remains attached to the normal macOS cursor, while the external mouse moves the overlay cursor.

## Requirements

- macOS 14 or newer
- Swift 5.9 or newer
- An external mouse exposed by macOS as a standard Generic Desktop Mouse HID device

LazyMouse enumerates standard Generic Desktop Mouse devices, rejects built-in devices and trackpads, then seizes the selected external mouse so macOS does not also move the regular cursor. This covers the connected USB, Bluetooth, or receiver-based mouse without treating the built-in trackpad as a second cursor. The menu includes a persisted separate-cursor toggle, a cursor-color picker, and virtual clicks, drags, and scrolling for the overlay cursor.

## Run from source

```sh
swift test
swift run LazyMouse
```

HID discovery and exclusive mouse capture may require **System Settings > Privacy & Security > Input Monitoring** on the current macOS configuration; LazyMouse includes a shortcut to that pane when no device is visible. If the Bluetooth mouse was connected before LazyMouse started, use **Rescan mice** in the menu. With one display, assign the mouse to **Free - all displays**. The app does not claim notarization and should be treated as a locally built developer utility.

## Build and install the macOS app

The repository includes one native vector logo source at `assets/AppIcon.svg` and a packaging script. The script builds a release executable, creates `LazyMouse.app`, generates `AppIcon.icns`, signs the local bundle with the stable `LazyMouse Local Development` identity when available, installs it in `~/Applications`, and can launch it through LaunchServices:

```sh
./build_app.sh --open
```

To build and install without opening it:

```sh
./build_app.sh
```

The packaged bundle is kept in the ignored `.build` directory and installed at `~/Applications/LazyMouse.app`, leaving one user-facing app. The icon is intentionally text-free so the two-mouse mark remains legible in Finder, GitHub, and at small menu sizes. If the local signing identity is unavailable, the script falls back to an ad-hoc signature and macOS may require Input Monitoring approval again after a rebuild.
