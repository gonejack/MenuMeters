//
//  AppDelegate.swift
//  MenuMeters
//
//  Application lifecycle: preferences, meters and the menu bar.
//

import Cocoa

final class AppDelegate: NSObject, NSApplicationDelegate {
    private static let welcomeFile = "Welcome"

    private var prefsWindow: PrefsWindowController?
    private var cpuExtra: CPUExtra?
    private var diskExtra: DiskExtra?
    private var netExtra: NetExtra?
    private var memExtra: MemExtra?

    // MARK: - NSApplicationDelegate

    func applicationWillFinishLaunching(_ notification: Notification) {
        // Touching the shared preferences performs the one-time migration from
        // the old com.ragingmenace.MenuMeters domain.
        _ = Prefs.shared
        buildMainMenu()
    }

    func applicationDidFinishLaunching(_ notification: Notification) {
        if isRunningOnReadOnlyVolume() {
            alertConcerningAppTranslocation()
        }

        killOlderInstances()

        prefsWindow = PrefsWindowController(aboutFile: Self.welcomeFile)

        let key = Self.welcomeFile + "Presented"
        if !UserDefaults.standard.bool(forKey: key) {
            prefsWindow?.openAbout(nil)
            UserDefaults.standard.set(true, forKey: key)
        }

        // Meters are created last: a failure while probing hardware must not
        // prevent the preferences from working.
        cpuExtra = CPUExtra(bundleID: MM.cpuBundleID)
        diskExtra = DiskExtra(bundleID: MM.diskBundleID)
        netExtra = NetExtra(bundleID: MM.netBundleID)
        memExtra = MemExtra(bundleID: MM.memBundleID)

        if !LoginItem.isEnabled() {
            LoginItem.setEnabled(true)
        }
    }

    func applicationSupportsSecureRestorableState(_ app: NSApplication) -> Bool {
        true
    }

    func applicationShouldHandleReopen(_ sender: NSApplication,
                                      hasVisibleWindows flag: Bool) -> Bool {
        prefsWindow?.showPreferences()
        return true
    }

    // MARK: - Main menu

    private func buildMainMenu() {
        let mainMenu = NSMenu()

        let appMenuItem = NSMenuItem()
        mainMenu.addItem(appMenuItem)
        let appMenu = NSMenu()
        appMenuItem.submenu = appMenu

        let about = NSMenuItem(title: "About MenuMeters",
                               action: #selector(showAbout(_:)), keyEquivalent: "")
        about.target = self
        appMenu.addItem(about)

        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Hide MenuMeters", action: #selector(NSApplication.hide(_:)),
                        keyEquivalent: "h")
        appMenu.addItem(withTitle: "Hide Others", action: #selector(NSApplication.hideOtherApplications(_:)),
                        keyEquivalent: "h").keyEquivalentModifierMask = [.command, .option]
        appMenu.addItem(withTitle: "Show All", action: #selector(NSApplication.unhideAllApplications(_:)),
                        keyEquivalent: "")
        appMenu.addItem(.separator())
        appMenu.addItem(withTitle: "Quit MenuMeters", action: #selector(NSApplication.terminate(_:)),
                        keyEquivalent: "q")

        let windowMenuItem = NSMenuItem()
        mainMenu.addItem(windowMenuItem)
        let windowMenu = NSMenu(title: "Window")
        windowMenuItem.submenu = windowMenu
        windowMenu.addItem(withTitle: "Minimize", action: #selector(NSWindow.performMiniaturize(_:)),
                           keyEquivalent: "m")
        windowMenu.addItem(withTitle: "Close", action: #selector(NSWindow.performClose(_:)),
                           keyEquivalent: "w")
        NSApp.windowsMenu = windowMenu

        NSApp.mainMenu = mainMenu
    }

    @objc private func showAbout(_ sender: Any?) {
        prefsWindow?.openAbout(sender)
    }

    // MARK: - Single instance and translocation

    private func killOlderInstances() {
        let thisVersion = Bundle.main.infoDictionary?["CFBundleVersion"] as? String ?? "0"
        let thisProcess = ProcessInfo.processInfo.processIdentifier
        for app in NSRunningApplication.runningApplications(withBundleIdentifier: MM.appBundleID) {
            guard app.processIdentifier != thisProcess else { continue }
            let version = app.bundleURL
                .flatMap { Bundle(url: $0) }?
                .infoDictionary?["CFBundleVersion"] as? String ?? "0"
            let result = Version.compare(version, thisVersion)
            NSLog("MenuMeters: running version \(version), ours \(thisVersion)")
            if result != .orderedDescending {
                NSLog("MenuMeters: terminating older instance \(version)")
                app.terminate()
            }
        }
    }

    private func isRunningOnReadOnlyVolume() -> Bool {
        var info = statfs()
        let path = FileManager.default.fileSystemRepresentation(withPath: Bundle.main.bundleURL.path)
        guard statfs(path, &info) == 0 else {
            // If the volume cannot be inspected, assume the app is translocated.
            return true
        }
        return (info.f_flags & UInt32(MNT_RDONLY)) != 0
    }

    private func alertConcerningAppTranslocation() {
        let alert = NSAlert()
        alert.messageText = "Please move the app after downloading it"
        alert.addButton(withTitle: "OK, I quit the app and move it")
        alert.informativeText = """
            Please move the app to, say, /Applications, using your mouse/trackpad, not from the command line.

            macOS runs downloaded apps from a temporary location, which prevents MenuMeters from registering itself as a login item.

            I am sorry for the inconvenience.
            """
        alert.runModal()
        NSApp.terminate(nil)
    }
}
