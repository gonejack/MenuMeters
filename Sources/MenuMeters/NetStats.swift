//
//  NetStats.swift
//  MenuMeters
//
//  Network interface byte counters with per-interface deltas, peaks and totals.
//

import Foundation
import Darwin

struct NetInterfaceStats {
    var ifIn: UInt32
    var ifOut: UInt32
    var deltaIn: UInt64
    var deltaOut: UInt64
    var totalIn: UInt64
    var totalOut: UInt64
    var peak: Double
    var hasDeltas: Bool
}

final class NetStats {
    private let ppp = NetPPP.shared
    private var lastData: [String: NetInterfaceStats] = [:]

    private struct InterfaceCounters {
        let name: String
        let input: UInt32
        let output: UInt32
        let isUp: Bool
    }

    init() {
        // Prime the counters so the first displayed sample has a baseline.
        _ = netStats(forInterval: 1.0)
    }

    func netStats(forInterval interval: TimeInterval) -> [String: NetInterfaceStats]? {
        guard let interfaces = readInterfaces() else { return nil }

        var newData: [String: NetInterfaceStats] = [:]
        for interface in interfaces {
            if interface.name.hasPrefix("ppp") {
                guard let status = ppp.status(forInterfaceName: interface.name),
                      status.status == NetPPP.running,
                      let input = status.inBytes,
                      let output = status.outBytes else { continue }
                newData[interface.name] = updatedStats(name: interface.name,
                                                       input: input,
                                                       output: output,
                                                       isUp: true,
                                                       interval: interval)
            } else {
                newData[interface.name] = updatedStats(name: interface.name,
                                                       input: interface.input,
                                                       output: interface.output,
                                                       isUp: interface.isUp,
                                                       interval: interval)
            }
        }

        lastData = newData
        return newData
    }

    func resetTotals(forInterface name: String) {
        guard var stats = lastData[name] else { return }
        stats.totalIn = 0
        stats.totalOut = 0
        lastData[name] = stats
    }

    // MARK: - Counter math

    private func updatedStats(name: String, input: UInt32, output: UInt32,
                              isUp: Bool, interval: TimeInterval) -> NetInterfaceStats {
        guard let old = lastData[name], isUp else {
            return NetInterfaceStats(ifIn: input,
                                     ifOut: output,
                                     deltaIn: 0,
                                     deltaOut: 0,
                                     totalIn: UInt64(input),
                                     totalOut: UInt64(output),
                                     peak: 0,
                                     hasDeltas: false)
        }

        let totalIn = wrappedTotal(current: input, previous: old.ifIn,
                                   previousTotal: old.totalIn)
        let totalOut = wrappedTotal(current: output, previous: old.ifOut,
                                    previousTotal: old.totalOut)
        let deltaIn = totalIn > old.totalIn ? totalIn - old.totalIn : 0
        let deltaOut = totalOut > old.totalOut ? totalOut - old.totalOut : 0

        var peak = old.peak
        if interval > 0 {
            peak = max(peak, Double(deltaIn) / interval, Double(deltaOut) / interval)
        }

        return NetInterfaceStats(ifIn: input,
                                 ifOut: output,
                                 deltaIn: deltaIn,
                                 deltaOut: deltaOut,
                                 totalIn: totalIn,
                                 totalOut: totalOut,
                                 peak: peak,
                                 hasDeltas: true)
    }

    /// Interface counters are 32-bit and wrap; retain the wrap adjustment in a
    /// 64-bit total. The one-byte addition accounts for the counter stepping
    /// from UInt32.max to zero.
    private func wrappedTotal(current: UInt32, previous: UInt32,
                              previousTotal: UInt64) -> UInt64 {
        if previous > current {
            return previousTotal + UInt64(current) + UInt64(UInt32.max)
                - UInt64(previous) + 1
        }
        return previousTotal + UInt64(current - previous)
    }

    // MARK: - Interface enumeration

    private func readInterfaces() -> [InterfaceCounters]? {
        var addressList: UnsafeMutablePointer<ifaddrs>?
        guard getifaddrs(&addressList) == 0, let first = addressList else { return nil }
        defer { freeifaddrs(addressList) }

        var interfaces: [InterfaceCounters] = []
        var pointer: UnsafeMutablePointer<ifaddrs>? = first
        while let current = pointer {
            let interface = current.pointee
            pointer = interface.ifa_next

            guard let address = interface.ifa_addr,
                  address.pointee.sa_family == UInt8(AF_LINK),
                  let data = interface.ifa_data,
                  interface.ifa_flags & UInt32(IFF_LOOPBACK) == 0 else { continue }

            let counters = data.assumingMemoryBound(to: if_data.self).pointee
            interfaces.append(InterfaceCounters(
                name: String(cString: interface.ifa_name),
                input: counters.ifi_ibytes,
                output: counters.ifi_obytes,
                isUp: interface.ifa_flags & UInt32(IFF_UP) != 0
            ))
        }
        return interfaces
    }
}
