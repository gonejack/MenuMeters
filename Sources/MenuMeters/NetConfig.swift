//
//  NetConfig.swift
//  MenuMeters
//
//  SystemConfiguration and IOKit reader for network service details.
//

import Cocoa
import SystemConfiguration
import IOKit

struct NetInterfaceConfig {
    let serviceID: String
    let statName: String
    let speed: Double
    let name: String
    let isUp: Bool
}

struct NetInterfaceDetails {
    let serviceID: String
    var isPrimary = false
    var name = "Unknown Interface"
    var deviceName: String?
    var pppDeviceName: String?
    var connectionType: String?
    var pppStatus: PPPStatusResult?
    var ipv4Addresses: [String] = []
    var ipv6Addresses: [String] = []
    var appleTalkNetID: String?
    var appleTalkNodeID: String?
    var appleTalkZone: String?
    var linkActive: Bool?
    var linkSpeed: Double?
}

/// SystemConfiguration notification callback. The context is an unretained
/// NetConfig instance owned by the network menu extra.
private func netConfigChanged(store: SCDynamicStore?, changedKeys: CFArray?,
                              info: UnsafeMutableRawPointer?) {
    guard let info else { return }
    Unmanaged<NetConfig>.fromOpaque(info).takeUnretainedValue().configChanged()
}

final class NetConfig {
    /// Called on the main queue when SystemConfiguration reports a change.
    var onChange: (() -> Void)?

    private let ppp = NetPPP.shared
    private var store: SCDynamicStore?
    private var runLoopSource: CFRunLoopSource?
    private var masterPort: mach_port_t = 0

    // SystemConfiguration is slow enough that the original meter cached
    // almost everything and dropped the caches on SC notifications.
    private var cachedDetails: [NetInterfaceDetails]?
    private var cachedPrimaryName: String?
    private var cachedPrimaryService: String?
    private var cachedServiceToName: [String: String] = [:]
    private var cachedNameToService: [String: String] = [:]
    private var cachedServiceSpeed: [String: Double] = [:]
    private var cachedUnderlying: [String: String] = [:]
    private var cachedInterfaceUp: [String: Bool] = [:]

    init() {
        var context = SCDynamicStoreContext(version: 0,
                                            info: Unmanaged.passUnretained(self).toOpaque(),
                                            retain: nil,
                                            release: nil,
                                            copyDescription: nil)
        if let store = SCDynamicStoreCreate(nil, "MenuMeterNetConfig" as CFString,
                                            netConfigChanged, &context) {
            self.store = store
            let keys = ["State:/Network/Global/IPv4",
                        "Setup:/Network/Global/IPv4",
                        "State:/Network/Interface"] as CFArray
            let patterns = ["State:/Network/Interface.*"] as CFArray
            if SCDynamicStoreSetNotificationKeys(store, keys, patterns),
               let source = SCDynamicStoreCreateRunLoopSource(nil, store, 0) {
                runLoopSource = source
                CFRunLoopAddSource(CFRunLoopGetCurrent(), source, .defaultMode)
            } else {
                NSLog("MenuMeterNetConfig unable to install notification keys.")
            }
        } else {
            NSLog("MenuMeterNetConfig unable to establish configd session.")
        }

        var port: mach_port_t = 0
        if IOMainPort(0, &port) == KERN_SUCCESS {
            masterPort = port
        } else {
            NSLog("MenuMeterNetConfig unable to establish IOKit port.")
        }

        // Prime the caches while startup is cheap.
        _ = interfaceDetails()
        _ = primaryInterfaceName()
        _ = primaryServiceID()
    }

    deinit {
        if let source = runLoopSource {
            CFRunLoopRemoveSource(CFRunLoopGetCurrent(), source, .defaultMode)
        }
    }

    // MARK: - Public data

    func computerName() -> String? {
        guard let store else { return nil }
        return SCDynamicStoreCopyComputerName(store, nil) as String?
    }

    func interfaceConfig(for name: String?) -> NetInterfaceConfig? {
        if let name, name != MM.primaryInterface,
           let service = serviceForInterfaceName(name) {
            guard let statName = underlyingInterfaceNameForServiceID(service) else { return nil }
            return NetInterfaceConfig(serviceID: service,
                                      statName: statName,
                                      speed: speedForServiceID(service),
                                      name: name,
                                      isUp: interfaceNameIsUp(statName))
        }

        guard let service = primaryServiceID() else { return nil }
        let statName = underlyingInterfaceNameForServiceID(service)
        let primaryName = primaryInterfaceName()
        guard let underlying = statName ?? primaryName else { return nil }
        return NetInterfaceConfig(serviceID: service,
                                  statName: underlying,
                                  speed: speedForServiceID(service),
                                  name: MM.primaryInterface,
                                  isUp: interfaceNameIsUp(underlying))
    }

