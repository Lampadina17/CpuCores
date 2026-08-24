#include "MemorySampler.h"

#include <CoreFoundation/CoreFoundation.h>
#include <dlfcn.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <string.h>

typedef mach_port_t CCIOObject;
typedef CCIOObject CCIOService;
typedef CFArrayRef (*CCIOPSCopyPowerSourcesByTypeFunction)(int type);
typedef kern_return_t (*CCIOMasterPortFunction)(mach_port_t bootstrapPort, mach_port_t *mainPort);
typedef CFTypeRef (*CCMGCopyAnswerFunction)(CFStringRef key);
typedef CFMutableDictionaryRef (*CCIOServiceMatchingFunction)(const char *name);
typedef CCIOService (*CCIOServiceGetMatchingServiceFunction)(mach_port_t mainPort, CFDictionaryRef matching);
typedef kern_return_t (*CCIORegistryEntryCreateCFPropertiesFunction)(
    CCIOObject entry,
    CFMutableDictionaryRef *properties,
    CFAllocatorRef allocator,
    uint32_t options
);
typedef kern_return_t (*CCIOObjectReleaseFunction)(CCIOObject object);

static bool CCBatteryReadUnsignedNumber(CFDictionaryRef properties, CFStringRef key, uint64_t *result) {
    if (properties == NULL || key == NULL || result == NULL) {
        return false;
    }

    CFTypeRef value = CFDictionaryGetValue(properties, key);
    if (value == NULL || CFGetTypeID(value) != CFNumberGetTypeID()) {
        return false;
    }

    int64_t signedValue = 0;
    if (!CFNumberGetValue((CFNumberRef)value, kCFNumberSInt64Type, &signedValue) || signedValue < 0) {
        return false;
    }

    *result = (uint64_t)signedValue;
    return true;
}

static bool CCBatteryReadUnsignedNumberIncludingBatteryData(
    CFDictionaryRef properties,
    CFStringRef key,
    uint64_t *result
) {
    if (CCBatteryReadUnsignedNumber(properties, key, result)) {
        return true;
    }

    CFTypeRef batteryData = CFDictionaryGetValue(properties, CFSTR("BatteryData"));
    if (batteryData == NULL || CFGetTypeID(batteryData) != CFDictionaryGetTypeID()) {
        return false;
    }

    return CCBatteryReadUnsignedNumber((CFDictionaryRef)batteryData, key, result);
}

static void CCBatteryPopulateSampleFromDictionary(
    CFDictionaryRef properties,
    CCBatteryHealthSample *sample
) {
    if (!sample->hasMaximumCapacity) {
        sample->hasMaximumCapacity =
            CCBatteryReadUnsignedNumberIncludingBatteryData(properties, CFSTR("AppleRawMaxCapacity"), &sample->maximumCapacity) ||
            CCBatteryReadUnsignedNumberIncludingBatteryData(properties, CFSTR("NominalChargeCapacity"), &sample->maximumCapacity) ||
            CCBatteryReadUnsignedNumberIncludingBatteryData(properties, CFSTR("MaximumFCC"), &sample->maximumCapacity);
    }

    if (!sample->hasDesignCapacity) {
        sample->hasDesignCapacity =
            CCBatteryReadUnsignedNumberIncludingBatteryData(properties, CFSTR("DesignCapacity"), &sample->designCapacity) ||
            CCBatteryReadUnsignedNumberIncludingBatteryData(properties, CFSTR("AppleRawDesignCapacity"), &sample->designCapacity);
    }

    if (!sample->hasCycleCount) {
        sample->hasCycleCount =
            CCBatteryReadUnsignedNumberIncludingBatteryData(properties, CFSTR("CycleCount"), &sample->cycleCount) ||
            CCBatteryReadUnsignedNumberIncludingBatteryData(properties, CFSTR("Cycle Count"), &sample->cycleCount);
    }

    if (!sample->hasHealthFraction) {
        uint64_t healthPercent = 0;
        if ((CCBatteryReadUnsignedNumberIncludingBatteryData(
                properties,
                CFSTR("Maximum Capacity Percent"),
                &healthPercent
            ) || CCBatteryReadUnsignedNumberIncludingBatteryData(
                properties,
                CFSTR("MaximumCapacityPercent"),
                &healthPercent
            )) && healthPercent > 0 && healthPercent <= 100) {
            sample->healthFraction = (double)healthPercent / 100.0;
            sample->hasHealthFraction = true;
        }
    }

    if (!sample->hasHealthFraction) {
        uint64_t healthMetric = 0;
        if (CCBatteryReadUnsignedNumberIncludingBatteryData(
                properties,
                CFSTR("BatteryHealthMetric"),
                &healthMetric
            ) && healthMetric > 0 && healthMetric <= 100) {
            sample->healthFraction = (double)healthMetric / 100.0;
            sample->hasHealthFraction = true;
        }
    }
}

