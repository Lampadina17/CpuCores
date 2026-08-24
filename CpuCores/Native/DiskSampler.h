#ifndef DiskSampler_h
#define DiskSampler_h

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

typedef struct {
    uint64_t totalBytes;
    uint64_t freeBytes;
    uint64_t usedBytes;
    double usedFraction;
} CCDiskSample;

// Takes one filesystem snapshot for path and derives every value from it.
// Returns false and clears sample when the path cannot be measured.
bool CCDiskTakeSample(const char *path, CCDiskSample *sample);

#ifdef __cplusplus
}
#endif

#endif
