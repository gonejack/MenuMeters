# MenuMeters

MenuMeters is a set of CPU, memory, disk, and network meters for the macOS menu
bar. This is the maintained fork that runs as a regular menu-bar app (originally
by Yuji Tachikawa, based on the classic MenuMeters by Alex Harper).

## Requirements

- macOS 12 Monterey or later (Apple Silicon and Intel)
- Xcode 16 or later, **or** the Command Line Tools
- A full Xcode installation is needed for `xcodebuild` or for editing the
  remaining main-menu nib; `build-clt.sh` builds everything with the Command
  Line Tools

The app is built as a universal binary (`arm64` + `x86_64`) and uses ARC,
modern Objective-C, and current AppKit/IOKit APIs.

## Build

### Xcode

1. Open `MenuMeters.xcodeproj`.
2. Select the `MenuMeters` scheme and the `My Mac` destination.
3. Build and run.

`Sparkle.framework` is bundled in the repository, so no package download is
required. The bundled Sparkle 2.10.1 requires macOS 12, which is why the app's
deployment target is macOS 12.0.

For a signed/notarized release, sign the app with your Developer ID. Updates
must be signed with the EdDSA key whose public half is stored in
`MenuMeters-Info.plist` (`SUPublicEDKey`); see [Release signing](#release-signing).

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

`MenuMeters.entitlements` only contains the app's normal entitlements. If you
ad-hoc sign a hardened-runtime build that loads the bundled
`Sparkle.framework`, you may additionally need
`com.apple.security.cs.disable-library-validation` in a temporary entitlements
file. Do not add that key to Developer ID release builds; instead sign the
framework and the app with the same identity.

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

The `MenuMeters` keychain account is the one created for this project. If the
key is stored in a file instead, pass it with `--ed-key-file /path/to/key`.

Sparkle 2.10 requires macOS 12. When writing an appcast item manually, include
`<sparkle:minimumSystemVersion>12.0</sparkle:minimumSystemVersion>`.
`generate_appcast` copies this from the app's `LSMinimumSystemVersion`.

The old DSA signature and `dsa_pub.pem` are no longer used. Existing appcast
entries must be re-signed with the EdDSA key before users can update to a
Sparkle 2 build. Because Sparkle 1 verifies DSA signatures, users still running
a DSA build need a one-time manual update unless you can also add a valid
`sparkle:dsaSignature` to the appcast entry using the old DSA private key
(which is not stored in this repository).

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
[`Docs/Modernization.md`](Docs/Modernization.md) for the current state and the
compatibility shims.

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
