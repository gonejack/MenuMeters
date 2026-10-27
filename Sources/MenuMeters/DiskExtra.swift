//
//  DiskExtra.swift
//  MenuMeters
//
//  Disk activity menu bar meter.
//

import Cocoa

final class DiskExtra: MenuExtraBase {
    private let diskIO = DiskIO()
    private let diskSpace = DiskSpace()
    private var extraMenu = NSMenu()
    private var images: [Bool: [DiskActivity: NSImage]] = [:]
    private var displayedActivity: DiskActivity = .idle
    private var fgMenuThemeColor: NSColor = .labelColor
    private var blankImage = NSImage(size: NSSize(width: Disk.viewWidth, height: 22))

    override init(bundleID: String) {
        super.init(bundleID: bundleID)
        extraMenu = NSMenu(title: "")
        extraMenu.autoenablesItems = false
        configFromPrefs(nil)
    }

    // MARK: - Status item

    override func makeImage() -> NSImage {
        images[isDark()]?[displayedActivity] ?? blankImage
    }

    override func setupColor() {
        fgMenuThemeColor = menuBarTextColor()
        statusItem?.button?.image = makeImage()
    }

    // MARK: - Preferences

    override func configFromPrefs(_ notification: Notification?) {
        configDisplay(interval: Prefs.shared.diskInterval)
        diskSpace.useBaseTen = !Prefs.shared.diskSpaceForceBaseTwo
        fgMenuThemeColor = menuBarTextColor()
        buildImages()
        statusItem?.button?.image = makeImage()
    }

    private func buildImages() {
        let prefs = Prefs.shared
        let imageSet = prefs.diskImageset
        let menuHeight = height()
        let bootIcon = NSWorkspace.shared.icon(forFile: "/")
        bootIcon.size = NSSize(width: Disk.viewWidth, height: Disk.viewWidth)
        let drawBoot = {
            bootIcon.draw(at: NSPoint(x: 0, y: (menuHeight - Disk.viewWidth) / 2),
                          from: .zero, operation: .sourceOver, fraction: 1)
        }

        for dark in [false, true] {
            let prefix = (dark ? Disk.darkImageSets : Disk.imageSets)[imageSet]
            var set: [DiskActivity: NSImage] = [:]

            switch imageSet {
            case Disk.arrowsImageSet:
                set[.idle] = compose(size: NSSize(width: Disk.viewWidth, height: menuHeight)) {
                    bootIcon.draw(at: NSPoint(x: 0, y: (menuHeight - Disk.viewWidth) / 2),
                                  from: .zero, operation: .sourceOver, fraction: 1)
                }
                for (activity, suffix) in [(DiskActivity.read, "Read"),
                                           (.write, "Write"), (.readWrite, "ReadWrite")] {
                    guard let overlay = NSImage(named: prefix + suffix) else { continue }
                    set[activity] = compose(size: NSSize(width: Disk.viewWidth, height: menuHeight)) {
                        bootIcon.draw(at: NSPoint(x: 0, y: (menuHeight - Disk.viewWidth) / 2),
                                      from: .zero, operation: .sourceOver, fraction: 1)
                        overlay.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
                    }
                }
            case Disk.arrowsLargeImageSet:
                let readPath = arrowPath(up: true, height: menuHeight)
                let writePath = arrowPath(up: false, height: menuHeight)
                set[.idle] = compose(size: NSSize(width: Disk.viewWidth, height: menuHeight)) {
                    drawBoot()
                }
                set[.read] = compose(size: NSSize(width: Disk.viewWidth, height: menuHeight)) {
                    drawBoot()
                    NSColor.green.setFill()
                    readPath.fill()
                }
                set[.write] = compose(size: NSSize(width: Disk.viewWidth, height: menuHeight)) {
                    drawBoot()
                    NSColor.red.setFill()
                    writePath.fill()
                }
                set[.readWrite] = compose(size: NSSize(width: Disk.viewWidth, height: menuHeight)) {
                    drawBoot()
                    NSColor.green.setFill()
                    readPath.fill()
                    NSColor.red.setFill()
                    writePath.fill()
                }
            default:
                for (activity, suffix) in [(DiskActivity.idle, "Idle"), (.read, "Read"),
                                           (.write, "Write"), (.readWrite, "ReadWrite")] {
                    if let image = NSImage(named: prefix + suffix) { set[activity] = image }
                }
            }
            images[dark] = set
        }
        blankImage = NSImage(size: NSSize(width: Disk.viewWidth, height: menuHeight))
    }

    private func arrowPath(up: Bool, height: CGFloat) -> NSBezierPath {
        let path = NSBezierPath()
        let middle = height / 2
        path.move(to: NSPoint(x: 0, y: middle + (up ? 1 : -1)))
        path.line(to: NSPoint(x: Disk.viewWidth, y: middle + (up ? 1 : -1)))
        path.line(to: NSPoint(x: Disk.viewWidth / 2, y: middle + (up ? 9 : -9)))
        path.close()
        return path
    }

    private func compose(size: NSSize, drawing: @escaping () -> Void) -> NSImage {
        NSImage(size: size, flipped: false) { _ in
            drawing()
            return true
        }
    }

