# Modernization notes

MenuMeters dates back to the Mac OS X 10.2 era. The goal of the current
modernization pass is to keep the existing behavior while removing APIs that
no longer work or are deprecated on current macOS, and to make the project
build cleanly with current toolchains.

## Toolchain and build settings

- Deployment target raised from macOS 10.11 to **macOS 11.0**, matching
  `build-clt.sh`.
- C language standard raised from `gnu99` to **`gnu17`**; C++ standard raised
  to `gnu++17`.
- `GCC_WARN_ABOUT_DEPRECATED_FUNCTIONS` is enabled so new deprecated API usage
  is visible during development.
- The reference build (`./build-clt.sh`) produces a universal `arm64` +
  `x86_64` binary and compiles every source file with the current SDK.
- Carbon, ApplicationServices, Security, and PreferencePanes are no longer
  required by the source or the link step. ServiceManagement is linked for the
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
| `IOMasterPort()` / `kIOMasterPortDefault` | `IOMainPort()` / `kIOMainPortDefault` on macOS 12+, with a runtime fallback (see `Common/MenuMeterIOCompat.h`) |
| `launchApplication:` / `openFile:` | `openApplicationAtURL:configuration:completionHandler:` and `openURL:` (see `Common/MenuMeterWorkspaceCompat.h`) |
| `NSBeginAlertSheet` | `NSAlert` sheet |
| `LSSharedFileList` login items | `SMAppService.mainAppService` on macOS 13+, with `LSSharedFileList` fallback on macOS 11–12 (see `PrefPane/EMCLoginItem.m`) |
| `readInBackgroundAndNotify` + global notification observer | `NSFileHandle.readabilityHandler` with a weak self capture |
| `SYS_memorystatus_get_level` syscall | `sysctlbyname("kern.memorystatus_level")` |
| `AcquireIconRef` / `ReleaseIconRef` | removed; the icon ref parameter was unused |
| `setScalesWhenResized:` | removed; images are sized explicitly |

## Performance and reliability improvements

- Timers are block-based and capture `self` weakly; they keep the tolerance
  setting so the system can coalesce wake-ups.
- The `top` process reader no longer registers a global
  `NSFileHandleReadCompletionNotification` observer. Output is read from the
  pipe on a background queue and parsed on the main queue.
- Starting the process reader tears down any previous task and clears its
  readability handler; stopping it releases the pipe and task.
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

- The deployment target is macOS 11. The macOS 12 IOKit renames and the
  macOS 13 login-item API are selected at runtime, so the same binary runs on
  Big Sur and later.
- Preferences written by MenuMeters 2.1.6 and earlier still load: colour
  values fall back to the legacy unarchiver when keyed unarchiving fails.
  Colours saved by this version use secure keyed archives, so downgrading to
  2.1.6 or earlier will show the default colours for those preferences.
- The menu-bar item uses `NSStatusItem`, not the private `NSMenuExtra` API.
  `NSMenuExtra` in the source is only a local compatibility macro.

## Known follow-up work

- **Sparkle 1.24** is bundled and uses the legacy DSA update signature. It
  should be migrated to Sparkle 2.x (Swift Package Manager, EdDSA signatures,
  `SPUStandardUpdaterController`) before the next public release. This is the
  largest remaining compatibility/security item.
- The preference window is still nib-based. Moving it to SwiftUI/AppKit
  programmatic layout would simplify future maintenance but is a larger
  behavioral change.
- The Activity Monitor pane switching uses AppleScript and accessibility
  permissions. AppKit has no public API for selecting an Activity Monitor tab,
  so this remains intentionally best-effort.
- The top-process list shells out to `/usr/bin/top`. Using `libproc` would
  avoid a subprocess, but the output format and permissions are stable and
  well understood.
- Large parts of the source still use pre-literal Objective-C style
  (`[NSNumber numberWithInt:]`, `objectForKey:`, etc.). These are semantically
  equivalent on the modern runtime and were intentionally left alone to keep
  this change reviewable. Convert them incrementally when touching a file.
- There is no automated test suite. `./build-clt.sh` verifies that every
  translation unit compiles with the current SDK, and CI runs both the CLT and
  Xcode builds.

## Verification

```sh
./build-clt.sh

# Optional: compile every file with deprecation warnings visible
SDK=$(xcrun --sdk macosx --show-sdk-path)
find . -name '*.m' -not -path './Sparkle.framework/*' -not -path './out/*' \
  -exec clang -fsyntax-only -isysroot "$SDK" -mmacosx-version-min=11.0 \
  -fobjc-arc -include MenuMeters.pch -DELCAPITAN=1 -DSPARKLE=1 \
  -Wdeprecated-declarations -Wno-unused-parameter \
  -I. -ICommon -IMenuExtras/MenuMeterCPU \
  -IMenuExtras/MenuMeterDisk -IMenuExtras/MenuMeterMem \
  -IMenuExtras/MenuMeterNet -IPrefPane -IMenuMetersApp -Ihardware_reader \
  -F . {} \;
```
