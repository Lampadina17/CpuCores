#include "MemorySampler.h"

#include <mach/mach.h>
#include <mach/mach_host.h>
#include <string.h>

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
