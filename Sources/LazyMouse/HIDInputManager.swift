import Foundation
import IOKit.hid
import OSLog

final class HIDInputManager {
    typealias DeviceHandler = ([MouseDevice]) -> Void
    typealias DeltaHandler = (String, CGPoint) -> Void
    typealias ButtonHandler = (String, Int, Bool) -> Void
    typealias ScrollHandler = (String, CGFloat) -> Void

    var onDevicesChanged: DeviceHandler?
    var onDelta: DeltaHandler?
    var onButton: ButtonHandler?
    var onScroll: ScrollHandler?
    private(set) var isAvailable = false
    private(set) var isExclusive = false

    private let manager: IOHIDManager
    private let logger = Logger(subsystem: "com.engbyume.LazyMouse", category: "HID")
    private var devices: [String: MouseDevice] = [:]
    private var deviceIDs: [ObjectIdentifier: String] = [:]
    private var seizedDevices: [ObjectIdentifier: IOHIDDevice] = [:]
    private var started = false
    private var discoveryOpen = false
    private var discoveryScheduled = false
    private var exclusiveLifecycleOpen = false
    private var exclusiveLifecycleScheduled = false
    private var loggedFirstInput = false

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
        guard !started else {
            if isExclusive {
                rescan()
            } else {
                retryExclusiveCapture()
            }
            return
        }

        started = true
        loggedFirstInput = false
        let context = Unmanaged.passUnretained(self).toOpaque()
        if tryStartExclusiveCapture(context: context) {
            isAvailable = true
            rescan()
            return
        }

