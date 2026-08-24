#include "MulticoreSampler.h"

#include <errno.h>
#include <mach/mach.h>
#include <mach/mach_host.h>
#include <mach/processor_info.h>
#include <stdlib.h>
#include <string.h>
#include <time.h>

typedef struct {
    processor_info_array_t previousInfo;
    mach_msg_type_number_t previousInfoCount;
} CPUMulticoreSampler;

static uint32_t TickDelta(uint32_t current, uint32_t previous) {
    // Unsigned subtraction also handles a single 32-bit counter wrap.
    return current - previous;
}

static void DeallocateInfo(processor_info_array_t info, mach_msg_type_number_t infoCount) {
    if (info == NULL) {
        return;
    }
    vm_deallocate(mach_task_self(), (vm_address_t)info, (vm_size_t)infoCount * sizeof(integer_t));
}

static void SleepMicroseconds(uint32_t microseconds) {
    struct timespec remaining = {
        .tv_sec = microseconds / 1000000U,
        .tv_nsec = (long)(microseconds % 1000000U) * 1000L
    };

    while (nanosleep(&remaining, &remaining) == -1 && errno == EINTR) {
    }
}

CPUMulticoreSamplerRef CPUMulticoreSamplerCreate(void) {
    return calloc(1, sizeof(CPUMulticoreSampler));
}

void CPUMulticoreSamplerDestroy(CPUMulticoreSamplerRef samplerRef) {
    if (samplerRef == NULL) {
        return;
    }
    CPUMulticoreSampler *sampler = samplerRef;
    DeallocateInfo(sampler->previousInfo, sampler->previousInfoCount);
    free(sampler);
}

void CPUMulticoreSamplerReset(CPUMulticoreSamplerRef samplerRef) {
    if (samplerRef == NULL) {
        return;
    }
    CPUMulticoreSampler *sampler = samplerRef;
    DeallocateInfo(sampler->previousInfo, sampler->previousInfoCount);
    sampler->previousInfo = NULL;
    sampler->previousInfoCount = 0;
}

bool CPUMulticoreSamplerTakeSample(CPUMulticoreSamplerRef samplerRef, float *loads, uint32_t capacity, uint32_t *sampledCoreCount, float *overallLoad) {
    if (samplerRef == NULL || loads == NULL || capacity == 0 ||
        sampledCoreCount == NULL || overallLoad == NULL) {
        return false;
    }

    *sampledCoreCount = 0;
    *overallLoad = 0.0f;
    memset(loads, 0, (size_t)capacity * sizeof(float));

    natural_t processorCount = 0;
    processor_info_array_t rawInfo = NULL;
    mach_msg_type_number_t rawInfoCount = 0;

    kern_return_t result = host_processor_info(mach_host_self(), PROCESSOR_CPU_LOAD_INFO, &processorCount, &rawInfo, &rawInfoCount);
    if (result != KERN_SUCCESS) {
        return false;
    }

    natural_t availableCoreCount = rawInfoCount / PROCESSOR_CPU_LOAD_INFO_COUNT;
    natural_t coreCount = processorCount;
    if (coreCount > availableCoreCount) {
        coreCount = availableCoreCount;
    }
    if (coreCount > CPU_MULTICORE_MAX_CORES) {
        coreCount = CPU_MULTICORE_MAX_CORES;
    }
    if (coreCount > capacity) {
        coreCount = capacity;
    }

    CPUMulticoreSampler *sampler = samplerRef;
    processor_cpu_load_info_t current = (processor_cpu_load_info_t)rawInfo;
    processor_cpu_load_info_t previous = (processor_cpu_load_info_t)sampler->previousInfo;

    uint64_t allActiveTicks = 0;
    uint64_t allTicks = 0;

    for (natural_t core = 0; core < coreCount; ++core) {
        uint64_t activeTicks;
        uint64_t idleTicks;
        bool hasPrevious =
            previous != NULL &&
            sampler->previousInfoCount >= (core + 1) * PROCESSOR_CPU_LOAD_INFO_COUNT;

        if (hasPrevious) {
            activeTicks = (uint64_t)TickDelta(current[core].cpu_ticks[CPU_STATE_USER], previous[core].cpu_ticks[CPU_STATE_USER]) + TickDelta(current[core].cpu_ticks[CPU_STATE_SYSTEM], previous[core].cpu_ticks[CPU_STATE_SYSTEM]) + TickDelta(current[core].cpu_ticks[CPU_STATE_NICE], previous[core].cpu_ticks[CPU_STATE_NICE]);
            idleTicks = TickDelta(current[core].cpu_ticks[CPU_STATE_IDLE], previous[core].cpu_ticks[CPU_STATE_IDLE]);
        } else {
            // Same first-sample behavior as the recovered Vidgets routine.
            activeTicks = (uint64_t)current[core].cpu_ticks[CPU_STATE_USER] + current[core].cpu_ticks[CPU_STATE_SYSTEM] + current[core].cpu_ticks[CPU_STATE_NICE];
            idleTicks = current[core].cpu_ticks[CPU_STATE_IDLE];
        }

        uint64_t totalTicks = activeTicks + idleTicks;
        loads[core] = totalTicks == 0 ? 0.0f : (float)activeTicks / (float)totalTicks;
        allActiveTicks += activeTicks;
        allTicks += totalTicks;
    }

    *sampledCoreCount = (uint32_t)coreCount;
    *overallLoad = allTicks == 0 ? 0.0f : (float)allActiveTicks / (float)allTicks;

    DeallocateInfo(sampler->previousInfo, sampler->previousInfoCount);
    sampler->previousInfo = rawInfo;
    sampler->previousInfoCount = rawInfoCount;
    return true;
}

bool CPUMulticoreSamplerTakeIntervalSample(
    CPUMulticoreSamplerRef samplerRef,
    float *loads,
    uint32_t capacity,
    uint32_t *sampledCoreCount,
    float *overallLoad,
    uint32_t intervalMicroseconds
) {
    if (!CPUMulticoreSamplerTakeSample(
        samplerRef,
        loads,
        capacity,
        sampledCoreCount,
        overallLoad
    )) {
        return false;
    }

    SleepMicroseconds(intervalMicroseconds);
    return CPUMulticoreSamplerTakeSample(
        samplerRef,
        loads,
        capacity,
        sampledCoreCount,
        overallLoad
    );
}
