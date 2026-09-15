#!/bin/bash

set -euo pipefail

if [[ $# -ne 1 || ! -e "$1" ]]; then
    echo "Usage: $0 <PAL .app bundle or Mach-O binary>" >&2
    exit 2
fi

for VERIFY_COMMAND in strings nm otool codesign file grep find; do
    if ! command -v "$VERIFY_COMMAND" >/dev/null 2>&1; then
        echo "error: $VERIFY_COMMAND is unavailable." >&2
        exit 1
    fi
done

readonly VERIFY_INPUT="$1"
readonly VERIFY_PRIVATE_CODE_PATTERN='MGCopyAnswer|libMobileGestalt|MobileGestalt|IOPSCopyPowerSourcesByType|IOServiceMatching|IOServiceGetMatchingService|IORegistryEntryCreateCFProperties|IOObjectRelease|IOMasterPort|AppleSmartBattery|IOPMPowerSource|IOPMPowerSourceClient|BatteryMaximumCapacity|BatteryDesignCapacity|BatteryCycleCount|IOKit\.framework/IOKit|(^|[^[:alnum:]_])(BatteryData|AppleRawMaxCapacity|NominalChargeCapacity|MaximumFCC|DesignCapacity|AppleRawDesignCapacity|CycleCount|Cycle Count|Maximum Capacity Percent|MaximumCapacityPercent|BatteryHealthMetric)([^[:alnum:]_]|$)'
readonly VERIFY_PRIVATE_ENTITLEMENT_PATTERN='com\.apple\.private\.|platform-application|com\.apple\.security\.iokit-user-client-class|com\.apple\.security\.exception\.iokit-user-client-class|IOPMPowerSourceClient|IOAccelerator|IOGPUDeviceUserClient|IOSurfaceRootUserClient'

VERIFY_BINARIES=()
if [[ -f "$VERIFY_INPUT" ]]; then
    VERIFY_BINARIES+=("$VERIFY_INPUT")
else
    while IFS= read -r -d '' VERIFY_CANDIDATE; do
        if file -b "$VERIFY_CANDIDATE" | grep -q 'Mach-O'; then
            VERIFY_BINARIES+=("$VERIFY_CANDIDATE")
        fi
    done < <(find "$VERIFY_INPUT" -type f -print0)
fi

if [[ ${#VERIFY_BINARIES[@]} -eq 0 ]]; then
    echo "error: no Mach-O binaries found in $VERIFY_INPUT" >&2
    exit 1
fi

VERIFY_FAILED=0
for VERIFY_BINARY in "${VERIFY_BINARIES[@]}"; do
    echo "Checking private strings and symbols: $VERIFY_BINARY"

    if strings -a "$VERIFY_BINARY" | grep -En "$VERIFY_PRIVATE_CODE_PATTERN"; then
        echo "error: private API text found in $VERIFY_BINARY" >&2
        VERIFY_FAILED=1
    fi

    if nm -u "$VERIFY_BINARY" 2>/dev/null | grep -En "$VERIFY_PRIVATE_CODE_PATTERN"; then
        echo "error: private API symbol found in $VERIFY_BINARY" >&2
        VERIFY_FAILED=1
    fi

    if otool -L "$VERIFY_BINARY" 2>/dev/null | grep -En "$VERIFY_PRIVATE_CODE_PATTERN"; then
        echo "error: private framework dependency found in $VERIFY_BINARY" >&2
        VERIFY_FAILED=1
    fi

    VERIFY_ENTITLEMENTS="$(codesign --display --entitlements :- "$VERIFY_BINARY" 2>/dev/null || true)"
    if [[ -n "$VERIFY_ENTITLEMENTS" ]]; then
        if printf '%s\n' "$VERIFY_ENTITLEMENTS" | grep -En "$VERIFY_PRIVATE_ENTITLEMENT_PATTERN"; then
            echo "error: private entitlement found in $VERIFY_BINARY" >&2
            VERIFY_FAILED=1
        fi
    else
        echo "No embedded entitlements (binary is unsigned or has an empty entitlement set)."
    fi
done

if [[ $VERIFY_FAILED -ne 0 ]]; then
    exit 1
fi

echo "PAL verification passed for ${#VERIFY_BINARIES[@]} Mach-O binary/binaries."
