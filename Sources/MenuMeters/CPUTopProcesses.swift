//
//  CPUTopProcesses.swift
//  MenuMeters
//
//  Snapshot of the most CPU-intensive processes.
//

import Cocoa
import Darwin

struct ProcessListItem {
    let pid: pid_t
    let name: String
    let cpuPercent: Double
}

private struct ProcessSample {
    let pid: pid_t
    let cpuTime: UInt64
    let name: String
}

final class CPUTopProcesses {
    private var processes: [ProcessListItem] = []

    func startUpdateProcessList() {
        let first = Self.collectSamples()
        let start = mach_absolute_time()
        usleep(100 * 1000)
        let end = mach_absolute_time()
        let second = Self.collectSamples()

        guard !first.isEmpty, !second.isEmpty, end > start else { return }
        let wall = Double(end - start)

        var previous: [pid_t: UInt64] = [:]
        previous.reserveCapacity(first.count)
        for sample in first { previous[sample.pid] = sample.cpuTime }

        let entries = second.map { sample -> ProcessListItem in
            var percent = 0.0
            if let old = previous[sample.pid], sample.cpuTime >= old {
                percent = Double(sample.cpuTime - old) / wall * 100
            }
            return ProcessListItem(pid: sample.pid,
                                   name: Self.normalizedCommand(sample.name),
                                   cpuPercent: percent)
        }.sorted {
            if $0.cpuPercent != $1.cpuPercent { return $0.cpuPercent > $1.cpuPercent }
            return $0.name.localizedCompare($1.name) == .orderedAscending
        }

        processes = entries
    }

    func stopUpdateProcessList() {
        // Sampling is synchronous; keep the last result for the visible menu.
    }

    func runningProcesses(byCPUUsage maximum: Int) -> [ProcessListItem] {
        Array(processes.prefix(max(0, maximum)))
    }

    // MARK: - Sampling

    private static func collectSamples() -> [ProcessSample] {
        let capacity = proc_listallpids(nil, 0)
        guard capacity > 0 else { return [] }

        var pids = [pid_t](repeating: 0, count: Int(capacity))
        let count = pids.withUnsafeMutableBytes {
            proc_listallpids($0.baseAddress, Int32($0.count))
        }
        guard count > 0 else { return [] }

        var samples: [ProcessSample] = []
        samples.reserveCapacity(Int(count))
        for index in 0..<Int(count) {
            let pid = pids[index]
            guard pid > 0 else { continue }

            var taskInfo = proc_taskinfo()
            let taskInfoSize = MemoryLayout<proc_taskinfo>.size
            guard proc_pidinfo(pid, PROC_PIDTASKINFO, 0, &taskInfo, Int32(taskInfoSize)) == taskInfoSize else {
                continue
            }

            var bsdInfo = proc_bsdinfo()
            let bsdInfoSize = MemoryLayout<proc_bsdinfo>.size
            guard proc_pidinfo(pid, PROC_PIDTBSDINFO, 0, &bsdInfo, Int32(bsdInfoSize)) == bsdInfoSize else {
                continue
            }

            let name = withUnsafeBytes(of: bsdInfo.pbi_name) { raw -> String in
                guard let base = raw.baseAddress else { return "" }
                return String(cString: base.assumingMemoryBound(to: CChar.self))
            }
            let command = withUnsafeBytes(of: bsdInfo.pbi_comm) { raw -> String in
                guard let base = raw.baseAddress else { return "" }
                return String(cString: base.assumingMemoryBound(to: CChar.self))
            }

            samples.append(ProcessSample(pid: pid,
                                         cpuTime: taskInfo.pti_total_user + taskInfo.pti_total_system,
                                         name: name.isEmpty ? command : name))
        }
        return samples
    }

    private static func normalizedCommand(_ name: String) -> String {
        var result = name.trimmingCharacters(in: .whitespacesAndNewlines)
        for _ in 0..<2 where result.hasPrefix("-") {
            result.removeFirst()
        }
        return result
    }
}
