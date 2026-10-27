#!/bin/bash
#
# Build MenuMeters with the Command Line Tools only (no Xcode installation).
#
#   ./build-clt.sh                 -> out/MenuMeters (universal arm64 + x86_64)
#
# To install into an existing app bundle (keeps the compiled nibs/resources):
#
#   cp out/MenuMeters /Applications/MenuMeters.app/Contents/MacOS/MenuMeters
#   codesign -f -s - --options runtime --entitlements MenuMeters.entitlements \
#            --deep /Applications/MenuMeters.app
#
# The app links against Sparkle.framework. If you ad-hoc sign the app with the
# hardened runtime, add com.apple.security.cs.disable-library-validation to a
# temporary entitlements file (do not use it for Developer ID releases),
# otherwise the runtime refuses to load the framework. With a Developer ID
# identity, sign the app and the framework with that identity instead.
#
set -u
cd "$(dirname "$0")"

SDK=$(xcrun --sdk macosx --show-sdk-path)
OUT=out
rm -rf "$OUT"
mkdir -p "$OUT/obj"

SRCS=(
  MenuMetersApp/main.m
  MenuMetersApp/AppDelegate.m
  PrefPane/MenuMetersPref.m
  PrefPane/MenuMetersPrefWindow.m
  PrefPane/EMCLoginItem.m
  Common/MenuMeterDefaults.m
  MenuMetersMenuExtraBase.m
  Common/MenuMeterPowerMate.m
  Common/MenuMeterWorkarounds.m
  LocalizedStrings.m
  MenuExtras/MenuMeterCPU/MenuMeterCPUExtra.m
  MenuExtras/MenuMeterCPU/MenuMeterCPUStats.m
  MenuExtras/MenuMeterCPU/MenuMeterCPUTopProcesses.m
  MenuExtras/MenuMeterCPU/MenuMeterUptime.m
  MenuExtras/MenuMeterDisk/MenuMeterDiskExtra.m
  MenuExtras/MenuMeterDisk/MenuMeterDiskIO.m
  MenuExtras/MenuMeterDisk/MenuMeterDiskSpace.m
  MenuExtras/MenuMeterMem/MenuMeterMemExtra.m
  MenuExtras/MenuMeterMem/MenuMeterMemStats.m
  MenuExtras/MenuMeterNet/MenuMeterNetExtra.m
  MenuExtras/MenuMeterNet/MenuMeterNetConfig.m
  MenuExtras/MenuMeterNet/MenuMeterNetPPP.m
  MenuExtras/MenuMeterNet/MenuMeterNetStats.m
  hardware_reader/smc_reader.m
  hardware_reader/applesilicon_hardware_reader.m
  hardware_reader/TemperatureReader.m
)

INCS=(-I. -ICommon -IMenuExtras/MenuMeterCPU -IMenuExtras/MenuMeterDisk \
      -IMenuExtras/MenuMeterMem -IMenuExtras/MenuMeterNet -IPrefPane \
      -IMenuMetersApp -Ihardware_reader)

FLAGS=(-isysroot "$SDK" -mmacosx-version-min=12.0 -fobjc-arc -O2 -g0 \
       -include MenuMeters.pch -DELCAPITAN=1 -DSPARKLE=1 \
       -Wall -Wextra -Wno-unused-parameter \
       "${INCS[@]}" -F .)

rc=0
for s in "${SRCS[@]}"; do
  o="$OUT/obj/$(basename "$s" .m).o"
  for arch in arm64 x86_64; do
    clang -arch $arch -c "${FLAGS[@]}" -o "$o.$arch" "$s" 2>>"$OUT/clang.log" || rc=1
  done
  lipo -create "$o.arm64" "$o.x86_64" -output "$o" 2>>"$OUT/clang.log" || rc=1
done

if [ $rc -ne 0 ]; then
  echo "COMPILE FAILED, see $OUT/clang.log"
  exit 1
fi

clang -arch arm64 -arch x86_64 \
  -isysroot "$SDK" -mmacosx-version-min=12.0 \
  -Wl,-rpath,@loader_path/../Frameworks \
  -o "$OUT/MenuMeters" "$OUT"/obj/*.o \
  -framework Cocoa -framework SystemConfiguration -framework IOKit \
  -framework ServiceManagement -framework Foundation \
  -framework ApplicationServices \
  -F . -framework Sparkle 2>>"$OUT/clang.log" || { echo "LINK FAILED, see $OUT/clang.log"; exit 1; }

VERSION=$(sed -n 's/^#define MM_VERSION[[:space:]]*\([0-9.]*\).*/\1/p' InfoPlistPreprocessor.h)
echo "BUILD OK (version $VERSION)"
file "$OUT/MenuMeters"
