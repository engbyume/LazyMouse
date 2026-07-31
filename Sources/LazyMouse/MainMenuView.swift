import SwiftUI
import AppKit
import LazyMouseCore

struct MainMenuView: View {
    @EnvironmentObject private var state: AppState

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack {
                Label("LazyMouse", systemImage: "cursorarrow.rays")
                    .font(.headline)
                Spacer()
                Circle()
                    .fill(state.accessibilityTrusted ? .green : .orange)
                    .frame(width: 8, height: 8)
            }

            Toggle("Independent cursor mode", isOn: Binding(
                get: { state.independentMode },
                set: { state.setIndependentMode($0) }
            ))
            .help("Suppress ordinary mouse movement so each HID mouse can have its own overlay cursor")

            if !state.accessibilityTrusted {
                VStack(alignment: .leading, spacing: 6) {
                    Text("Accessibility permission is needed for independent mode.")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                    Button("Open Accessibility Settings") {
                        state.openAccessibilitySettings()
                    }
                    .buttonStyle(.borderedProminent)
                    .controlSize(.small)
                }
            }

            Divider()
            Text(state.devices.isEmpty ? "No pointing devices detected" : "Detected mice")
                .font(.subheadline.weight(.semibold))

            if state.devices.isEmpty {
                Text("Connect a USB, Bluetooth, or receiver-based mouse, then wait a moment.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(state.devices) { device in
                    DeviceRow(device: device)
                }
            }

            Divider()
            HStack {
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