        _ = startDiscovery(context: context)
        rescan()
    }

    func rescan() {
        guard started else { return }
        guard let currentDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            logger.error("HID manager returned no device set")
            return
        }
        logger.info("HID manager enumerated \(currentDevices.count) devices")
        for device in currentDevices {
            let product = stringProperty(kIOHIDProductKey, device: device) ?? "<none>"
            if product.localizedCaseInsensitiveContains("mouse") || product.localizedCaseInsensitiveContains("trackpad") {
                let usage = numberProperty(kIOHIDDeviceUsageKey, device: device) ?? 0
                let primaryUsage = numberProperty(kIOHIDPrimaryUsageKey, device: device) ?? 0
                let builtIn = numberProperty(kIOHIDBuiltInKey, device: device) ?? 0
                logger.info("HID candidate \(product), usage \(usage), primary \(primaryUsage), built-in \(builtIn)")
            }
            addIfPointing(device)
        }
    }

    func retryExclusiveCapture() {
        guard started, !isExclusive else {
            rescan()
            return
        }

        closeDiscovery()
        devices.removeAll()
        deviceIDs.removeAll()

        let context = Unmanaged.passUnretained(self).toOpaque()
        if tryStartExclusiveCapture(context: context) {
            isAvailable = true
        } else {
            _ = startDiscovery(context: context)
        }
        rescan()
        if devices.isEmpty {
            notifyDevices()
        }
    }

    func stop() {
        guard started else { return }
        closeCapture()
        closeDiscovery()
        devices.removeAll()
        deviceIDs.removeAll()
        notifyDevices()
        started = false
        isAvailable = false
    }

    private func startDiscovery(context: UnsafeMutableRawPointer) -> Bool {
        guard !discoveryOpen else { return true }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceAdded, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemoved, context)
        IOHIDManagerRegisterInputValueCallback(manager, Self.inputValue, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        discoveryScheduled = true

        let result = IOHIDManagerOpen(manager, 0)
        guard result == kIOReturnSuccess else {
            logger.error("HID manager open failed: \(result)")
            logger.info("Continuing HID discovery without live input access")
            closeDiscovery()
            isAvailable = false
            return false
        }

        discoveryOpen = true
        isAvailable = true
        logger.info("HID manager opened")
        return true
    }

    private func closeDiscovery() {
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        IOHIDManagerRegisterInputValueCallback(manager, nil, nil)
        if discoveryScheduled {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            discoveryScheduled = false
        }
        if discoveryOpen {
            IOHIDManagerClose(manager, 0)
            discoveryOpen = false
        }
    }

    private func closeCapture() {
        closeExclusiveLifecycle()
        for device in seizedDevices.values {
            IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, 0)
        }
        seizedDevices.removeAll()
        isExclusive = false
    }

    private func addIfPointing(_ device: IOHIDDevice) {
        guard isPointingDevice(device) else { return }
        if seizedDevices[ObjectIdentifier(device)] == nil && (exclusiveLifecycleScheduled || !seizedDevices.isEmpty) {
            return
        }
        add(device)
    }

    private func add(_ device: IOHIDDevice) {
        let objectKey = ObjectIdentifier(device)
        if let existingID = deviceIDs[objectKey] {
            devices[existingID] = describe(device, id: existingID)
            notifyDevices()
            return
        }

        let baseID = stableID(for: device)
        deviceIDs[objectKey] = baseID
        devices[baseID] = describe(device, id: baseID)
        notifyDevices()
    }

    private func tryStartExclusiveCapture(context: UnsafeMutableRawPointer) -> Bool {
        guard !isExclusive else { return true }
        guard let currentDevices = IOHIDManagerCopyDevices(manager) as? Set<IOHIDDevice> else {
            logger.error("HID manager returned no devices for exclusive capture")
            return false
        }

        let candidates = currentDevices
            .filter(isPointingDevice)
            .reduce(into: [String: [IOHIDDevice]]()) { result, device in
                result[stableID(for: device), default: []].append(device)
            }

        var captured = false
        for (_, devicesForID) in candidates.sorted(by: { $0.key < $1.key }) {
            for device in devicesForID {
                let result = IOHIDDeviceOpen(device, IOOptionBits(kIOHIDOptionsTypeSeizeDevice))
                guard result == kIOReturnSuccess else {
                    logger.error("Exclusive HID capture unavailable for one device: \(result)")
                    continue
                }

                seizedDevices[ObjectIdentifier(device)] = device
                addIfPointing(device)
                IOHIDDeviceRegisterInputValueCallback(device, Self.inputValue, context)
                IOHIDDeviceScheduleWithRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
                captured = true
                break
            }
            if captured { break }
        }

        guard !seizedDevices.isEmpty else {
            closeCapture()
            return false
        }

        isExclusive = true
        startExclusiveLifecycle(context: context)
        logger.info("Exclusive external HID capture active for \(self.seizedDevices.count) HID services")
        return true
    }

    private func remove(_ device: IOHIDDevice) {
        let key = ObjectIdentifier(device)
        let wasSeized = seizedDevices.removeValue(forKey: key) != nil
        if wasSeized {
            IOHIDDeviceRegisterInputValueCallback(device, nil, nil)
            IOHIDDeviceUnscheduleFromRunLoop(device, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            IOHIDDeviceClose(device, 0)
            if seizedDevices.isEmpty {
                isExclusive = false
                logger.info("Exclusive HID device removed; waiting for a replacement")
            }
        }
        if let id = deviceIDs.removeValue(forKey: key) {
            if !deviceIDs.values.contains(id) {
                devices.removeValue(forKey: id)
            }
            notifyDevices()
        }
    }

    private func startExclusiveLifecycle(context: UnsafeMutableRawPointer) {
        guard !exclusiveLifecycleScheduled else { return }
        IOHIDManagerRegisterDeviceMatchingCallback(manager, Self.deviceAdded, context)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, Self.deviceRemoved, context)
        IOHIDManagerScheduleWithRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
        exclusiveLifecycleScheduled = true

        let result = IOHIDManagerOpen(manager, 0)
        guard result == kIOReturnSuccess else {
            logger.error("HID lifecycle manager open failed: \(result)")
            closeExclusiveLifecycle()
            return
        }
        exclusiveLifecycleOpen = true
    }

    private func closeExclusiveLifecycle() {
        IOHIDManagerRegisterDeviceMatchingCallback(manager, nil, nil)
        IOHIDManagerRegisterDeviceRemovalCallback(manager, nil, nil)
        if exclusiveLifecycleScheduled {
            IOHIDManagerUnscheduleFromRunLoop(manager, CFRunLoopGetMain(), CFRunLoopMode.defaultMode.rawValue)
            exclusiveLifecycleScheduled = false
        }
        if exclusiveLifecycleOpen {
            IOHIDManagerClose(manager, 0)
            exclusiveLifecycleOpen = false
        }
    }

    private func notifyDevices() {
        let sorted = devices.values.sorted {
            $0.name.localizedStandardCompare($1.name) == .orderedAscending
        }
        logger.info("Accepted external HID mice: \(sorted.map(\.name).joined(separator: ", "))")
        onDevicesChanged?(Array(sorted.prefix(1)))
    }

    private func isPointingDevice(_ device: IOHIDDevice) -> Bool {
        guard isPhysicalMouse(device) else { return false }

        let usagePage = numberProperty(kIOHIDDeviceUsagePageKey, device: device)
        let usage = numberProperty(kIOHIDDeviceUsageKey, device: device)
        if isPointingUsage(page: usagePage, usage: usage) {
            return true
        }

        let primaryPage = numberProperty(kIOHIDPrimaryUsagePageKey, device: device)
        let primaryUsage = numberProperty(kIOHIDPrimaryUsageKey, device: device)
        if isPointingUsage(page: primaryPage, usage: primaryUsage) {
            return true
        }

        let product = (stringProperty(kIOHIDProductKey, device: device) ?? "").lowercased()
        guard product.contains("mouse") else { return false }
        guard let elements = IOHIDDeviceCopyMatchingElements(device, nil, 0) as? [IOHIDElement] else {
            return false
        }
        var hasX = false
        var hasY = false
        for element in elements {
            guard IOHIDElementGetUsagePage(element) == kHIDPage_GenericDesktop else { continue }
            let elementUsage = IOHIDElementGetUsage(element)
            hasX = hasX || elementUsage == kHIDUsage_GD_X
            hasY = hasY || elementUsage == kHIDUsage_GD_Y
        }
        return hasX && hasY
    }

    private func isPointingUsage(page: UInt32?, usage: UInt32?) -> Bool {
        guard let page, page == UInt32(kHIDPage_GenericDesktop), let usage else { return false }
        return usage == UInt32(kHIDUsage_GD_Mouse) || usage == UInt32(kHIDUsage_GD_Pointer)
    }

    private func stableID(for device: IOHIDDevice) -> String {
        let vendor = numberProperty(kIOHIDVendorIDKey, device: device) ?? 0
        let product = numberProperty(kIOHIDProductIDKey, device: device) ?? 0
        let serial = stringProperty(kIOHIDSerialNumberKey, device: device)
        let location = numberProperty(kIOHIDLocationIDKey, device: device)
        let transport = stringProperty(kIOHIDTransportKey, device: device) ?? "unknown"

        if let serial, !serial.isEmpty {
            return "serial-\(sanitized(serial))-\(vendor)-\(product)"
        }
        if let location {
            return "location-\(vendor)-\(product)-\(location)"
        }

        let productName = sanitized(stringProperty(kIOHIDProductKey, device: device) ?? "pointing-device")
        return "device-\(vendor)-\(product)-\(sanitized(transport))-\(productName)"
    }

    private func describe(_ device: IOHIDDevice, id: String) -> MouseDevice {
        let vendor = numberProperty(kIOHIDVendorIDKey, device: device) ?? 0
        let product = numberProperty(kIOHIDProductIDKey, device: device) ?? 0
        let productName = stringProperty(kIOHIDProductKey, device: device) ?? "Pointing device"
        let manufacturer = stringProperty(kIOHIDManufacturerKey, device: device)
        let transport = stringProperty(kIOHIDTransportKey, device: device)
        return MouseDevice(
            id: id,
            name: productName,
            manufacturer: manufacturer,
            transport: transport,
            vendorID: vendor,
            productID: product
        )
    }

    private func isPhysicalMouse(_ device: IOHIDDevice) -> Bool {
        if let builtIn = numberProperty(kIOHIDBuiltInKey, device: device), builtIn != 0 {
            return false
        }

        let product = (stringProperty(kIOHIDProductKey, device: device) ?? "").lowercased()
        return !product.contains("trackpad") && !product.contains("internal keyboard") && !product.contains("keyboard")
    }

    private func numberProperty(_ key: String, device: IOHIDDevice) -> UInt32? {
        (IOHIDDeviceGetProperty(device, (key as NSString) as CFString) as? NSNumber)?.uint32Value
    }

    private func stringProperty(_ key: String, device: IOHIDDevice) -> String? {
        IOHIDDeviceGetProperty(device, (key as NSString) as CFString) as? String
    }

    private func sanitized(_ value: String) -> String {
        value.replacingOccurrences(of: "[^A-Za-z0-9._-]", with: "_", options: .regularExpression)
    }

    private static let deviceAdded: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        let manager = Unmanaged<HIDInputManager>.fromOpaque(context).takeUnretainedValue()
        if manager.exclusiveLifecycleScheduled {
            _ = manager.tryStartExclusiveCapture(context: context)
            manager.rescan()
        } else {
            manager.addIfPointing(device)
        }
    }

    private static let deviceRemoved: IOHIDDeviceCallback = { context, _, _, device in
        guard let context else { return }
        Unmanaged<HIDInputManager>.fromOpaque(context).takeUnretainedValue().remove(device)
    }

    private static let inputValue: IOHIDValueCallback = { context, _, _, value in
        guard let context else { return }
        let manager = Unmanaged<HIDInputManager>.fromOpaque(context).takeUnretainedValue()
        if !manager.loggedFirstInput {
            manager.loggedFirstInput = true
            manager.logger.info("HID input callback active")
        }
        let element = IOHIDValueGetElement(value)
        let page = IOHIDElementGetUsagePage(element)
        let usage = IOHIDElementGetUsage(element)
        let device = IOHIDElementGetDevice(element)
        let key = ObjectIdentifier(device)
        let deviceID: String
        if let existingID = manager.deviceIDs[key] {
            deviceID = existingID
        } else {
            manager.addIfPointing(device)
            guard let newDeviceID = manager.deviceIDs[key] else { return }
            deviceID = newDeviceID
        }
        manager.routeInput(deviceID: deviceID, page: page, usage: usage, value: value)
    }

    private func routeInput(deviceID: String, page: UInt32, usage: UInt32, value: IOHIDValue) {
        if page == kHIDPage_GenericDesktop,
           usage == kHIDUsage_GD_X || usage == kHIDUsage_GD_Y {
            let amount = CGFloat(IOHIDValueGetIntegerValue(value))
            let delta = usage == kHIDUsage_GD_X ? CGPoint(x: amount, y: 0) : CGPoint(x: 0, y: -amount)
            onDelta?(deviceID, delta)
            return
        }

        if page == kHIDPage_Button, usage >= 1, usage <= 5 {
            onButton?(deviceID, Int(usage), IOHIDValueGetIntegerValue(value) != 0)
            return
        }

        if page == kHIDPage_GenericDesktop, usage == kHIDUsage_GD_Wheel {
            onScroll?(deviceID, CGFloat(IOHIDValueGetIntegerValue(value)))
        }
    }
}
