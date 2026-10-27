//
//  PowerMate.swift
//  MenuMeters
//
//  Griffin PowerMate LED support.
//

import Cocoa
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib

final class PowerMate {
    private static let glowRampInterval: TimeInterval = 0.05

    private var masterPort: mach_port_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifySource: CFRunLoopSource?
    private var matchedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var deviceInterface: UnsafeMutablePointer<IOUSBDeviceInterface>?
    private var devicePresent = false
    private var rampTimer: Timer?
    private var lastGlowLevel = 0.0
    private var targetGlowLevel = 0.0
    private var rampGlowStep = 0.0

    /// Whether a Griffin PowerMate is currently attached. Used to enable the
    /// corresponding preferences without opening the USB device.
    static func isAttached() -> Bool {
        var port: mach_port_t = 0
        guard IOMainPort(0, &port) == KERN_SUCCESS, port != 0 else { return false }
        defer { mach_port_deallocate(mach_task_self_, port) }
        guard let matching = IOServiceMatching("IOUSBDevice") else { return false }
        let dictionary = matching as NSMutableDictionary
        dictionary[kUSBVendorID] = 0x077d
        dictionary[kUSBProductID] = 0x0410
        var iterator: io_iterator_t = 0
        guard IOServiceGetMatchingServices(port, dictionary, &iterator) == KERN_SUCCESS else { return false }
        defer { IOObjectRelease(iterator) }
        let service = IOIteratorNext(iterator)
        if service != 0 { IOObjectRelease(service) }
        return service != 0
    }

    init?() {
        guard IOMainPort(0, &masterPort) == KERN_SUCCESS, masterPort != 0 else { return nil }
        notifyPort = IONotificationPortCreate(masterPort)
        guard let notifyPort else { return nil }
        notifySource = IONotificationPortGetRunLoopSource(notifyPort).takeUnretainedValue()
        if let notifySource {
            CFRunLoopAddSource(CFRunLoopGetCurrent(), notifySource, .defaultMode)
        }

        guard let matching = IOServiceMatching("IOUSBDevice") else { return nil }
        let dictionary = matching as NSMutableDictionary
        dictionary[kUSBVendorID] = 0x077d
        dictionary[kUSBProductID] = 0x0410
        guard let terminatedDictionary = CFDictionaryCreateMutableCopy(nil, 0, dictionary) else { return nil }

        let reference = Unmanaged.passUnretained(self).toOpaque()
        let matchedCallback: IOServiceMatchingCallback = { reference, iterator in
            guard let reference else { return }
            Unmanaged<PowerMate>.fromOpaque(reference).takeUnretainedValue().deviceMatched(iterator)
        }
        let terminatedCallback: IOServiceMatchingCallback = { reference, iterator in
            guard let reference else { return }
            Unmanaged<PowerMate>.fromOpaque(reference).takeUnretainedValue().deviceTerminated(iterator)
        }

        guard IOServiceAddMatchingNotification(notifyPort, kIOMatchedNotification, dictionary,
                                               matchedCallback, reference, &matchedIterator) == KERN_SUCCESS else { return nil }
        guard IOServiceAddMatchingNotification(notifyPort, kIOTerminatedNotification, terminatedDictionary,
                                               terminatedCallback, reference, &terminatedIterator) == KERN_SUCCESS else { return nil }

        // Pump both iterators; terminated first so state matches the final device set.
        deviceTerminated(terminatedIterator)
        deviceMatched(matchedIterator)
    }

