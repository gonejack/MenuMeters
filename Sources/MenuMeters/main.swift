//
//  main.swift
//  MenuMeters
//

import Cocoa

// Developer utility: remove this build from the login items without launching
// the UI (useful when testing a build from out/).
if CommandLine.arguments.contains("--unregister-login-item") {
    LoginItem.setEnabled(false)
    exit(0)
}

let application = NSApplication.shared
let delegate = AppDelegate()
application.delegate = delegate
application.setActivationPolicy(.accessory)
application.run()