    func interfaceDetails() -> [NetInterfaceDetails] {
        if let cached = cachedDetails {
            var refreshed = cached
            for index in refreshed.indices where refreshed[index].pppStatus != nil {
                if let status = ppp.status(forServiceID: refreshed[index].serviceID) {
                    refreshed[index].pppStatus = status
                }
            }
            cachedDetails = refreshed
            return refreshed
        }

        guard let servicesDict = sysconfigValue("Setup:/Network/Global/IPv4"),
              var services = servicesDict["ServiceOrder"] as? [String] else { return [] }

        let primaryService = primaryServiceID()
        if let primaryService, let index = services.firstIndex(of: primaryService), index != 0 {
            let service = services.remove(at: index)
            services.insert(service, at: 0)
        }

        var detailsList: [NetInterfaceDetails] = []
        for serviceID in services {
            var displayName: String?
            if let serviceDict = sysconfigValue("Setup:/Network/Service/\(serviceID)"),
               let definedName = serviceDict["UserDefinedName"] as? String {
                displayName = definedName
            }

            guard let interfaceDict = sysconfigValue("Setup:/Network/Service/\(serviceID)/Interface") else {
                continue
            }
            if displayName == nil {
                if let definedName = interfaceDict["UserDefinedName"] as? String {
                    displayName = definedName
                } else if let hardware = interfaceDict["Hardware"] as? String {
                    displayName = hardware
                } else {
                    displayName = "Unknown Interface"
                }
            }

            var detail = NetInterfaceDetails(serviceID: serviceID)
            detail.isPrimary = (primaryService == serviceID)
            detail.name = displayName ?? "Unknown Interface"
            detail.deviceName = interfaceDict["DeviceName"] as? String
            detail.connectionType = (interfaceDict["SubType"] as? String)
                ?? (interfaceDict["Type"] as? String)

            let statePPP = sysconfigValue("State:/Network/Service/\(serviceID)/PPP")
            if let pppName = statePPP?["InterfaceName"] as? String {
                detail.pppDeviceName = pppName
            }
            if sysconfigValue("Setup:/Network/Service/\(serviceID)/PPP") != nil {
                detail.pppStatus = ppp.status(forServiceID: serviceID)
            }

            if let ipDict = sysconfigValue("State:/Network/Service/\(serviceID)/IPv4") {
                detail.ipv4Addresses = stringArray(ipDict["Addresses"])
            }
            if let device = detail.deviceName {
                if let ipDict = sysconfigValue("State:/Network/Interface/\(device)/IPv6") {
                    detail.ipv6Addresses = stringArray(ipDict["Addresses"])
                }
            }

            if let device = detail.deviceName,
               let appletalk = sysconfigValue("State:/Network/Interface/\(device)/AppleTalk"),
               appletalk["NetworkID"] != nil,
               appletalk["NodeID"] != nil,
               appletalk["DefaultZone"] != nil {
                detail.appleTalkNetID = displayText(appletalk["NetworkID"])
                detail.appleTalkNodeID = displayText(appletalk["NodeID"])
                detail.appleTalkZone = displayText(appletalk["DefaultZone"])
            }

            if let device = detail.deviceName,
               let link = sysconfigValue("State:/Network/Interface/\(device)/Link") {
                detail.linkActive = boolValue(link["Active"])
            }

            if let device = detail.deviceName {
                if device.hasPrefix("en") {
                    detail.linkSpeed = speedForInterfaceName(device)
                } else if device == "modem",
                          let modem = sysconfigValue("State:/Network/Service/\(serviceID)/Modem"),
                          modem["ConnectSpeed"] != nil {
                    let pppDict = sysconfigValue("State:/Network/Service/\(serviceID)/PPP")
                    if uint32Value(pppDict?["Status"]) == NetPPP.running,
                       let speed = doubleValue(pppDict?["ConnectSpeed"]) {
                        detail.linkSpeed = speed
                    }
                }
            }

            detailsList.append(detail)
        }

        cachedDetails = detailsList
        return detailsList
    }

    func primaryInterfaceName() -> String? {
        if let cachedPrimaryName { return cachedPrimaryName }
        guard let ipDict = sysconfigValue("State:/Network/Global/IPv4"),
              let name = ipDict["PrimaryInterface"] as? String else { return nil }
        cachedPrimaryName = name
        return name
    }

    func primaryServiceID() -> String? {
        if let cachedPrimaryService { return cachedPrimaryService }
        guard let ipDict = sysconfigValue("State:/Network/Global/IPv4"),
              let service = ipDict["PrimaryService"] as? String else { return nil }
        cachedPrimaryService = service
        return service
    }