static bool CCBatteryCopyMobileGestaltNumber(
    CCMGCopyAnswerFunction copyAnswer,
    CFStringRef key,
    uint64_t *result
) {
    if (copyAnswer == NULL || key == NULL || result == NULL) {
        return false;
    }

    CFTypeRef answer = copyAnswer(key);
    if (answer == NULL) {
        return false;
    }

    bool didRead = false;
    if (CFGetTypeID(answer) == CFNumberGetTypeID()) {
        int64_t signedValue = 0;
        if (CFNumberGetValue((CFNumberRef)answer, kCFNumberSInt64Type, &signedValue) &&
            signedValue >= 0) {
            *result = (uint64_t)signedValue;
            didRead = true;
        }
    }

    CFRelease(answer);
    return didRead;
}

static void CCBatteryPopulateSampleFromMobileGestalt(CCBatteryHealthSample *sample) {
    void *mobileGestalt = dlopen("/usr/lib/libMobileGestalt.dylib", RTLD_LAZY | RTLD_LOCAL);
    if (mobileGestalt == NULL) {
        return;
    }

    CCMGCopyAnswerFunction copyAnswer =
        (CCMGCopyAnswerFunction)dlsym(mobileGestalt, "MGCopyAnswer");
    if (copyAnswer != NULL) {
        if (!sample->hasMaximumCapacity) {
            sample->hasMaximumCapacity = CCBatteryCopyMobileGestaltNumber(
                copyAnswer,
                CFSTR("BatteryMaximumCapacity"),
                &sample->maximumCapacity
            );
        }
        if (!sample->hasDesignCapacity) {
            sample->hasDesignCapacity = CCBatteryCopyMobileGestaltNumber(
                copyAnswer,
                CFSTR("BatteryDesignCapacity"),
                &sample->designCapacity
            );
        }
        if (!sample->hasCycleCount) {
            sample->hasCycleCount = CCBatteryCopyMobileGestaltNumber(
                copyAnswer,
                CFSTR("BatteryCycleCount"),
                &sample->cycleCount
            );
        }
    }

    dlclose(mobileGestalt);
}

bool CCSystemMemoryTakeSample(CCSystemMemorySample *sample) {
    if (sample == NULL) {
        return false;
    }

    memset(sample, 0, sizeof(*sample));

    mach_port_t host = mach_host_self();
    vm_size_t pageSize = 0;
    if (host_page_size(host, &pageSize) != KERN_SUCCESS) {
        return false;
    }

    vm_statistics_data_t statistics;
    memset(&statistics, 0, sizeof(statistics));
    mach_msg_type_number_t statisticsCount = HOST_VM_INFO_COUNT;
    kern_return_t result = host_statistics(
        host,
        HOST_VM_INFO,
        (host_info_t)&statistics,
        &statisticsCount
    );
    if (result != KERN_SUCCESS) {
        return false;
    }

    uint64_t bytesPerPage = (uint64_t)pageSize;
    sample->freeBytes = (uint64_t)statistics.free_count * bytesPerPage;
    sample->activeBytes = (uint64_t)statistics.active_count * bytesPerPage;
    sample->inactiveBytes = (uint64_t)statistics.inactive_count * bytesPerPage;
    sample->wiredBytes = (uint64_t)statistics.wire_count * bytesPerPage;

    // This is the exact classification used by Vidgets:
    // used = active + inactive + wired; total = free + used.
    sample->usedBytes = sample->activeBytes + sample->inactiveBytes + sample->wiredBytes;
    sample->totalBytes = sample->freeBytes + sample->usedBytes;
    sample->usedFraction = sample->totalBytes == 0 ? 0.0 : (double)sample->usedBytes / (double)sample->totalBytes;
    return true;
}

