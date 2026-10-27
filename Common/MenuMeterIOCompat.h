//
//  MenuMeterIOCompat.h
//
//  Small shims for IOKit API renames introduced in macOS 12, so the app can
//  keep a macOS 11 deployment target while building against current SDKs.
//
//  This file is part of MenuMeters.
//

#ifndef MenuMeterIOCompat_h
#define MenuMeterIOCompat_h

#import <IOKit/IOKitLib.h>

// IOMasterPort() and kIOMasterPortDefault were renamed to IOMainPort() and
// kIOMainPortDefault in macOS 12. The old names still exist, but are
// deprecated; selecting at runtime keeps macOS 11 support.
static inline kern_return_t MenuMetersIOMainPort(mach_port_t *mainPort) {
    if (@available(macOS 12.0, *)) {
        return IOMainPort(MACH_PORT_NULL, mainPort);
    }
    return IOMasterPort(MACH_PORT_NULL, mainPort);
}

static inline mach_port_t MenuMetersIODefaultPort(void) {
    if (@available(macOS 12.0, *)) {
        return kIOMainPortDefault;
    }
    return kIOMasterPortDefault;
}

#endif /* MenuMeterIOCompat_h */
