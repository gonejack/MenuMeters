# MenuMeters

MenuMeters is a set of CPU, memory, disk, and network meters for the macOS menu
bar. This is the maintained fork that runs as a regular menu-bar app (originally
by Yuji Tachikawa, based on the classic MenuMeters by Alex Harper).

## Requirements

- macOS 11 Big Sur or later (Apple Silicon and Intel)
- Xcode 16 or later, **or** the Command Line Tools
- A full Xcode installation is only needed for Interface Builder / nib editing

The app is built as a universal binary (`arm64` + `x86_64`) and uses ARC,
modern Objective-C, and current AppKit/IOKit APIs.

## Build

### Xcode

1. Open `MenuMeters.xcodeproj`.
2. Select the `MenuMeters` scheme and the `My Mac` destination.
3. Build and run.

`Sparkle.framework` is bundled in the repository, so no package download is
required. For a signed/notarized release, sign the app with your Developer ID
and let Sparkle sign its updates with the matching key.

### Command Line Tools only

```sh
./build-clt.sh
```

This produces `out/MenuMeters`, a universal binary. To update an existing app
bundle:

```sh
cp out/MenuMeters /Applications/MenuMeters.app/Contents/MacOS/MenuMeters
codesign -f -s - --options runtime \
         --entitlements MenuMeters.entitlements --deep \
         /Applications/MenuMeters.app
```

The ad-hoc signing instructions include
`com.apple.security.cs.disable-library-validation` because the linked
`Sparkle.framework` is not signed with the same identity. When using a real
Developer ID, sign the framework and the app with that identity instead.

### Tests and verification

There is no automated test suite. The build script is the reference build and
exercises every source file with the current SDK. GitHub Actions runs both the
Command Line Tools build and the Xcode project build on every push and pull
request.

## Project layout

| Path | Contents |
| --- | --- |
| `MenuMetersApp/` | `main.m`, app delegate, main menu nib |
| `Common/` | Preferences, shared helpers, IOKit/workspace compatibility shims |
| `MenuExtras/MenuMeterCPU/` | CPU meter, temperature, top-process list |
| `MenuExtras/MenuMeterDisk/` | Disk I/O and free-space meters |
| `MenuExtras/MenuMeterMem/` | Memory meter |
| `MenuExtras/MenuMeterNet/` | Network meter and PPP support |
| `PrefPane/` | Preferences window, login-item handling |
| `hardware_reader/` | AppleSMC / Apple Silicon temperature readers |
| `build-clt.sh` | Universal build without Xcode |

## Modernization notes

The codebase was originally written for Mac OS X 10.2–10.4. It has been kept
running through successive macOS releases; see
[`Docs/Modernization.md`](Docs/Modernization.md) for the current state, the
compatibility shims, and known follow-up work (most notably the legacy Sparkle
1.x updater and the AppleScript-based Activity Monitor pane switching).

## Other versions and related software

If you run a sufficiently new macOS, also consider these actively maintained
menu-bar monitors:

- <https://github.com/exelban/stats>
- <https://iglance.github.io>
- <https://github.com/gao-sun/eul>

Other forks of MenuMeters:

- <https://github.com/emcrisostomo/MenuMeters> (DMG installers)
- <https://gitlab.com/axet/MenuMeters> (CPU-meter features)

## Background

MenuMeters was originally developed at
<http://www.ragingmenace.com/software/menumeters/>. The original version stopped
working on El Capitan and later because SystemUIServer no longer loads
third-party menu extras. This fork runs as a faceless app that uses
`NSStatusItem` instead of `NSMenuExtra`. Since Catalina it is an independent
app rather than a System Preferences pane.
