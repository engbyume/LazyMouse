# LazyMouse

LazyMouse is a macOS menu bar utility for showing independent, color-coded cursors for multiple physical mice. Each detected mouse can roam across the virtual desktop or be locked to one display.

## What works

- Detects pointing devices that macOS exposes through standard relative HID X/Y reports, including many USB, Bluetooth, and receiver-based mice.
- Gives each mouse its own colored pointer overlay.
- Supports `Free (all displays)` or a specific display per mouse.
- Detects display changes and keeps locked cursors inside their selected display.
- Stores per-device display assignments in `UserDefaults`.
- Includes an optional independent-cursor mode. When enabled, LazyMouse asks macOS to intercept ordinary mouse movement and drags so the overlay cursors do not fight the system cursor. This MVP renders pointer overlays only. Clicks and drags are not independently injected into apps.
- Keeps the app pointer-only for now. It does not inject clicks or seize devices, so it cannot silently interfere with applications.

## Permissions

Independent-cursor mode needs **Privacy & Security > Accessibility** permission because macOS protects global event taps. Without it, LazyMouse still detects devices and renders their movement, but the normal system cursor may also move.

The app does not request device seizure, kernel extensions, or background input injection. This makes it safer across ordinary standard-HID mice and wireless receivers. Trackballs, touch surfaces, vendor-specific devices, and other pointing hardware are supported only when macOS exposes standard relative HID X/Y reports. Independent clicks and drags are intentionally out of scope for this MVP.

## Run from source

Requirements: macOS 14 or newer and Swift 5.9 or newer.

```sh
swift test
swift run LazyMouse
```

Grant Accessibility permission, enable **Independent cursor mode**, then move each mouse. Open the menu bar item to assign a display boundary to each device.

## Current scope

The roadmap's collaboration concepts, such as shared rooms, follow mode, and control handoff, are intentionally not mixed into this local hardware MVP. They can be added later as an opt-in network layer without storing raw cursor movement.

## Safety

LazyMouse is pointer-only. Quit from the menu bar before changing permissions or disconnecting a receiver. If an event tap fails, LazyMouse keeps independent mode off and leaves the system cursor untouched. If a saved display is disconnected, its locked cursor stays put until you choose another available display.
