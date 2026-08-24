#ifndef MulticoreSampler_h
#define MulticoreSampler_h

#include <stdbool.h>
#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum { CPU_MULTICORE_MAX_CORES = 8 };

typedef void *CPUMulticoreSamplerRef;

CPUMulticoreSamplerRef CPUMulticoreSamplerCreate(void);
void CPUMulticoreSamplerDestroy(CPUMulticoreSamplerRef sampler);
void CPUMulticoreSamplerReset(CPUMulticoreSamplerRef sampler);

// Fills loads with normalized values in the 0.0 ... 1.0 range.
// overallLoad is calculated from the sum of active and total ticks across all
// sampled cores, rather than by measuring only this app's process.
bool CPUMulticoreSamplerTakeSample(CPUMulticoreSamplerRef sampler, float *loads, uint32_t capacity, uint32_t *sampledCoreCount, float *overallLoad);

// Takes a baseline sample, waits for the requested interval, then returns the
// load calculated from the tick delta. Intended for short-lived processes,
// such as a WidgetKit extension, that cannot retain a sampler between runs.
bool CPUMulticoreSamplerTakeIntervalSample(
    CPUMulticoreSamplerRef sampler,
    float *loads,
    uint32_t capacity,
    uint32_t *sampledCoreCount,
    float *overallLoad,
    uint32_t intervalMicroseconds
);

#ifdef __cplusplus
}
#endif

#endif
