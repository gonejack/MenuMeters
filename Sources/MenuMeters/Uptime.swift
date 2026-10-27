//
//  Uptime.swift
//  MenuMeters
//

import Cocoa

enum Uptime {
    static func string() -> String {
        var bootTime = timeval()
        var size = MemoryLayout<timeval>.size
        var mib: [Int32] = [CTL_KERN, KERN_BOOTTIME]
        guard sysctl(&mib, 2, &bootTime, &size, nil, 0) == 0 else {
            return String(format: L("%02ld:%02ld:%02ld"), 0, 0, 0)
        }

        var remaining = max(0, time(nil) - bootTime.tv_sec)
        let days = remaining / 86_400
        remaining %= 86_400
        let hours = remaining / 3_600
        remaining %= 3_600
        let minutes = remaining / 60
        let seconds = remaining % 60

        if days > 1 {
            return String(format: L("%ld days %02ld:%02ld:%02ld"), days, hours, minutes, seconds)
        }
        if days == 1 {
            return String(format: L("%ld day %02ld:%02ld:%02ld"), days, hours, minutes, seconds)
        }
        return String(format: L("%02ld:%02ld:%02ld"), hours, minutes, seconds)
    }
}
