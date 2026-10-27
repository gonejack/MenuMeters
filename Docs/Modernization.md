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
| `AppDelegate.swift` | Startup, single-instance handling, update controller, meter creation, main menu |
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
one meter does not prevent the updater or the preferences window from starting.
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

This keeps existing preferences and login-item entries working. Colors written
by the old version are read with a keyed-archive first and the legacy
`NSUnarchiver` path as a fallback. New colors use secure keyed archives.
Downgrading to 2.1.6 or earlier will show default colors for colors saved by
this version.

## API modernization

| Old implementation | Current implementation |
| --- | --- |
| Private `NSMenuExtra` / SystemUIServer menu extras | Public `NSStatusItem` in a standalone accessory app |
| Objective-C app delegate and nib | Swift `NSApplicationDelegate`, programmatic AppKit |
| `NSOnState` / `NSOffState` | `NSControl.StateValue.on` / `.off` |
| `NSArchiver` / `NSUnarchiver` colors | `NSKeyedArchiver` / `NSKeyedUnarchiver`, legacy read fallback |
| `NSBeginAlertSheet` | `NSAlert` |
| `FSRef` / `FSGetVolumeInfo` | `URL` resource values |
| `IOMasterPort()` | `IOMainPort()` / `kIOMainPortDefault` |
| `String(cString:)` from raw buffers | Bounded UTF-8 conversion |
| `/usr/bin/top` subprocess | `libproc` process snapshots |
| AppleScript / System Events automation | `AXUIElement` accessibility traversal, best effort |
| Sparkle 1 `SUUpdater` + DSA | Sparkle 2 `SPUStandardUpdaterController` + EdDSA |
| `LSSharedFileList` only | `SMAppService.mainApp` on macOS 13+, `LSSharedFileList` fallback on macOS 12 |
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
- `Resources/v2.0.8alert.rtf` is shown in the About tab.
- `Resources/com.ragingmenace.MenuMeters.plist` provides the bundled defaults
  used during migration.
- `Resources/releases.html` is the release-history page.

Both build paths copy the disk TIFFs and localized tables to the top level of
`Contents/Resources`, which is where `NSImage(named:)` and
`Bundle.localizedString(forKey:value:table:)` expect them.

`build-clt.sh` is the reference build. It compiles every Swift source for
`arm64` and `x86_64`, links against the bundled Sparkle framework, copies the
resources, and ad-hoc signs the resulting `out/MenuMeters.app`. Setting
`NO_SPARKLE=1` builds without the framework; the `#if canImport(Sparkle)`
branches hide update controls in that configuration.

The x86_64 link passes `-runtime-compatibility-version none` because recent
Command Line Tools ship the Swift 5.6 back-deployment compatibility library
with an arm64 slice only. MenuMeters does not use Swift concurrency, so the
back-deployment library is not required.

The Xcode project contains the same sources and resources, uses resource
variant groups for the localized string tables, and embeds Sparkle with a
`CodeSignOnCopy` build phase. The shared `MenuMeters` scheme builds the app;
CI runs both the Xcode and Command Line Tools builds.

## Deployment and signing

- Minimum deployment target: **macOS 12.0**, matching Sparkle 2.10.1.
- Architectures: `arm64` and `x86_64`.
- Swift language mode: Swift 5.
- Local builds use ad-hoc signing. Release builds should use a Developer ID
  identity, sign the embedded Sparkle framework and the app with the same
  identity, and be notarized.
- Sparkle updates use EdDSA. The public key is in `MenuMeters-Info.plist`; the
  private key is not in the repository.

## Known limitations and follow-up work

- There is no automated test suite. `./build-clt.sh` compiles every source file
  for both architectures and the CI workflow builds the Xcode project as well.
- Activity Monitor's toolbar is not public API. The accessibility traversal
  used for pane switching is intentionally best effort and may need adjustment
  after major Activity Monitor redesigns. It requires Accessibility permission.
- `NSUnarchiver` and `LSSharedFileList` produce deprecation warnings. They are
  retained only for reading old preferences and for the macOS 12 login-item
  fallback.
- The preference window uses fixed frames inherited from the old nib. A future
  layout pass could make it resize more gracefully.
- Existing appcast entries signed with DSA must be re-signed with the EdDSA key.
  Users still on a DSA build may need a one-time manual update, as described in
  the README.

## Verification

```sh
./build-clt.sh
lipo -info out/MenuMeters.app/Contents/MacOS/MenuMeters
codesign --verify --deep --strict out/MenuMeters.app
```

The no-Sparkle configuration is verified separately:

```sh
NO_SPARKLE=1 ./build-clt.sh
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
