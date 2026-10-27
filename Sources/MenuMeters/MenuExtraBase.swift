//
//  MenuExtraBase.swift
//  MenuMeters
//
//  Common NSStatusItem lifecycle, theme handling, menu plumbing and
//  Activity Monitor integration.
//

import Cocoa
import ApplicationServices

class MenuExtraBase: NSObject, NSMenuDelegate {
    let bundleID: String
    private(set) var statusItem: NSStatusItem?
    private var updateTimer: Timer?
    private var observingStatusItem = false
    private var observingButton = false
    var menuWidth: CGFloat = 0
    private(set) var isMenuVisible = false

    init(bundleID: String) {
        self.bundleID = bundleID
        super.init()
        Prefs.shared.defaults.addObserver(self, forKeyPath: "tintPercentage", options: [.new], context: nil)
        NotificationCenter.default.addObserver(self, selector: #selector(configFromPrefs(_:)),
                                               name: Notification.Name(bundleID), object: MM.prefChange)
    }

    deinit {
        updateTimer?.invalidate()
        if let item = statusItem {
            if observingStatusItem { item.removeObserver(self, forKeyPath: "visible") }
            if observingButton { item.button?.removeObserver(self, forKeyPath: "effectiveAppearance") }
        }
        Prefs.shared.defaults.removeObserver(self, forKeyPath: "tintPercentage")
        NotificationCenter.default.removeObserver(self)
    }

    // MARK: - Subclass hooks

    func menu() -> NSMenu { NSMenu() }
    func renderImage() -> Bool { false }
    @objc func configFromPrefs(_ notification: Notification?) {}
    func setupColor() {}

    func imageHeight() -> CGFloat { height() - 1 }
    func height() -> CGFloat {
        let value = statusItem?.button?.frame.height ?? 0
        return value < 10 ? 22 : value
    }

    func isDark() -> Bool {
        guard let appearance = statusItem?.button?.effectiveAppearance else {
            return NSApp.effectiveAppearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
        }
        return appearance.bestMatch(from: [.aqua, .darkAqua]) == .darkAqua
    }

    func menuBarTextColor() -> NSColor {
        .labelColor
    }

    func colorByAdjustingForLightDark(_ color: NSColor) -> NSColor {
        color.blended(withFraction: Prefs.shared.tintPercentage / 100,
                      of: (isDark() ? NSColor.white : NSColor.black).withAlphaComponent(color.alphaComponent)) ?? color
    }

    var baselineOffset: CGFloat { 1 }

    func makeImage() -> NSImage {
        let size = NSSize(width: menuWidth, height: imageHeight())
        let appearance = statusItem?.button?.effectiveAppearance ?? NSApp.effectiveAppearance
        return NSImage(size: size, flipped: false) { [weak self] _ in
            guard let self else { return false }
            var rendered = false
            appearance.performAsCurrentDrawingAppearance {
                rendered = self.renderImage()
            }
            return rendered
        }
    }

    func timerFired(_ timer: Timer) {
        statusItem?.button?.image = makeImage()
        if isInstalledButHiddenBySystem {
            NotificationCenter.default.post(name: .hiddenBySystem, object: nil)
        }
    }

    /// Creates or removes the status item according to the meter enablement pref.
    func configDisplay(interval: TimeInterval) {
        if Prefs.shared.meterEnabled(bundleID) {
            if statusItem == nil {
                let item = NSStatusBar.system.statusItem(withLength: NSStatusItem.variableLength)
                item.autosaveName = bundleID
                item.behavior = .removalAllowed
                item.addObserver(self, forKeyPath: "visible", options: [.new], context: nil)
                observingStatusItem = true
                item.button?.addObserver(self, forKeyPath: "effectiveAppearance",
                                         options: [.new, .old], context: nil)
                observingButton = true
                statusItem = item
            }
            if let item = statusItem {
                let newMenu = menu()
                newMenu.delegate = self
                item.menu = newMenu
            }
            updateTimer?.invalidate()
            let timer = Timer(timeInterval: interval, repeats: true) { [weak self] timer in
                self?.timerFired(timer)
            }
            timer.tolerance = interval * 0.2
            RunLoop.current.add(timer, forMode: .common)
            updateTimer = timer
            statusItem?.button?.image = makeImage()
        } else if statusItem != nil {
            removeStatusItem()
        }
    }

    func removeStatusItem() {
        updateTimer?.invalidate()
        updateTimer = nil
        if let item = statusItem {
            if observingStatusItem { item.removeObserver(self, forKeyPath: "visible") }
            observingStatusItem = false
            if observingButton { item.button?.removeObserver(self, forKeyPath: "effectiveAppearance") }
            observingButton = false
            NSStatusBar.system.removeStatusItem(item)
        }
        statusItem = nil
        NotificationCenter.default.post(name: .menuExtraUnloaded, object: bundleID)
    }

