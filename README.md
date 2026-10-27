# MenuMeters

MenuMeters is a set of CPU, memory, disk, and network meters for the macOS
menu bar. This is the maintained fork that runs as a regular menu-bar app
(originally by Yuji Tachikawa, based on the classic MenuMeters by Alex Harper).

## Requirements

- macOS 12 Monterey or later (Apple Silicon and Intel)
- Xcode 16 or later, **or** the Command Line Tools

The app is a universal binary (`arm64` + `x86_64`) and is written in Swift with
programmatic AppKit views. There are no nibs or Objective-C sources.

## Features

- CPU usage, per-core graphs, temperature, and a top-process list
- Disk activity and free-space meters with several icon sets
- Memory usage, pressure, paging, and swap information
- Network throughput, interface selection, and PPP/VPN support
- Configurable colors, widths, intervals, and menu-bar display modes
- Sparkle 2 automatic updates with EdDSA signatures
- PowerMate support and automatic login-item registration

Preferences from MenuMeters 2.1.6 and earlier are imported once from
`~/Library/Preferences/com.ragingmenace.MenuMeters.plist`. The current app
stores its settings in the standard domain for its own bundle identifier,
`com.yujitach.MenuMeters`.

## Build

### Xcode

1. Open `MenuMeters.xcodeproj`.
2. Select the `MenuMeters` scheme and the `My Mac` destination.
3. Build and run.

`Sparkle.framework` is bundled in the repository, so no package download is
required. The project uses ad-hoc signing for local builds; select your
Developer ID team and identity for a distributable build. The bundled Sparkle
2.10.1 requires macOS 12, which is why the app's deployment target is
macOS 12.0.

### Command Line Tools only

```sh
./build-clt.sh
```

This produces a complete, ad-hoc-signed `out/MenuMeters.app` bundle containing
the universal executable, Sparkle, localized strings, disk icons, and the
About text. Run it with `open out/MenuMeters.app` or copy it to `/Applications`.

To build without automatic updates:

```sh
NO_SPARKLE=1 ./build-clt.sh
```

The update controls are then hidden at runtime. This is useful when testing on
a machine without the bundled framework.

The script passes `-runtime-compatibility-version none` to `swiftc`. Recent
Command Line Tools ship `libswiftCompatibility56.a` with an arm64 slice only,
which otherwise prevents linking the x86_64 executable against macOS 12.
MenuMeters does not use Swift concurrency, so no back-deployment library is
needed.

To update an existing installation, quit MenuMeters first and replace the
bundle rather than copying only the executable:

```sh
ditto out/MenuMeters.app /Applications/MenuMeters.app
```

The app registers itself as a login item on first launch. During development,
a build can be removed from the login items without opening the UI:

```sh
out/MenuMeters.app/Contents/MacOS/MenuMeters --unregister-login-item
```

## Release signing

MenuMeters uses Sparkle 2 and EdDSA update signatures. The public key is in
`MenuMeters-Info.plist`; the matching private key must be kept outside the
repository and backed up securely. Do not commit it.

The appcast entry for each release must contain an EdDSA signature. The easiest
way is to let Sparkle's `generate_appcast` tool create or update the appcast:

```sh
/path/to/Sparkle/bin/generate_appcast --account MenuMeters /path/to/releases
```

Alternatively, sign a single archive with `sign_update` and put the resulting
`sparkle:edSignature` attribute on the `<enclosure>` element:

```sh
/path/to/Sparkle/bin/sign_update --account MenuMeters MenuMeters.zip
```

Sparkle 2.10 requires macOS 12. When writing an appcast item manually, include
`<sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>`.
`generate_appcast` copies this from the app's `LSMinimumSystemVersion`.

The old DSA signature and `dsa_pub.pem` are no longer used. Existing appcast
entries must be re-signed with the EdDSA key before users can update to a
Sparkle 2 build. Because Sparkle 1 verifies DSA signatures, users still running
a DSA build need a one-time manual update unless you can also add a valid
`sparkle:dsaSignature` to the appcast entry using the old DSA private key
(which is not stored in this repository).

For a Developer ID release, sign the embedded framework and the app with the
same identity, then notarize and staple the result. The `build-clt.sh` output
is ad-hoc signed only and is intended for local use.

## Verification

```sh
./build-clt.sh
lipo -info out/MenuMeters.app/Contents/MacOS/MenuMeters
codesign --verify --deep --strict out/MenuMeters.app
```

There is no automated test suite. The build script is the reference build and
compiles every Swift source file for both architectures with the current SDK.
GitHub Actions runs the Command Line Tools build and the Xcode project build on
every push and pull request.

## Project layout

| Path | Contents |
| --- | --- |
| `Sources/MenuMeters/` | Swift app lifecycle, preferences, meters, temperature, PowerMate, login item |
| `Resources/` | Localizations, disk icon TIFFs, app icon, About RTF, default preferences, release page |
| `MenuMeters-Info.plist` | Bundle metadata, deployment target, and Sparkle keys |
| `Sparkle.framework` | Bundled Sparkle 2.10.1 universal framework |
| `build-clt.sh` | Universal app-bundle build without Xcode |
| `Docs/Modernization.md` | Detailed modernization and compatibility notes |

## Modernization notes

The codebase was originally written for Mac OS X 10.2–10.4 and later kept
running through a series of compatibility layers. The current version has been
rewritten in Swift and uses `NSStatusItem` directly rather than the private
`NSMenuExtra` API. See [`Docs/Modernization.md`](Docs/Modernization.md) for the
architecture and migration details.

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
