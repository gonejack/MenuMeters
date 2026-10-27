# Modernization notes

MenuMeters dates back to the Mac OS X 10.2 era. The goal of the current
modernization pass is to keep the existing behavior while removing APIs that
no longer work or are deprecated on current macOS, and to make the project
build cleanly with current toolchains.

## Toolchain and build settings

- Deployment target raised from macOS 10.11 to **macOS 12.0**, matching
  `build-clt.sh` and the minimum OS of the bundled Sparkle framework.
- C language standard raised from `gnu99` to **`gnu17`**; C++ standard raised
  to `gnu++17`.
- `GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS` is enabled so new deprecated API usage
  is visible during development.
- The reference build (`./build-clt.sh`) produces a universal `arm64` +
  `x86_64` binary and compiles every source file with the current SDK.
- Carbon, Security, and PreferencePanes are no longer required by the source or
  the link step. ApplicationServices is linked for the Accessibility API used
  by Activity Monitor pane switching; ServiceManagement is linked for the
  login-item implementation.

## API migrations

| Old API | Replacement |
| --- | --- |
| `NSOnState` / `NSOffState` | `NSControlStateValueOn` / `NSControlStateValueOff` |
| `NSArchiver` / `NSUnarchiver` (colour prefs) | `NSKeyedArchiver` / `NSKeyedUnarchiver`, with a legacy read fallback |
| Archive/unarchive cycle for `NSNumberFormatter` copies | `-[NSNumberFormatter copy]` |
| `NSCompositeSourceOver` / `NSCompositeCopy` | `NSCompositingOperationSourceOver` / `NSCompositingOperationCopy` |
| `compositeToPoint:operation:` | `drawAtPoint:fromRect:operation:fraction:` |
| `stringWithCString:` | `stringWithUTF8String:` |
| `GetCurrentKeyModifiers()` / `optionKey` | `NSEvent.modifierFlags` / `NSEventModifierFlagOption` |
| `FSRef` / `FSGetVolumeInfo` / `FSGetCatalogInfo` | `NSURL` resource values (`NSURLVolumeNameKey`) |
| `IOMasterPort()` / `kIOMasterPortDefault` | `IOMainPort()` / `kIOMainPortDefault`, available directly with the macOS 12 deployment target |
| `launchApplication:` / `openFile:` | `openApplicationAtURL:configuration:completionHandler:` and `openURL:` (see `Common/MenuMeterWorkspaceCompat.h`) |
| `NSBeginAlertSheet` | `NSAlert` sheet |
| `LSSharedFileList` login items | `SMAppService.mainAppService` on macOS 13+, with `LSSharedFileList` fallback on macOS 12 (see `PrefPane/EMCLoginItem.m`) |
| `readInBackgroundAndNotify` + global notification observer | `NSFileHandle.readabilityHandler` with a weak self capture |
| `SYS_memorystatus_get_level` syscall | `sysctlbyname("kern.memorystatus_level")` |
| `AcquireIconRef` / `ReleaseIconRef` | removed; the icon ref parameter was unused |
| `setScalesWhenResized:` | removed; images are sized explicitly |
| Sparkle 1.x `SUUpdater` + DSA signatures | Sparkle 2 `SPUStandardUpdaterController` + EdDSA (`SUPublicEDKey`) |
| `MenuMetersPref.xib` | programmatic AppKit window in `PrefPane/MenuMetersPrefWindow.m` |
| `/usr/bin/top` subprocess | `libproc` (`proc_listallpids` / `proc_pidinfo`) |
| AppleScript + System Events for Activity Monitor | `AXUIElement` accessibility traversal and `AXPress`, best-effort |

## Performance and reliability improvements

- Timers are block-based and capture `self` weakly; they keep the tolerance
  setting so the system can coalesce wake-ups.
- The top-process reader uses `libproc` instead of launching `/usr/bin/top`.
  It takes two `proc_pidinfo(PROC_PIDTASKINFO)` snapshots 100 ms apart and
  compares the mach absolute-time counters, so no subprocess, pipe, or output
  parser is involved.
- CPU/package counts are file-local statics with guards against zero values,
  removing global symbol pollution and a possible division by zero.
- Disk, CPU, memory, and network formatters are created once and configured
  with properties instead of being round-tripped through an archiver.
- `isDark` uses `bestMatchFromAppearancesWithNames:` instead of a substring
  check on the appearance name.
- Theme changes are handled through the existing
  `effectiveAppearance` KVO path; the pre-Mojave distributed-notification path
  has been removed.

## Compatibility notes

- The deployment target is macOS 12. The macOS 12 IOKit renames are available
  directly, and the macOS 13 login-item API is still selected at runtime with
  an `LSSharedFileList` fallback, so the same binary runs on Monterey and later.
- Preferences written by MenuMeters 2.1.6 and earlier still load: colour
  values fall back to the legacy unarchiver when keyed unarchiving fails.
  Colours saved by this version use secure keyed archives, so downgrading to
  2.1.6 or earlier will show the default colours for those preferences.
- The menu-bar item uses `NSStatusItem`, not the private `NSMenuExtra` API.
  `NSMenuExtra` in the source is only a local compatibility macro.
- Sparkle is bundled at **2.10.1**, which requires macOS 12; the app's
  deployment target was raised to macOS 12.0 to match. The framework is
  universal (`arm64` + `x86_64`), and the appcast must contain EdDSA signatures
  made with the private key matching the `SUPublicEDKey` in
  `MenuMeters-Info.plist`.
- Activity Monitor pane switching requires Accessibility permission. The app
  uses the public Accessibility API directly; it no longer needs Apple Events
  or the Automation entitlement.

## Known follow-up work

- The Activity Monitor toolbar layout is not public API. The accessibility
  traversal is intentionally best-effort and may need adjustment after major
  Activity Monitor redesigns.
- Large parts of the source still use pre-literal Objective-C style
  (`[NSNumber numberWithInt:]`, `objectForKey:`, etc.). These are semantically
  equivalent on the modern runtime and were intentionally left alone to keep
  this change reviewable. Convert them incrementally when touching a file.
- The preference window is now programmatic, but its fixed frames mirror the
  old nib. A future layout pass could make it resize more gracefully.
- There is no automated test suite. `./build-clt.sh` verifies that every
  translation unit compiles with the current SDK, and CI runs both the CLT and
  Xcode builds.

## Verification

```sh
./build-clt.sh

# Optional: compile every file with deprecation warnings visible
SDK=$(xcrun --sdk macosx --show-sdk-path)
find . -name '*.m' -not -path './Sparkle.framework/*' -not -path './out/*' \
  -exec clang -fsyntax-only -isysroot "$SDK" -mmacosx-version-min=12.0 \
  -fobjc-arc -include MenuMeters.pch -DELCAPITAN=1 -DSPARKLE=1 \
  -Wdeprecated-declarations -Wno-unused-parameter \
  -I. -ICommon -IMenuExtras/MenuMeterCPU \
  -IMenuExtras/MenuMeterDisk -IMenuExtras/MenuMeterMem \
  -IMenuExtras/MenuMeterNet -IPrefPane -IMenuMetersApp -Ihardware_reader \
  -F . {} \;
```