    func interfaceNameForServiceID(_ serviceID: String?) -> String? {
        guard let serviceID else { return nil }
        if let cached = cachedServiceToName[serviceID] { return cached }

        let interfaceDict = sysconfigValue("Setup:/Network/Service/\(serviceID)/Interface")
        let pppDict = sysconfigValue("State:/Network/Service/\(serviceID)/PPP")
        if let pppName = pppDict?["InterfaceName"] as? String {
            cachedServiceToName[serviceID] = pppName
            return pppName
        }
        if let device = interfaceDict?["DeviceName"] as? String {
            cachedServiceToName[serviceID] = device
            return device
        }
        return nil
    }

    func serviceForInterfaceName(_ interfaceName: String) -> String? {
        if let cached = cachedNameToService[interfaceName] { return cached }
        guard let services = serviceOrder() else { return nil }

        for serviceID in services {
            let interfaceDict = sysconfigValue("Setup:/Network/Service/\(serviceID)/Interface")
            if interfaceDict?["DeviceName"] as? String == interfaceName {
                cachedNameToService[interfaceName] = serviceID
                return serviceID
            }
            let pppDict = sysconfigValue("State:/Network/Service/\(serviceID)/PPP")
            if pppDict?["InterfaceName"] as? String == interfaceName {
                cachedNameToService[interfaceName] = serviceID
                return serviceID
            }
        }
        return nil
    }

    func speedForServiceID(_ serviceID: String?) -> Double {
        guard let serviceID else { return -1 }
        if let cached = cachedServiceSpeed[serviceID] { return cached }

        let modemDict = sysconfigValue("State:/Network/Service/\(serviceID)/Modem")
        let pppDict = sysconfigValue("State:/Network/Service/\(serviceID)/PPP")
        if modemDict != nil {
            if let connectSpeed = doubleValue(modemDict?["ConnectSpeed"]),
               uint32Value(pppDict?["Status"]) == NetPPP.running {
                cachedServiceSpeed[serviceID] = connectSpeed
                return connectSpeed
            }
            return 56000
        }

        if let interfaceName = interfaceNameForServiceID(serviceID),
           interfaceName.hasPrefix("en") {
            let speed = speedForInterfaceName(interfaceName)
            cachedServiceSpeed[serviceID] = speed
            return speed
        }

        return -1
    }

    func underlyingInterfaceNameForServiceID(_ serviceID: String?) -> String? {
        guard let serviceID else { return nil }
        if let cached = cachedUnderlying[serviceID] { return cached }

        let interfaceDict = sysconfigValue("Setup:/Network/Service/\(serviceID)/Interface")
        let pppDict = sysconfigValue("State:/Network/Service/\(serviceID)/PPP")
        if let pppName = pppDict?["InterfaceName"] as? String {
            if let device = interfaceDict?["DeviceName"] as? String, device.hasPrefix("en") {
                cachedUnderlying[serviceID] = device
                return device
            }
            cachedUnderlying[serviceID] = pppName
            return pppName
        }
        if let device = interfaceDict?["DeviceName"] as? String {
            cachedUnderlying[serviceID] = device
            return device
        }
        return nil
    }

    func interfaceNameIsUp(_ interfaceName: String?) -> Bool {
        guard let interfaceName else { return false }
        if let cached = cachedInterfaceUp[interfaceName] { return cached }

        if interfaceName.hasPrefix("en") {
            let linkDict = sysconfigValue("State:/Network/Interface/\(interfaceName)/Link")
            if let active = boolValue(linkDict?["Active"]) {
                cachedInterfaceUp[interfaceName] = active
                return active
            }
        } else if interfaceName.hasPrefix("ppp") {
            let running = ppp.status(forInterfaceName: interfaceName)?.status == NetPPP.running
            cachedInterfaceUp[interfaceName] = running
            return running
        }

        // Interfaces without explicit link state are assumed active.
        return true
    }

    // MARK: - Link speed

    func speedForInterfaceName(_ interfaceName: String) -> Double {
        if sysconfigValue("Setup:/Network/Interface/\(interfaceName)/AirPort") != nil,
           let airportSpeed = speedForAirport() {
            return airportSpeed
        }
        if let ioKitSpeed = speedForInterfaceNameViaIOKit(interfaceName) {
            return ioKitSpeed
        }
        return speedForInterfaceNameViaIfConfig(interfaceName)
    }

    private func speedForAirport() -> Double? {
        let path = "/System/Library/PrivateFrameworks/Apple80211.framework/Versions/A/Resources/airport"
        guard let output = runCommand("\(path) -I | grep maxRate"),
              let colon = output.range(of: ":") else { return nil }
        let value = output[colon.upperBound...]
        return firstNumber(String(value)).map { $0 * 1_000_000 }
    }

