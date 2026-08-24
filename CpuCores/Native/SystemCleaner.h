#ifndef SystemCleaner_h
#define SystemCleaner_h

#include <stdint.h>

#ifdef __cplusplus
extern "C" {
#endif

enum {
    CC_CLEANER_STATUS_SUCCESS = 0,
    CC_CLEANER_STATUS_CANCELLED = 1,
    CC_CLEANER_STATUS_UNAVAILABLE = 2,
    CC_CLEANER_STATUS_NO_WORK = 3,
    CC_CLEANER_STATUS_ALLOCATION_FAILED = 4,
    CC_CLEANER_STATUS_IO_ERROR = 5
};

typedef struct {
    uint32_t opaqueCancelled;
} CCCleanerCancellation;

typedef struct {
    uint32_t status;
    uint64_t availableBeforeBytes;
    uint64_t availableAfterBytes;
    uint64_t committedBytes;
} CCRAMCleanerResult;

typedef struct {
    uint32_t status;
    uint64_t availableBeforeBytes;
    uint64_t availableAfterBytes;
    uint64_t temporaryBytesWritten;
    uint64_t estimatedReclaimedBytes;
} CCDiskCleanerResult;

// The cancellation object may be shared between the UI thread and a cleaner.
void CCCleanerCancellationReset(CCCleanerCancellation *cancellation);
void CCCleanerCancellationRequest(CCCleanerCancellation *cancellation);

// Removes only incomplete pressure files left by a previous interrupted run.
void CCCleanerRemoveStaleAPFSFiles(const char *directory);

// Runs the three-pass, 50%-of-physical-memory "Very Deep" pressure profile.
// Every block is temporary and a process headroom margin is always preserved.
CCRAMCleanerResult CCCleanRAM(const CCCleanerCancellation *cancellation);

// Creates one bounded temporary file inside directory, then always removes it.
// Only stale files created by this implementation are removed.
CCDiskCleanerResult CCCleanAPFS(const char *directory,
                               const CCCleanerCancellation *cancellation);

#ifdef __cplusplus
}
#endif

#endif