    deinit {
        rampTimer?.invalidate()
        if let deviceInterface { _ = deviceInterface.pointee.Release(deviceInterface) }
        if matchedIterator != 0 { IOObjectRelease(matchedIterator) }
        if terminatedIterator != 0 { IOObjectRelease(terminatedIterator) }
        if let notifySource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), notifySource, .defaultMode)
        }
        if let notifyPort { IONotificationPortDestroy(notifyPort) }
        if masterPort != 0 { mach_port_deallocate(mach_task_self_, masterPort) }
    }

    // MARK: - LED control

    func setGlow(_ level: Double) {
        rampTimer?.invalidate()
        rampTimer = nil
        guard devicePresent, deviceInterface != nil else { return }

        let level = min(1, max(0, level))
        stopPulse()
        lastGlowLevel = level
        targetGlowLevel = level
        rampGlowStep = 0
        request(value: 0x01, index: UInt16(128 * level))
    }

    func setGlow(_ level: Double, rampInterval interval: TimeInterval) {
        rampTimer?.invalidate()
        rampTimer = nil
        guard devicePresent, deviceInterface != nil else { return }

        let level = min(1, max(0, level))
        stopPulse()
        guard interval > Self.glowRampInterval else {
            setGlow(level)
            return
        }

        rampGlowStep = (level - lastGlowLevel) / (interval / Self.glowRampInterval)
        targetGlowLevel = level
        let timer = Timer(timeInterval: Self.glowRampInterval, repeats: true) { [weak self] _ in
            self?.glowRamp()
        }
        RunLoop.current.add(timer, forMode: .common)
        rampTimer = timer
        glowRamp()
    }

    func setPulse(_ rate: Double) {
        guard devicePresent, deviceInterface != nil else { return }
        let rate = min(1, max(0, rate))
        request(value: 0x03, index: 0x01).self

        let pulseRate = UInt16(24 * rate)
        var index: UInt16
        if pulseRate > 2 {
            index = 0x02 | (pulseRate << 8)
        } else if pulseRate == 2 {
            index = 0x0001
        } else {
            index = (2 - pulseRate) << 8
        }
        request(value: 0x0104, index: index)
    }

    func stopPulse() {
        guard devicePresent, deviceInterface != nil else { return }
        request(value: 0x03, index: 0x00).self
    }

    // MARK: - Ramping

    private func glowRamp() {
        guard devicePresent, deviceInterface != nil else {
            rampTimer?.invalidate()
            rampTimer = nil
            return
        }
        let newLevel = min(1, max(0, lastGlowLevel + rampGlowStep))
        if (rampGlowStep > 0 && newLevel > targetGlowLevel)
            || (rampGlowStep <= 0 && newLevel < targetGlowLevel) {
            setGlow(targetGlowLevel)
            return
        }
        lastGlowLevel = newLevel
        request(value: 0x01, index: UInt16(128 * newLevel))
    }

    @discardableResult
    private func request(value: UInt16, index: UInt16) -> IOReturn {
        guard let deviceInterface else { return kIOReturnNoDevice }
        var request = IOUSBDevRequest(bmRequestType: 0x41, bRequest: 0x01,
                                      wValue: value, wIndex: index, wLength: 0,
                                      pData: nil, wLenDone: 0)
        return deviceInterface.pointee.DeviceRequest(deviceInterface, &request)
    }

    // MARK: - Device notifications

    private func deviceMatched(_ iterator: io_iterator_t) {
        let service = IOIteratorNext(iterator)
        guard service != 0 else { return }
        var other = IOIteratorNext(iterator)
        while other != 0 {
            IOObjectRelease(other)
            other = IOIteratorNext(iterator)
        }
        guard deviceInterface == nil else {
            IOObjectRelease(service)
            return
        }

        var plugIn: UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>?
        var score: Int32 = 0
        let userClientType = CFUUIDCreateFromString(nil, "9DC7B780-9EC0-11D4-A54F-000A27052861" as CFString)!
        let plugInType = CFUUIDCreateFromString(nil, "C244E858-109C-11D4-91D4-0050E4C6426F" as CFString)!
        let error = IOCreatePlugInInterfaceForService(service, userClientType, plugInType, &plugIn, &score)
        IOObjectRelease(service)
        guard error == KERN_SUCCESS, let plugIn else { return }
        defer { IODestroyPlugInInterface(plugIn) }

        var interface: UnsafeMutablePointer<IOUSBDeviceInterface>?
        let deviceType = CFUUIDCreateFromString(nil, "5C8187D0-9EF3-11D4-8B45-000A27052861" as CFString)!
        let uuid = CFUUIDGetUUIDBytes(deviceType)
        let queryResult = withUnsafeMutablePointer(to: &interface) { pointer -> IOReturn in
            let raw = UnsafeMutableRawPointer(pointer)
            return plugIn.pointee!.pointee.QueryInterface(plugIn, uuid,
                                                           raw.assumingMemoryBound(to: LPVOID?.self))
        }
        guard queryResult == 0, let interface else { return }

        guard interface.pointee.USBDeviceOpen(interface) == kIOReturnSuccess else {
            _ = interface.pointee.Release(interface)
            return
        }
        deviceInterface = interface
        devicePresent = true
        setGlow(0)
    }

    private func deviceTerminated(_ iterator: io_iterator_t) {
        if let deviceInterface { _ = deviceInterface.pointee.Release(deviceInterface) }
        deviceInterface = nil
        devicePresent = false
        var service = IOIteratorNext(iterator)
        while service != 0 {
            IOObjectRelease(service)
            service = IOIteratorNext(iterator)
        }
    }
}
