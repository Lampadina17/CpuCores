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

// Reconstructs the Vidgets calculation using HOST_VM_INFO. Unlike the 2015
// implementation, all byte calculations use 64-bit integers.
bool CCSystemMemoryTakeSample(CCSystemMemorySample *sample);

#ifdef __cplusplus
}
#endif

#endif
