import Foundation
import IOKit.hid

final class HIDInputManager {
    typealias DeviceHandler = ([MouseDevice]) -> Void
    typealias DeltaHandler = (String, CGPoint) -> Void

    var onDevicesChanged: DeviceHandler?
    var onDelta: DeltaHandler?

    private let manager: IOHIDManager
    private var devices: [String: MouseDevice] = [:]
    private var deviceIDs: [ObjectIdentifier: String] = [:]
    private var started = false

    init() {
        manager = IOHIDManagerCreate(kCFAllocatorDefault, 0)
        let matching: [[String: Any]] = [
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Mouse
            ],
            [
                kIOHIDDeviceUsagePageKey as String: kHIDPage_GenericDesktop,
                kIOHIDDeviceUsageKey as String: kHIDUsage_GD_Pointer
            ]
        ]
        IOHIDManagerSetDeviceMatchingMultiple(manager, matching as CFArray)
    }

    deinit {
        stop()
    }

    func start() {
        guard !started else { return }
        started = true
        let context = Unmanaged.passUnretained(self).toOpaque()
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceAdded, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemoved, context)
        IOHIDManagerRegisterInputValueCallback(manager, Self.inputValue, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        let result = IOHIDManagerOpen(manager, 0)
        if result != kIOReturnSuccess {
            IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
            IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
            IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            started = false
        }
    }

    func stop() {
        guard started else { return }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        IOHIDManagerClose(manager, 0)
        started = false
    }

    private func add(_ device: IOHIDDevice) {
        let descriptor = describe(device)
        let key = ObjectIdentifier(device)
        deviceIDs[key] = descriptor.id
        devices[descriptor.id] = descriptor
        notifyDevices()
    }

    private func remove(_ device: IOHIDDevice) {
        let key = ObjectIdentifier(device)
        if let id = deviceIDs.removeValue(forKey: key) {
            devices.removeValue(forKey: id)
            notifyDevices()
        }
    }

    private func notifyDevices() {
        onDevicesChanged?(devices.values.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending })
    }

    private func describe(_ device: IOHIDDevice) -> MouseDevice {
        let vendor = numberProperty(kIOHIDVendorIDKey, device: device) ?? 0
        let product = numberProperty(kIOHIDProductIDKey, device: device) ?? 0
        let location = numberProperty(kIOHIDLocationIDKey, device: device) ?? UInt32(bitPattern: Int32(truncatingIfNeeded: ObjectIdentifier(device).hashValue))
        let productName = stringProperty(kIOHIDProductKey, device: device) ?? "Pointing device"
        let id = "\(vendor)-\(product)-\(location)"
        return MouseDevice(id: id, name: productName, vendorID: vendor, productID: product)
    }

    private func numberProperty(_ key: String, device: IOHIDDevice) -> UInt32? {
        (IOHIDDeviceGetProperty(device, (key as NSString) as CFString) as? NSNumber)?.uint32Value
    }

    private func stringProperty(_ key: String, device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, (key as NSString) as CFString) as? String
    }

    private static let deviceAdded: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<HIDInputManager>.fromOpaque(context).takeUnretainedValue().add(device)
    }

    private static let deviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<HIDInputManager>.fromOpaque(context).takeUnretainedValue().remove(device)
    }

    private static let inputValue: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        let manager = Unmanaged<HIDInputManager>.fromOpaque(context).takeUnretainedValue()
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        guard page == kHIDPage_GenericDesktop,
              usage == kHIDUsage_GD_X || usage == kHIDUsage_GD_Y else { return }
        let device = IOHIDElementGetDevice(element)
        let key = ObjectIdentifier(device)
        guard let deviceID = manager.deviceIDs[key] else {
            manager.add(device)
            return
        }
        let amount = CGFloat(IOHIDValueGetIntegerValue(value))
        let delta = usage == kHIDUsage_GD_X ? CGPoint(x: amount, y: 0) : CGPoint(x: 0, y: -amount)
        manager.onDelta?(deviceID, delta)
    }
}
