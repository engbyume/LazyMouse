import SwiftUI
import AppKit
import LazyMouseCore

struct MainMenuView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Image(nsImage: LazyMouseBranding.appIconImage)
                    .renderingMode(.original)
                    .frame(width: 24, height: 24)
                Text("LazyMouse")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(state.separateCursorEnabled ? (isolationReady ? .green : .orange) : .gray)
                    .frame(width: 8, height: 8)
            }

            Toggle("Separate overlay cursor", isOn: Binding(
                get: { state.separateCursorEnabled },
                set: { state.setSeparateCursorEnabled($0) }
            ))

            Button("Swap cursor controls") {
                state.swapCursorAssignments()
            }
            .disabled(!state.separateCursorEnabled || !state.externalMouseAvailable)
            .help("Switch which device controls the overlay and normal macOS cursor")

            HStack {
                Label("Overlay: \(state.overlayInputSource.displayName)", systemImage: "cursorarrow.motionlines")
                Spacer()
                Text("macOS: \(state.overlayInputSource.other.displayName)")
            }
            .font(.caption)
            .foregroundStyle(.secondary)

            HStack {
                Text("Cursor color")
                Spacer()
                CursorColorWell(color: state.cursorColor.nsColor) { color in
                    state.setCursorColor(color)
                }
                .frame(width: 28, height: 22)
                .help("Choose the overlay cursor color")
            }

            Text(modeDescription)
                .font(.caption)
                .foregroundStyle(.secondary)

            if state.separateCursorEnabled && (!state.hidExclusive || state.devices.isEmpty) {
                Button("Request Input Monitoring Access") {
                    state.requestInputMonitoringAccess()
                }
                .controlSize(.small)
                Button("Open Input Monitoring Settings") {
                    state.openInputMonitoringSettings()
                }
                .controlSize(.small)
                .help("Allow LazyMouse to receive HID input from Bluetooth and USB pointing devices")
            }

            Divider()
            HStack {
                Text(statusText)
                    .font(.subheadline.weight(.semibold))
                Spacer()
                Button { state.rescanDevices() } label: {
                    Image(systemName: "arrow.clockwise")
                }
                .buttonStyle(.borderless)
                .help("Rescan connected USB and Bluetooth pointing devices")
            }

            if state.devices.isEmpty {
                Text(emptyStateText)
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else if state.separateCursorEnabled && !state.hidExclusive {
                Text("The mouse is listed, but exclusive capture is not active. Request Input Monitoring access, then rescan.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.devices) { device in
                    DeviceRow(device: device)
                }
            }

            if state.separateCursorEnabled && !state.postEventsAvailable {
                Button("Request Click Access") {
                    state.requestClickAccess()
                }
                .controlSize(.small)
            }

            if state.separateCursorEnabled {
                Label(
                    state.postEventsAvailable ? "Overlay interaction ready" : "Overlay interaction needs Accessibility",
                    systemImage: state.postEventsAvailable ? "checkmark.circle.fill" : "exclamationmark.triangle.fill"
                )
                .font(.caption)
                .foregroundStyle(state.postEventsAvailable ? .green : .orange)
            }

            if state.separateCursorEnabled && state.overlayInputSource == .builtInTrackpad && !state.trackpadIsolationActive {
                Label("Trackpad isolation unavailable", systemImage: "exclamationmark.triangle.fill")
                    .font(.caption)
                    .foregroundStyle(.orange)
            }

            Divider()
            HStack {
                Button("Rescan devices") { state.rescanDevices() }
                    .controlSize(.small)
                Button("Refresh displays") { state.refreshDisplays() }
                    .controlSize(.small)
                Spacer()
                Button("Quit") { NSApplication.shared.terminate(nil) }
                    .controlSize(.small)
            }
        }
        .padding(16)
        .frame(width: 360)
    }

    private var modeDescription: String {
        guard state.separateCursorEnabled else {
            return "The mouse and trackpad both use the normal macOS cursor."
        }
        return "\(state.overlayInputSource.displayName) uses the overlay; \(state.overlayInputSource.other.displayName.lowercased()) keeps the normal cursor."
    }

    private var statusText: String {
        if !state.separateCursorEnabled { return "Single cursor mode" }
        if state.devices.isEmpty { return "No external mouse detected" }
        if !state.hidExclusive { return "Mouse detected; capture unavailable" }
        if state.overlayInputSource == .builtInTrackpad {
            return state.trackpadIsolationActive ? "Cursor controls swapped" : "Trackpad capture unavailable"
        }
        return "External mouse isolated"
    }

    private var emptyStateText: String {
        if !state.separateCursorEnabled {
            return "Turn on separate cursor mode to use the external mouse independently."
        }
        if state.hidAvailable {
            return "Connect or enable the external mouse, then rescan."
        }
        return "LazyMouse could not open the HID manager. Check Input Monitoring permission, then rescan."
    }

    private var isolationReady: Bool {
        state.hidExclusive
            && (state.overlayInputSource == .externalMouse || state.trackpadIsolationActive)
    }
}

private struct CursorColorWell: NSViewRepresentable {
    let color: NSColor
    let onChange: (NSColor) -> Void

    func makeCoordinator() -> Coordinator {
        Coordinator(onChange: onChange)
    }

    func makeNSView(context: Context) -> NSColorWell {
        let colorWell = NSColorWell()
        colorWell.color = color
        colorWell.setAccessibilityLabel("Cursor color")
        colorWell.identifier = NSUserInterfaceItemIdentifier("cursor-color-well")
        colorWell.target = context.coordinator
        colorWell.action = #selector(Coordinator.colorChanged(_:))
        return colorWell
    }

    func updateNSView(_ nsView: NSColorWell, context: Context) {
        if nsView.color != color {
            nsView.color = color
        }
        context.coordinator.onChange = onChange
    }

    final class Coordinator: NSObject {
        var onChange: (NSColor) -> Void

        init(onChange: @escaping (NSColor) -> Void) {
            self.onChange = onChange
        }

        @objc func colorChanged(_ sender: NSColorWell) {
            onChange(sender.color)
        }
    }
}

private struct DeviceRow: View {
    @EnvironmentObject private var state: AppState
    let device: MouseDevice

    var body: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(device.name)
                .font(.callout.weight(.medium))
                .lineLimit(1)
            Picker("Boundary", selection: Binding<CursorBoundary>(
                get: { state.boundary(for: device) },
                set: { state.setBoundary($0, for: device) }
            )) {
                Text("Free - all displays").tag(CursorBoundary.free)
                ForEach(state.displays) { display in
                    Text(display.name).tag(CursorBoundary.display(display.id))
                }
            }
            .labelsHidden()
            .pickerStyle(.menu)
        }
        .padding(.vertical, 3)
    }
}
