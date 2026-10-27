//
//  DiskIO.swift
//  MenuMeters
//
//  Block-device read/write activity from IOKit.
//

import Cocoa
import IOKit

final class DiskIO {
    private static let driverClass = "IOBlockStorageDriver"
    private static let statisticsKey = "Statistics"
    private static let bytesReadKey = "Bytes (Read)"
    private static let bytesWrittenKey = "Bytes (Write)"

    private var masterPort: mach_port_t = 0
    private var notifyPort: IONotificationPortRef?
    private var notifyRunSource: CFRunLoopSource?
    private var publishedIterator: io_iterator_t = 0
    private var terminatedIterator: io_iterator_t = 0
    private var deviceIterator: io_iterator_t = 0
    private var previousTotalRead: UInt64 = 0
    private var previousTotalWrite: UInt64 = 0

    init?() {
        guard IOMainPort(mach_port_t(MACH_PORT_NULL), &masterPort) == KERN_SUCCESS, masterPort != 0 else {
            return nil
        }
        guard let port = IONotificationPortCreate(masterPort) else { return nil }
        notifyPort = port
        guard let source = IONotificationPortGetRunLoopSource(port)?.takeUnretainedValue() else {
            cleanup()
            return nil
        }
        notifyRunSource = source
        CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)

        let refcon = Unmanaged.passUnretained(self).toOpaque()
        let callback: IOServiceMatchingCallback = { refcon, iterator in
            guard let refcon else { return }
            Unmanaged<DiskIO>.fromOpaque(refcon).takeUnretainedValue().blockDeviceChanged(iterator)
        }
        guard IOServiceAddMatchingNotification(port, kIOPublishNotification,
                                               IOServiceMatching(Self.driverClass),
                                               callback, refcon, &publishedIterator) == KERN_SUCCESS,
              IOServiceAddMatchingNotification(port, kIOTerminatedNotification,
                                               IOServiceMatching(Self.driverClass),
                                               callback, refcon, &terminatedIterator) == KERN_SUCCESS else {
            cleanup()
            return nil
        }

        // Drain the notification iterators and seed the counters.
        blockDeviceChanged(publishedIterator)
        blockDeviceChanged(terminatedIterator)
        _ = diskIOActivity()
    }

    deinit {
        cleanup()
    }

    private func cleanup() {
        if deviceIterator != 0 { IOObjectRelease(deviceIterator); deviceIterator = 0 }
        if publishedIterator != 0 { IOObjectRelease(publishedIterator); publishedIterator = 0 }
        if terminatedIterator != 0 { IOObjectRelease(terminatedIterator); terminatedIterator = 0 }
        if let notifyRunSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), notifyRunSource, .defaultMode)
            self.notifyRunSource = nil
        }
        if let notifyPort {
            IONotificationPortDestroy(notifyPort)
            self.notifyPort = nil
        }
        if masterPort != 0 {
            mach_port_deallocate(mach_task_self_, masterPort)
            masterPort = 0
        }
    }

    // MARK: - Activity

    func diskIOActivity() -> DiskActivity {
        if deviceIterator == 0 {
            guard IOServiceGetMatchingServices(masterPort, IOServiceMatching(Self.driverClass),
                                               &deviceIterator) == KERN_SUCCESS else {
                return .idle
            }
        }

        var totalRead: UInt64 = 0
        var totalWrite: UInt64 = 0
        while true {
            let entry = IOIteratorNext(deviceIterator)
            guard entry != 0 else { break }
            if let property = IORegistryEntryCreateCFProperty(entry, Self.statisticsKey as CFString,
                                                              kCFAllocatorDefault, 0)?
                .takeRetainedValue() as? [String: Any] {
                totalRead += (property[Self.bytesReadKey] as? NSNumber)?.uint64Value ?? 0
                totalWrite += (property[Self.bytesWrittenKey] as? NSNumber)?.uint64Value ?? 0
            }
            IOObjectRelease(entry)
        }
        IOIteratorReset(deviceIterator)

        // Only changes matter: unmounts and counter overflows are treated as
        // activity too, which is close enough for a menu bar indicator.
        let activity: DiskActivity
        if totalRead != previousTotalRead && totalWrite != previousTotalWrite {
            activity = .readWrite
        } else if totalRead != previousTotalRead {
            activity = .read
        } else if totalWrite != previousTotalWrite {
            activity = .write
        } else {
            activity = .idle
        }
        previousTotalRead = totalRead
        previousTotalWrite = totalWrite
        return activity
    }

    private func blockDeviceChanged(_ iterator: io_iterator_t) {
        if deviceIterator != 0 {
            IOObjectRelease(deviceIterator)
            deviceIterator = 0
        }
        while true {
            let device = IOIteratorNext(iterator)
            guard device != 0 else { break }
            IOObjectRelease(device)
        }
    }
}