bool CCBatteryHealthTakeSample(CCBatteryHealthSample *sample) {
    if (sample == NULL) {
        return false;
    }

    memset(sample, 0, sizeof(*sample));

    void *ioKit = dlopen("/System/Library/Frameworks/IOKit.framework/IOKit", RTLD_LAZY | RTLD_LOCAL);
    if (ioKit == NULL) {
        return false;
    }

    // This private API is the source used by the Battery settings pane. It
    // requires the com.apple.private.iokit.batterydata entitlement, which a
    // TrollStore build can carry but an ordinary Xcode debug build cannot.
    CCIOPSCopyPowerSourcesByTypeFunction copyPowerSources =
        (CCIOPSCopyPowerSourcesByTypeFunction)dlsym(ioKit, "IOPSCopyPowerSourcesByType");
    if (copyPowerSources != NULL) {
        CFArrayRef powerSources = copyPowerSources(1);
        if (powerSources != NULL) {
            if (CFArrayGetCount(powerSources) > 0) {
                CFTypeRef source = CFArrayGetValueAtIndex(powerSources, 0);
                if (source != NULL && CFGetTypeID(source) == CFDictionaryGetTypeID()) {
                    CCBatteryPopulateSampleFromDictionary((CFDictionaryRef)source, sample);
                }
            }
            CFRelease(powerSources);
        }
    }

    CCIOServiceMatchingFunction serviceMatching =
        (CCIOServiceMatchingFunction)dlsym(ioKit, "IOServiceMatching");
    CCIOMasterPortFunction masterPortFunction =
        (CCIOMasterPortFunction)dlsym(ioKit, "IOMasterPort");
    CCIOServiceGetMatchingServiceFunction getMatchingService =
        (CCIOServiceGetMatchingServiceFunction)dlsym(ioKit, "IOServiceGetMatchingService");
    CCIORegistryEntryCreateCFPropertiesFunction createProperties =
        (CCIORegistryEntryCreateCFPropertiesFunction)dlsym(ioKit, "IORegistryEntryCreateCFProperties");
    CCIOObjectReleaseFunction releaseObject =
        (CCIOObjectReleaseFunction)dlsym(ioKit, "IOObjectRelease");

    if (serviceMatching != NULL && getMatchingService != NULL &&
        createProperties != NULL && releaseObject != NULL) {
        mach_port_t mainPort = MACH_PORT_NULL;
        bool ownsMainPort = masterPortFunction != NULL &&
            masterPortFunction(MACH_PORT_NULL, &mainPort) == KERN_SUCCESS;

        const char *serviceNames[] = {"IOPMPowerSource", "AppleSmartBattery"};
        for (size_t index = 0; index < sizeof(serviceNames) / sizeof(serviceNames[0]); index++) {
            CFMutableDictionaryRef matching = serviceMatching(serviceNames[index]);
            if (matching != NULL) {
                CCIOService service = getMatchingService(mainPort, matching);
                if (service != MACH_PORT_NULL) {
                    CFMutableDictionaryRef properties = NULL;
                    kern_return_t propertiesResult = createProperties(
                        service,
                        &properties,
                        kCFAllocatorDefault,
                        0
                    );
                    releaseObject(service);
                    if (propertiesResult == KERN_SUCCESS && properties != NULL) {
                        CCBatteryPopulateSampleFromDictionary(properties, sample);
                    }
                    if (properties != NULL) {
                        CFRelease(properties);
                    }
                }
            }
        }

        if (ownsMainPort && mainPort != MACH_PORT_NULL) {
            mach_port_deallocate(mach_task_self(), mainPort);
        }
    }

    CCBatteryPopulateSampleFromMobileGestalt(sample);

    if (!sample->hasHealthFraction && sample->hasMaximumCapacity &&
        sample->hasDesignCapacity && sample->designCapacity > 0) {
        double fraction = (double)sample->maximumCapacity / (double)sample->designCapacity;
        if (fraction > 0.0 && fraction < 2.0) {
            sample->healthFraction = fraction;
            sample->hasHealthFraction = true;
        }
    }

    dlclose(ioKit);
    return sample->hasMaximumCapacity || sample->hasDesignCapacity ||
        sample->hasCycleCount || sample->hasHealthFraction;
}
