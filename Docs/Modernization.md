# Modernization notes

MenuMeters dates back to the Mac OS X 10.2 era. The current version is a Swift
rewrite of the maintained fork: the user-facing meters and preferences are
preserved, while the old Objective-C menu-extra architecture and its
compatibility shims are gone.

## Architecture

MenuMeters is now a single Swift application. It has no nib, no Objective-C
sources, and no preference pane.

| File | Responsibility |
| --- | --- |
| `main.swift` | Creates `NSApplication`, installs the app delegate, and runs the accessory app |
| `AppDelegate.swift` | Startup, single-instance handling, meter creation, main menu |
| `MenuExtraBase.swift` | Shared `NSStatusItem` lifecycle, timers, menu plumbing, theme changes, Activity Monitor switching |
| `CPUExtra.swift`, `CPUStats.swift`, `CPUTopProcesses.swift`, `Uptime.swift` | CPU meter, graphs, top processes, load and uptime |
| `DiskExtra.swift`, `DiskIO.swift`, `DiskSpace.swift` | Disk activity and volume-space meters |
| `MemExtra.swift`, `MemStats.swift` | Memory meter, pressure, paging, and swap information |
| `NetExtra.swift`, `NetConfig.swift`, `NetStats.swift`, `NetPPP.swift` | Network throughput, interfaces, and PPP/VPN support |
| `PrefsWindow.swift` | Programmatic five-tab preferences and About window |
| `Defaults.swift` | Typed preferences, validation, and legacy migration |
| `Support.swift` | Constants, localization, notifications, login item, app launching, version comparison |
| `TemperatureReader.swift` | SMC / Apple Silicon temperature access |
| `PowerMate.swift` | Griffin PowerMate support |

Each meter owns one `NSStatusItem` and is created independently. A failure in
one meter does not prevent the preferences window from starting.
The application is an `LSUIElement` accessory app and temporarily switches to a
regular activation policy while the preferences window is open.

The public notification names from the old implementation are retained:
`openPref`, `menuExtraUnloaded`, and `hiddenBySystem`. Meter preference-change
notifications still use the meter bundle identifier as the notification name
and `"prefChange"` as the object.

## Preferences and compatibility

Preferences use `UserDefaults.standard` under the app's bundle identifier,
`com.yujitach.MenuMeters`. On first launch the app imports values from the old
`com.ragingmenace.MenuMeters` domain when that plist exists. Values equal to the
bundled defaults are skipped, and a migration marker prevents the import from
running again.

The historical meter identifiers are unchanged:

- `com.ragingmenace.MenuMeterCPU`
- `com.ragingmenace.MenuMeterDisk`
- `com.ragingmenace.MenuMeterMem`
- `com.ragingmenace.MenuMeterNet`

This keeps existing preference values working. Colors written by 2.1.6 and
earlier use legacy `NSArchiver` data, which the current app does not decode;
those colors fall back to the defaults while the other preferences are
imported. New colors use secure keyed archives. Downgrading to 2.1.6 or earlier
will show default colors for colors saved by this version.

## API modernization

| Old implementation | Current implementation |
| --- | --- |
| Private `NSMenuExtra` / SystemUIServer menu extras | Public `NSStatusItem` in a standalone accessory app |
| Objective-C app delegate and nib | Swift `NSApplicationDelegate`, programmatic AppKit |
| `NSOnState` / `NSOffState` | `NSControl.StateValue.on` / `.off` |
| `NSArchiver` / `NSUnarchiver` colors | `NSKeyedArchiver` / `NSKeyedUnarchiver` |
| `NSBeginAlertSheet` | `NSAlert` |
| `FSRef` / `FSGetVolumeInfo` | `URL` resource values |
| `IOMasterPort()` | `IOMainPort()` / `kIOMainPortDefault` |
| `NXGetLocalArchInfo()` | `sysctlbyname("hw.machine")` |
| `NSColor.ignoresAlpha` | `NSColorWell.supportsAlpha` |
| `String(cString:)` from raw buffers | Bounded UTF-8 conversion |
| `/usr/bin/top` subprocess | `libproc` process snapshots |
| AppleScript / System Events automation | `AXUIElement` accessibility traversal, best effort |
| `LSSharedFileList` | `SMAppService.mainApp` |
| Fixed `NSTimer` selectors | Block-based timers with weak captures and tolerance |

Timers keep the user-selected interval and use tolerance so the system can
coalesce wake-ups. Disk, CPU, memory, and network formatters are created once
and configured with properties instead of being round-tripped through an
archiver. CPU and package counts are cached file-private values with guards
against zero.

## Resources and build layout

All app resources live in `Resources/`:

- `Resources/*.lproj/` contains `Localizable.strings`,
  `MenuMetersPref.strings`, and `DiskImageSet.strings`.
- `Resources/DiskIcons/` contains the TIFF icon sets.
- `Resources/MenuMeters.icns` is the app icon.
- `Resources/Welcome.rtf` is shown in the About tab.
- `Resources/com.ragingmenace.MenuMeters.plist` provides the bundled defaults
  used during migration.
- `Resources/releases.html` is the release-history page.

Both build paths copy the disk TIFFs and localized tables to the top level of
`Contents/Resources`, which is where `NSImage(named:)` and
`Bundle.localizedString(forKey:value:table:)` expect them.

`build-clt.sh` is the reference build. It compiles every Swift source for
`arm64` and `x86_64`, copies the resources, and ad-hoc signs the resulting
`out/MenuMeters.app`. The app has no bundled third-party frameworks.

The Xcode project contains the same sources and resources and uses resource
variant groups for the localized string tables. The shared `MenuMeters` scheme
builds the app; CI runs both the Xcode and Command Line Tools builds.

## Deployment and signing

- Minimum deployment target: **macOS 26.0**.
- Architectures: `arm64` and `x86_64`.
- Swift language mode: Swift 5.
- Local builds use ad-hoc signing. Release builds should use a Developer ID
  identity and be notarized.
- This fork has no automatic updater; it does not check for or download
  updates.

## Known limitations and follow-up work

- There is no automated test suite. `./build-clt.sh` compiles every source file
  for both architectures and the CI workflow builds the Xcode project as well.
- Activity Monitor's toolbar is not public API. The accessibility traversal
  used for pane switching is intentionally best effort and may need adjustment
  after major Activity Monitor redesigns. It requires Accessibility permission.
- Colors archived by MenuMeters 2.1.6 and earlier are not decoded and fall
  back to the defaults. Login items registered by the old preference-pane
  version are also not removed automatically; use System Settings to delete
  stale entries.
- The preference window uses fixed frames inherited from the old nib. A future
  layout pass could make it resize more gracefully.

## Verification

```sh
./build-clt.sh
lipo -info out/MenuMeters.app/Contents/MacOS/MenuMeters
codesign --verify --deep --strict out/MenuMeters.app
```

The Xcode build can be run with a full Xcode installation:

```sh
xcodebuild \
  -project MenuMeters.xcodeproj \
  -scheme MenuMeters \
  -configuration Release \
  -destination "platform=macOS" \
  CODE_SIGNING_ALLOWED=NO \
  build
```
