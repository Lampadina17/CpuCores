#!/bin/bash

set -euo pipefail

readonly BUILD_SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BUILD_REPOSITORY_ROOT="$(cd "$BUILD_SCRIPT_DIRECTORY/.." && pwd)"
readonly BUILD_PROJECT_PATH="$BUILD_REPOSITORY_ROOT/CpuCores.xcodeproj"
readonly BUILD_SCHEME="CpuCores"
readonly BUILD_CONFIGURATION="Release"
readonly BUILD_TROLLSTORE_XCCONFIG="$BUILD_SCRIPT_DIRECTORY/TrollStore.xcconfig"
readonly BUILD_ENTITLEMENTS="$BUILD_SCRIPT_DIRECTORY/TrollStore.entitlements"
readonly BUILD_VERIFY_PAL="$BUILD_SCRIPT_DIRECTORY/verify-pal-binary.sh"

print_usage() {
    echo "Usage: $0 [output-directory]"
    echo
    echo "Performs separate PAL and TrollStore compilations and creates:"
    echo "  CpuCores-<version>.ipa"
    echo "  CpuCores-<version>-TrollStore.tipa"
    echo
    echo "A relative output directory is resolved from the repository root."
    echo "Default: repository root"
}

if [[ "${1:-}" == "-h" || "${1:-}" == "--help" ]]; then
    print_usage
    exit 0
fi