    private func speedForInterfaceNameViaIOKit(_ interfaceName: String) -> Double? {
        guard masterPort != 0 else { return nil }
        var iterator: io_iterator_t = 0
        guard let matching = IOBSDNameMatching(masterPort, 0, interfaceName) else { return nil }
        IOServiceGetMatchingServices(masterPort, matching, &iterator)
        guard iterator != 0 else { return nil }
        defer { IOObjectRelease(iterator) }

        let entry = IOIteratorNext(iterator)
        guard entry != 0 else { return -1 }
        defer { IOObjectRelease(entry) }

        var controller: io_registry_entry_t = 0
        guard IORegistryEntryGetParentEntry(entry, kIOServicePlane, &controller) == KERN_SUCCESS,
              controller != 0 else { return -1 }
        defer { IOObjectRelease(controller) }

        guard let value = IORegistryEntryCreateCFProperty(controller, "IOLinkSpeed" as CFString,
                                                          kCFAllocatorDefault, 0)?
            .takeRetainedValue() as? NSNumber,
              value.uint64Value > 0 else { return nil }
        return value.doubleValue
    }

    private func speedForInterfaceNameViaIfConfig(_ interfaceName: String) -> Double {
        guard let output = runCommand("ifconfig -v \(interfaceName) | egrep 'link rate|uplink'") else {
            return 0
        }
        if output.contains("does not") { return 0 }

        let text: String
        if let separator = output.range(of: "/") {
            text = String(output[separator.upperBound...])
        } else if let separator = output.range(of: ": ") {
            text = String(output[separator.upperBound...])
        } else {
            return 0
        }

        let factors: [(String, Double)] = [("Gbps", 1_000_000_000),
                                           ("Mbps", 1_000_000),
                                           ("Kbps", 1_000),
                                           ("bps", 1)]
        for (unit, factor) in factors {
            if let range = text.range(of: unit) {
                let number = firstNumber(String(text[..<range.lowerBound])) ?? 0
                return number * factor
            }
        }
        return 0
    }

    // MARK: - Formatters

    private func runCommand(_ command: String) -> String? {
        let process = Process()
        process.executableURL = URL(fileURLWithPath: "/bin/sh")
        process.arguments = ["-c", command]
        let pipe = Pipe()
        process.standardOutput = pipe
        process.standardError = pipe
        do {
            try process.run()
        } catch {
            return nil
        }
        let data = pipe.fileHandleForReading.readDataToEndOfFile()
        process.waitUntilExit()
        return String(data: data, encoding: .utf8)
    }

    private func firstNumber(_ text: String) -> Double? {
        Scanner(string: text).scanDouble()
    }

    // MARK: - SystemConfiguration helpers

    private func sysconfigValue(_ key: String) -> [String: Any]? {
        guard let store else { return nil }
        return SCDynamicStoreCopyValue(store, key as CFString) as? [String: Any]
    }

    private func serviceOrder() -> [String]? {
        guard let dict = sysconfigValue("Setup:/Network/Global/IPv4") else { return nil }
        if let order = dict["ServiceOrder"] as? [String] { return order }
        let order = stringArray(dict["ServiceOrder"])
        return order.isEmpty ? nil : order
    }

    private func stringArray(_ value: Any?) -> [String] {
        guard let array = value as? [Any] else { return [] }
        return array.compactMap { $0 as? String }
    }

    private func boolValue(_ value: Any?) -> Bool? {
        if let number = value as? NSNumber { return number.boolValue }
        if let bool = value as? Bool { return bool }
        return nil
    }

    private func uint32Value(_ value: Any?) -> UInt32? {
        if let number = value as? NSNumber { return number.uint32Value }
        if let string = value as? String { return UInt32(string) }
        return nil
    }

    private func doubleValue(_ value: Any?) -> Double? {
        if let number = value as? NSNumber { return number.doubleValue }
        if let string = value as? String { return Double(string) }
        return nil
    }

    private func displayText(_ value: Any?) -> String? {
        guard let value else { return nil }
        if let string = value as? String { return string }
        if let number = value as? NSNumber { return number.stringValue }
        return String(describing: value)
    }

    func configChanged() {
        clearCaches()
        if let onChange {
            DispatchQueue.main.async { onChange() }
        }
    }

    func clearCaches() {
        cachedDetails = nil
        cachedPrimaryName = nil
        cachedPrimaryService = nil
        cachedServiceToName.removeAll()
        cachedNameToService.removeAll()
        cachedServiceSpeed.removeAll()
        cachedUnderlying.removeAll()
        cachedInterfaceUp.removeAll()
    }
}
