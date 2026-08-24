#ifndef MemorySampler_h
#define MemorySampler_h

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t freeBytes;
    uint64_t activeBytes;
    uint64_t inactiveBytes;
    uint64_t wiredBytes;
    uint64_t usedBytes;
    uint64_t totalBytes;
    double usedFraction;
} CCSystemMemorySample;

typedef struct {
    bool hasMaximumCapacity;
    bool hasDesignCapacity;
    bool hasCycleCount;
    bool hasHealthFraction;
    uint64_t maximumCapacity;
    uint64_t designCapacity;
    uint64_t cycleCount;
    double healthFraction;
} CCBatteryHealthSample;

// Reconstructs the Vidgets calculation using HOST_VM_INFO. Unlike the 2015
// implementation, all byte calculations use 64-bit integers.
bool CCSystemMemoryTakeSample(CCSystemMemorySample *sample);

// Battery-health values are not part of the public iOS SDK. This function
// resolves IOKit at runtime and simply returns false when access is unavailable.
bool CCBatteryHealthTakeSample(CCBatteryHealthSample *sample);

#ifdef __cplusplus
}
#endif

#endif