    // MARK: - Menu

    override func menu() -> NSMenu {
        extraMenu.removeAllItems()
        let volumes = diskSpace.diskSpaceData()
        guard !volumes.isEmpty else { return extraMenu }
        let itemImages = diskSpaceMenuItemImages(volumes)
        guard itemImages.count == volumes.count else { return extraMenu }

        for (index, volume) in volumes.enumerated() {
            let item = extraMenu.addItem(withTitle: "", action: #selector(openOrEjectVolume(_:)),
                                         keyEquivalent: "")
            item.image = itemImages[index]
            item.representedObject = volume.path
            item.target = self
        }
        extraMenu.addItem(.separator())
        addStandardMenuEntries(to: extraMenu)
        return extraMenu
    }

    private func diskSpaceMenuItemImages(_ volumes: [DiskSpaceInfo]) -> [NSImage] {
        let attributes: [NSAttributedString.Key: Any] = [
            .foregroundColor: fgMenuThemeColor,
            .font: NSFont.monospacedDigitSystemFont(ofSize: 11, weight: .regular)
        ]

        var nameStrings: [NSAttributedString] = []
        var detailStrings: [NSAttributedString] = []
        var freeStrings: [NSAttributedString] = []
        var usedStrings: [NSAttributedString] = []
        var totalStrings: [NSAttributedString] = []
        var widestName: CGFloat = 0
        var widestDetail: CGFloat = 0
        var widestFree: CGFloat = 0
        var widestUsed: CGFloat = 0
        var widestTotal: CGFloat = 0

        for volume in volumes {
            let name = NSAttributedString(string: volume.name, attributes: attributes)
            let detail = NSAttributedString(string: "(\(volume.device), \(volume.fileSystem))",
                                            attributes: attributes)
            let free = NSAttributedString(string: volume.free, attributes: attributes)
            let used = NSAttributedString(string: volume.used, attributes: attributes)
            let total = NSAttributedString(string: volume.total, attributes: attributes)

            nameStrings.append(name)
            detailStrings.append(detail)
            freeStrings.append(free)
            usedStrings.append(used)
            totalStrings.append(total)

            widestName = max(widestName, name.size().width)
            widestDetail = max(widestDetail, detail.size().width)
            widestFree = max(widestFree, free.size().width)
            widestUsed = max(widestUsed, used.size().width)
            widestTotal = max(widestTotal, total.size().width)
        }

        widestName = ceil(widestName)
        widestDetail = ceil(widestDetail)
        widestFree = ceil(widestFree)
        widestUsed = ceil(widestUsed)
        widestTotal = ceil(widestTotal)

        var textWidth = widestName + widestDetail + 25
        textWidth = max(textWidth, widestFree + widestUsed + widestTotal + 30)

        var images: [NSImage] = []
        for index in volumes.indices {
            let icon = volumes[index].icon ?? NSImage(size: NSSize(width: 32, height: 32))
            let iconWidth = ceil(icon.size.width)
            let iconHeight = ceil(icon.size.height)
            let image = compose(size: NSSize(width: icon.size.width + 10 + textWidth,
                                             height: icon.size.height)) {
                icon.draw(at: .zero, from: .zero, operation: .sourceOver, fraction: 1)
                nameStrings[index].draw(at: NSPoint(x: iconWidth + 10, y: ceil(iconHeight / 2)))
                detailStrings[index].draw(at: NSPoint(x: iconWidth + 10 + widestName + 15,
                                                      y: ceil(iconHeight / 2)))
                usedStrings[index].draw(at: NSPoint(x: iconWidth + 10, y: 1))
                freeStrings[index].draw(at: NSPoint(x: iconWidth + 10 + widestUsed + 10, y: 1))
                totalStrings[index].draw(at: NSPoint(
                    x: iconWidth + 10 + widestUsed + 10 + widestFree + 10, y: 1))
            }
            images.append(image)
        }
        return images
    }

    // MARK: - Timer

    override func timerFired(_ timer: Timer) {
        if let activity = diskIO?.diskIOActivity() {
            displayedActivity = activity
        }
        super.timerFired(timer)
    }

    // MARK: - Volume actions

    @objc private func openOrEjectVolume(_ sender: NSMenuItem) {
        guard let path = sender.representedObject as? String else { return }
        var eject = Prefs.shared.diskSelectMode == 1
        if NSEvent.modifierFlags.contains(.option) { eject.toggle() }

        let url = URL(fileURLWithPath: path, isDirectory: true)
        guard eject else {
            if !NSWorkspace.shared.open(url) {
                NSLog("MenuMeterDisk unable to open \"%@\".", path)
            }
            return
        }

        let removable = (try? url.resourceValues(forKeys: [.volumeIsRemovableKey]))?
            .volumeIsRemovable ?? false
        let task = Process()
        task.executableURL = URL(fileURLWithPath: "/usr/sbin/diskutil")
        task.arguments = [removable ? "eject" : "unmount", path]
        do {
            try task.run()
            task.waitUntilExit()
        } catch {
            NSLog("MenuMeterDisk unable to eject/unmount \"%@\" using diskutil: %@",
                  path, error.localizedDescription)
        }
    }
}
