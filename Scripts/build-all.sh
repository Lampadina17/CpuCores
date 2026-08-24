#!/bin/bash

set -euo pipefail

readonly BUILD_SCRIPT_DIRECTORY="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
readonly BUILD_REPOSITORY_ROOT="$(cd "$BUILD_SCRIPT_DIRECTORY/.." && pwd)"
readonly BUILD_PROJECT_PATH="$BUILD_REPOSITORY_ROOT/CpuCores.xcodeproj"
readonly BUILD_SCHEME="CpuCores"
readonly BUILD_CONFIGURATION="Release"
readonly BUILD_ENTITLEMENTS="$BUILD_SCRIPT_DIRECTORY/TrollStore.entitlements"

print_usage() {
    echo "Usage: $0 [output-directory]"
    echo
    echo "Builds all CpuCores IPA variants with a single Xcode compilation:"
    echo "  CpuCores-unsigned.ipa"
    echo "  CpuCores-TrollStore.tipa"
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
readonly BUILD_UNSIGNED_OUTPUT="$BUILD_OUTPUT_DIRECTORY/CpuCores-unsigned.ipa"
readonly BUILD_TROLLSTORE_OUTPUT="$BUILD_OUTPUT_DIRECTORY/CpuCores-TrollStore.tipa"
readonly BUILD_TEMP_DIRECTORY="$(mktemp -d "${TMPDIR:-/tmp}/cpucores-all.XXXXXX")"
readonly BUILD_DERIVED_DATA="$BUILD_TEMP_DIRECTORY/DerivedData"
readonly BUILD_APP_BUNDLE="$BUILD_DERIVED_DATA/Build/Products/Release-iphoneos/CpuCores.app"
readonly BUILD_UNSIGNED_DIRECTORY="$BUILD_TEMP_DIRECTORY/Unsigned"
readonly BUILD_UNSIGNED_PAYLOAD="$BUILD_UNSIGNED_DIRECTORY/Payload"
readonly BUILD_UNSIGNED_ARCHIVE="$BUILD_TEMP_DIRECTORY/CpuCores-unsigned.ipa"
readonly BUILD_TROLLSTORE_DIRECTORY="$BUILD_TEMP_DIRECTORY/TrollStore"
readonly BUILD_TROLLSTORE_PAYLOAD="$BUILD_TROLLSTORE_DIRECTORY/Payload"
readonly BUILD_TROLLSTORE_APP="$BUILD_TROLLSTORE_PAYLOAD/CpuCores.app"
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

if [[ ! -f "$BUILD_ENTITLEMENTS" ]]; then
    echo "error: TrollStore entitlements not found at $BUILD_ENTITLEMENTS" >&2
    exit 1
fi

for BUILD_COMMAND in xcodebuild codesign ditto unzip; do
    if ! command -v "$BUILD_COMMAND" >/dev/null 2>&1; then
        echo "error: $BUILD_COMMAND is unavailable." >&2
        exit 1
    fi
done

mkdir -p \
    "$BUILD_OUTPUT_DIRECTORY" \
    "$BUILD_UNSIGNED_PAYLOAD" \
    "$BUILD_TROLLSTORE_PAYLOAD"

echo "Building unsigned $BUILD_CONFIGURATION app…"
xcodebuild \
    -quiet \
    -project "$BUILD_PROJECT_PATH" \
    -scheme "$BUILD_SCHEME" \
    -configuration "$BUILD_CONFIGURATION" \
    -destination "generic/platform=iOS" \
    -derivedDataPath "$BUILD_DERIVED_DATA" \
    CODE_SIGNING_ALLOWED=NO \
    CODE_SIGNING_REQUIRED=NO \
    CODE_SIGN_IDENTITY="" \
    DEVELOPMENT_TEAM="" \
    build

if [[ ! -d "$BUILD_APP_BUNDLE" ]]; then
    echo "error: build succeeded but CpuCores.app was not found." >&2
    exit 1
fi

if [[ ! -d "$BUILD_APP_BUNDLE/PlugIns/widgetExtension.appex" ]]; then
    echo "error: the widget extension is missing from the app bundle." >&2
    exit 1
fi

ditto "$BUILD_APP_BUNDLE" "$BUILD_UNSIGNED_PAYLOAD/CpuCores.app"

BUILD_UNEXPECTED_SIGNATURE="$(find "$BUILD_UNSIGNED_PAYLOAD" -type d -name _CodeSignature -print -quit)"
if [[ -n "$BUILD_UNEXPECTED_SIGNATURE" ]]; then
    echo "error: an unexpected code signature was found at $BUILD_UNEXPECTED_SIGNATURE" >&2
    exit 1
fi

BUILD_UNEXPECTED_PROFILE="$(find "$BUILD_UNSIGNED_PAYLOAD" -type f -name embedded.mobileprovision -print -quit)"
if [[ -n "$BUILD_UNEXPECTED_PROFILE" ]]; then
    echo "error: an unexpected provisioning profile was found at $BUILD_UNEXPECTED_PROFILE" >&2
    exit 1
fi

echo "Packaging unsigned IPA…"
ditto -c -k --sequesterRsrc --keepParent \
    "$BUILD_UNSIGNED_PAYLOAD" \
    "$BUILD_UNSIGNED_ARCHIVE"
unzip -tq "$BUILD_UNSIGNED_ARCHIVE" >/dev/null

ditto "$BUILD_UNSIGNED_PAYLOAD" "$BUILD_TROLLSTORE_PAYLOAD"

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

echo "Packaging TrollStore IPA…"
ditto -c -k --sequesterRsrc --keepParent \
    "$BUILD_TROLLSTORE_PAYLOAD" \
    "$BUILD_TROLLSTORE_ARCHIVE"
unzip -tq "$BUILD_TROLLSTORE_ARCHIVE" >/dev/null

mv -f "$BUILD_UNSIGNED_ARCHIVE" "$BUILD_UNSIGNED_OUTPUT"
mv -f "$BUILD_TROLLSTORE_ARCHIVE" "$BUILD_TROLLSTORE_OUTPUT"

echo
echo "All IPA variants were created successfully:"
du -h "$BUILD_UNSIGNED_OUTPUT" "$BUILD_TROLLSTORE_OUTPUT" |
    awk '{ print $2 " (" $1 ")" }'
