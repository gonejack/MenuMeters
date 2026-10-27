//
//  DiskSpace.swift
//  MenuMeters
//
//  Volume list and free-space statistics.
//

import Cocoa

struct DiskSpaceInfo {
    let name: String
    let path: String
    let device: String
    let fileSystem: String
    let icon: NSImage?
    let total: String
    let free: String
    let used: String
}

final class DiskSpace {
    private let localFileSystems: Set<String> = [
        "hfs", "apfs", "ufs", "msdos", "exfat", "ntfs", "cd9660", "cddafs", "udf"
    ]
    private let spaceFormatter: NumberFormatter = {
        let formatter = NumberFormatter()
        formatter.localizesFormat = true
        formatter.numberStyle = .decimal
        formatter.usesGroupingSeparator = false
        formatter.minimumFractionDigits = 2
        formatter.maximumFractionDigits = 2
        return formatter
    }()
    var useBaseTen = false

    func diskSpaceData() -> [DiskSpaceInfo] {
        var mountInfo: UnsafeMutablePointer<statfs>?
        let mountCount = getmntinfo(&mountInfo, MNT_WAIT)
        guard mountCount > 0, let mountInfo else { return [] }

        var volumes: [DiskSpaceInfo] = []
        for index in 0..<Int(mountCount) {
            let mount = mountInfo[index]
            let fileSystem = cString(mount.f_fstypename)
            guard localFileSystems.contains(fileSystem) else { continue }

            let path = cString(mount.f_mntonname)
            let url = URL(fileURLWithPath: path, isDirectory: true)
            let volumeName = (try? url.resourceValues(forKeys: [.volumeNameKey]))?.volumeName
            let name = volumeName ?? url.lastPathComponent

            let blockSize = Double(mount.f_bsize)
            let total = Double(mount.f_blocks) * blockSize
            let free = Double(mount.f_bavail) * blockSize
            let used = (Double(mount.f_blocks) - Double(mount.f_bavail)) * blockSize

            volumes.append(DiskSpaceInfo(
                name: name,
                path: path,
                device: cString(mount.f_mntfromname),
                fileSystem: fileSystem,
                icon: NSWorkspace.shared.icon(forFile: path),
                total: String(format: L("%@ Total"), spaceString(total)),
                free: String(format: L("%@ Free"), spaceString(free)),
                used: String(format: L("%@ Used"), spaceString(used))
            ))
        }

        // Device order is stable and matches users' expectations better than
        // mount order, which changes as volumes are mounted and unmounted.
        return volumes.sorted { $0.device < $1.device }
    }

    private func spaceString(_ space: Double) -> String {
        let base: Double = useBaseTen ? 1000 : 1024
        let unit: String
        let divisor: Double
        if space > base * base * base {
            divisor = base * base * base
            unit = "GB"
        } else if space > base * base {
            divisor = base * base
            unit = "MB"
        } else {
            divisor = base
            unit = "KB"
        }
        let number = spaceFormatter.string(from: NSNumber(value: space / divisor)) ?? "0.00"
        return number + L(unit)
    }

    private func cString<T>(_ value: T) -> String {
        var value = value
        return withUnsafePointer(to: &value) {
            $0.withMemoryRebound(to: CChar.self, capacity: MemoryLayout<T>.size) {
                String(cString: $0)
            }
        }
    }
}