if [[ $# -gt 1 ]]; then
    print_usage >&2
    exit 2
fi

BUILD_OUTPUT_ARGUMENT="${1:-$BUILD_REPOSITORY_ROOT}"
if [[ "$BUILD_OUTPUT_ARGUMENT" = /* ]]; then
    BUILD_OUTPUT_DIRECTORY="$BUILD_OUTPUT_ARGUMENT"
else
    BUILD_OUTPUT_DIRECTORY="$BUILD_REPOSITORY_ROOT/$BUILD_OUTPUT_ARGUMENT"
fi

readonly BUILD_OUTPUT_DIRECTORY
readonly BUILD_TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/cpucores-all.XXXXXX")"
readonly BUILD_PAL_DERIVED_DATA="$BUILD_TEMP_DIRECTORY/DerivedData-PAL"
readonly BUILD_TROLLSTORE_DERIVED_DATA="$BUILD_TEMP_DIRECTORY/DerivedData-TrollStore"
readonly BUILD_PAL_APP="$BUILD_PAL_DERIVED_DATA/Build/Products/Release-iphoneos/CPU Cores.app"
readonly BUILD_TROLLSTORE_APP_SOURCE="$BUILD_TROLLSTORE_DERIVED_DATA/Build/Products/Release-iphoneos/CPU Cores.app"
readonly BUILD_PAL_DIRECTORY="$BUILD_TEMP_DIRECTORY/PAL"
readonly BUILD_PAL_PAYLOAD="$BUILD_PAL_DIRECTORY/Payload"
readonly BUILD_PAL_ARCHIVE="$BUILD_TEMP_DIRECTORY/CpuCores-PAL.ipa"
readonly BUILD_TROLLSTORE_DIRECTORY="$BUILD_TEMP_DIRECTORY/TrollStore"
readonly BUILD_TROLLSTORE_PAYLOAD="$BUILD_TROLLSTORE_DIRECTORY/Payload"
readonly BUILD_TROLLSTORE_APP="$BUILD_TROLLSTORE_PAYLOAD/CPU Cores.app"
readonly BUILD_TROLLSTORE_ARCHIVE="$BUILD_TEMP_DIRECTORY/CpuCores-TrollStore.tipa"

cleanup() {
    if [[ -d "$BUILD_TEMP_DIRECTORY" ]]; then
        rm -rf -- "$BUILD_TEMP_DIRECTORY"
    fi
}
trap cleanup EXIT

if [[ ! -d "$BUILD_PROJECT_PATH" ]]; then
    echo "error: Xcode project not found at $BUILD_PROJECT_PATH" >&2
    exit 1
fi

for BUILD_FILE in "$BUILD_TROLLSTORE_XCCONFIG" "$BUILD_ENTITLEMENTS" "$BUILD_VERIFY_PAL"; do
    if [[ ! -f "$BUILD_FILE" ]]; then
        echo "error: required file not found at $BUILD_FILE" >&2
        exit 1
    fi
done

for BUILD_COMMAND in xcodebuild codesign ditto unzip strings cmp grep; do
    if ! command -v "$BUILD_COMMAND" >/dev/null 2>&1; then
        echo "error: $BUILD_COMMAND is unavailable." >&2
        exit 1
    fi
done

mkdir -p \
    "$BUILD_OUTPUT_DIRECTORY" \
    "$BUILD_PAL_PAYLOAD" \
    "$BUILD_TROLLSTORE_PAYLOAD"

echo "Building public-API PAL app…"
xcodebuild \
    -quiet \
    -project "$BUILD_PROJECT_PATH" \
    -scheme "$BUILD_SCHEME" \
    -configuration "$BUILD_CONFIGURATION" \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$BUILD_PAL_DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM="" \
    build

if [[ ! -d "$BUILD_PAL_APP" ]]; then
    echo "error: PAL build succeeded but CPU Cores.app was not found." >&2
    exit 1
fi

if [[ ! -d "$BUILD_PAL_APP/PlugIns/widgetExtension.appex" ]]; then
    echo "error: the PAL widget extension is missing from the app bundle." >&2
    exit 1
fi

"$BUILD_VERIFY_PAL" "$BUILD_PAL_APP"
ditto "$BUILD_PAL_APP" "$BUILD_PAL_PAYLOAD/CPU Cores.app"

BUILD_UNEXPECTED_SIGNATURE="$(find "$BUILD_PAL_PAYLOAD" -type d -name _CodeSignature -print -quit)"
if [[ -n "$BUILD_UNEXPECTED_SIGNATURE" ]]; then
    echo "error: an unexpected PAL code signature was found at $BUILD_UNEXPECTED_SIGNATURE" >&2
    exit 1
fi

BUILD_UNEXPECTED_PROFILE="$(find "$BUILD_PAL_PAYLOAD" -type f -name embedded.mobileprovision -print -quit)"
if [[ -n "$BUILD_UNEXPECTED_PROFILE" ]]; then
    echo "error: an unexpected PAL provisioning profile was found at $BUILD_UNEXPECTED_PROFILE" >&2
    exit 1
fi

echo "Packaging public-API PAL IPA…"
ditto -c -k --sequesterRsrc --keepParent \
    "$BUILD_PAL_PAYLOAD" \
    "$BUILD_PAL_ARCHIVE"
unzip -tq "$BUILD_PAL_ARCHIVE" >/dev/null

echo "Building privileged TrollStore app…"
xcodebuild \
    -quiet \
    -project "$BUILD_PROJECT_PATH" \
    -scheme "$BUILD_SCHEME" \
    -configuration "$BUILD_CONFIGURATION" \
    -xcconfig "$BUILD_TROLLSTORE_XCCONFIG" \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$BUILD_TROLLSTORE_DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM="" \
    build

if [[ ! -d "$BUILD_TROLLSTORE_APP_SOURCE" ]]; then
    echo "error: TrollStore build succeeded but CPU Cores.app was not found." >&2
    exit 1
fi

if [[ ! -d "$BUILD_TROLLSTORE_APP_SOURCE/PlugIns/widgetExtension.appex" ]]; then
    echo "error: the TrollStore widget extension is missing from the app bundle." >&2
    exit 1
fi

BUILD_PAL_EXECUTABLE="$BUILD_PAL_APP/CPU Cores"
BUILD_TROLLSTORE_EXECUTABLE_SOURCE="$BUILD_TROLLSTORE_APP_SOURCE/CPU Cores"
if [[ ! -f "$BUILD_PAL_EXECUTABLE" || ! -f "$BUILD_TROLLSTORE_EXECUTABLE_SOURCE" ]]; then
    echo "error: one of the separately compiled executables is missing." >&2
    exit 1
fi

if cmp -s "$BUILD_PAL_EXECUTABLE" "$BUILD_TROLLSTORE_EXECUTABLE_SOURCE"; then
    echo "error: PAL and TrollStore unexpectedly produced the same executable." >&2
    exit 1
fi

for BUILD_PRIVATE_MARKER in MGCopyAnswer IOPSCopyPowerSourcesByType AppleSmartBattery; do
    if ! strings -a "$BUILD_TROLLSTORE_EXECUTABLE_SOURCE" |
        grep -F "$BUILD_PRIVATE_MARKER" >/dev/null; then
        echo "error: TrollStore marker '$BUILD_PRIVATE_MARKER' was not compiled." >&2
        exit 1
    fi
done

ditto "$BUILD_TROLLSTORE_APP_SOURCE" "$BUILD_TROLLSTORE_APP"

echo "Applying TrollStore battery entitlements…"
codesign \
    --force \
    --deep \
    --sign - \
    --entitlements "$BUILD_ENTITLEMENTS" \
    --generate-entitlement-der \
    "$BUILD_TROLLSTORE_APP"

codesign --verify --deep --strict "$BUILD_TROLLSTORE_APP"

BUILD_EMBEDDED_ENTITLEMENTS="$(codesign --display --entitlements :- "$BUILD_TROLLSTORE_APP" 2>/dev/null)"
if [[ "$BUILD_EMBEDDED_ENTITLEMENTS" != *"com.apple.private.iokit.batterydata"* ||
      "$BUILD_EMBEDDED_ENTITLEMENTS" != *"IOPMPowerSourceClient"* ||
      "$BUILD_EMBEDDED_ENTITLEMENTS" != *"com.apple.private.security.no-sandbox"* ||
      "$BUILD_EMBEDDED_ENTITLEMENTS" != *"com.apple.private.security.storage.AppDataContainers"* ||
      "$BUILD_EMBEDDED_ENTITLEMENTS" != *"IOSurfaceRootUserClient"* ]]; then
    echo "error: the expected TrollStore entitlements were not embedded." >&2
    exit 1
fi

echo "Packaging TrollStore TIPA…"
ditto -c -k --sequesterRsrc --keepParent \
    "$BUILD_TROLLSTORE_PAYLOAD" \
    "$BUILD_TROLLSTORE_ARCHIVE"
unzip -tq "$BUILD_TROLLSTORE_ARCHIVE" >/dev/null

BUILD_VERSION="$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$BUILD_PAL_APP/Info.plist")"
if [[ -z "$BUILD_VERSION" || "$BUILD_VERSION" == *[!A-Za-z0-9._-]* ]]; then
    echo "error: invalid app version '$BUILD_VERSION'." >&2
    exit 1
fi

BUILD_PAL_OUTPUT="$BUILD_OUTPUT_DIRECTORY/CpuCores-$BUILD_VERSION.ipa"
BUILD_TROLLSTORE_OUTPUT="$BUILD_OUTPUT_DIRECTORY/CpuCores-$BUILD_VERSION-TrollStore.tipa"
mv -f "$BUILD_PAL_ARCHIVE" "$BUILD_PAL_OUTPUT"
mv -f "$BUILD_TROLLSTORE_ARCHIVE" "$BUILD_TROLLSTORE_OUTPUT"

echo
echo "All variants were created successfully from separate executables:"
du -h "$BUILD_PAL_OUTPUT" "$BUILD_TROLLSTORE_OUTPUT" |
    awk '{ print $2 " (" $1 ")" }'