    override func observeValue(forKeyPath keyPath: String?, of object: Any?,
                               change: [NSKeyValueChangeKey: Any]?, context: UnsafeMutableRawPointer?) {
        if keyPath == "effectiveAppearance", let change {
            let old = (change[.oldKey] as? NSAppearance)?.name
            let new = (change[.newKey] as? NSAppearance)?.name
            if old != new { setupColor() }
        } else if keyPath == "visible", let item = statusItem, !item.isVisible {
            removeStatusItem()
        } else if keyPath == "tintPercentage" {
            setupColor()
        }
    }

    // MARK: - Menu extras

    func addStandardMenuEntries(to menu: NSMenu) {
        let activity = menu.addItem(withTitle: L(MM.openActivityMonitorTitle),
                                    action: #selector(openActivityMonitor(_:)), keyEquivalent: "")
        activity.target = self
        let prefs = menu.addItem(withTitle: L(MM.openPrefsTitle),
                                 action: #selector(openMenuMetersPref(_:)), keyEquivalent: "")
        prefs.target = self
    }

    @objc func openMenuMetersPref(_ sender: Any?) {
        NotificationCenter.default.post(name: .openPref, object: self)
    }

    @objc func openActivityMonitor(_ sender: Any?) {
        AppLauncher.open(bundleID: "com.apple.ActivityMonitor",
                         path: "/System/Applications/Utilities/Activity Monitor.app",
                         name: "Activity Monitor")
        guard Prefs.shared.activityMonitorSpecificPanes else { return }
        if !AXIsProcessTrusted() {
            AXIsProcessTrustedWithOptions([kAXTrustedCheckOptionPrompt.takeUnretainedValue() as String: true] as CFDictionary)
        }

        let tab: Int
        switch bundleID {
        case MM.diskBundleID: tab = MM.diskPane
        case MM.memBundleID: tab = MM.memPane
        case MM.netBundleID: tab = MM.netPane
        default: tab = MM.cpuPane
        }
        selectActivityMonitorTab(tab, attempt: 0)
    }

    private func selectActivityMonitorTab(_ tab: Int, attempt: Int) {
        guard attempt <= 12 else { return }
        guard let app = NSRunningApplication.runningApplications(withBundleIdentifier: "com.apple.ActivityMonitor").first else {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
                self?.selectActivityMonitorTab(tab, attempt: attempt + 1)
            }
            return
        }
        let axApp = AXUIElementCreateApplication(app.processIdentifier)
        AXUIElementSetMessagingTimeout(axApp, 1.0)
        if pressActivityMonitorTab(axApp, tab: tab) { return }
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.4) { [weak self] in
            self?.selectActivityMonitorTab(tab, attempt: attempt + 1)
        }
    }

    private func axRole(_ element: AXUIElement) -> String? {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXRoleAttribute as CFString, &value) == .success else { return nil }
        return value as? String
    }

    private func axChildren(_ element: AXUIElement) -> [AXUIElement] {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(element, kAXChildrenAttribute as CFString, &value) == .success,
              let array = value as? [AXUIElement] else { return [] }
        return array
    }

    private func collectRadioButtons(_ element: AXUIElement, depth: Int = 0,
                                     into buttons: inout [AXUIElement]) -> Bool {
        guard depth <= 12 else { return false }
        if axRole(element) == (kAXRadioGroupRole as String) {
            let group = axChildren(element).filter { axRole($0) == (kAXRadioButtonRole as String) }
            if !group.isEmpty {
                buttons.append(contentsOf: group)
                return true
            }
        }
        for child in axChildren(element) {
            if collectRadioButtons(child, depth: depth + 1, into: &buttons) { return true }
        }
        return false
    }

    private func pressActivityMonitorTab(_ app: AXUIElement, tab: Int) -> Bool {
        var value: CFTypeRef?
        guard AXUIElementCopyAttributeValue(app, kAXWindowsAttribute as CFString, &value) == .success,
              let windows = value as? [AXUIElement], let window = windows.first else { return false }
        var buttons: [AXUIElement] = []
        guard collectRadioButtons(window, into: &buttons), !buttons.isEmpty else { return false }
        let index = tab > 0 ? tab - 1 : buttons.count + tab
        guard index >= 0, index < buttons.count else { return false }
        return AXUIElementPerformAction(buttons[index], kAXPressAction as CFString) == .success
    }

    var isInstalledButHiddenBySystem: Bool {
        guard let window = statusItem?.button?.window else { return false }
        guard window.frame.width > 0, window.frame.height > 0 else { return false }
        return !window.occlusionState.contains(.visible)
    }

    // MARK: - NSMenuDelegate

    func menuNeedsUpdate(_ menu: NSMenu) {
        if let item = statusItem {
            let newMenu = self.menu()
            newMenu.delegate = self
            item.menu = newMenu
        }
    }

    func menuWillOpen(_ menu: NSMenu) {
        isMenuVisible = true
    }

    func menuDidClose(_ menu: NSMenu) {
        isMenuVisible = false
    }
}
