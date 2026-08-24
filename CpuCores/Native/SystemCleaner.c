#include "SystemCleaner.h"
#include "MemorySampler.h"

#include <dirent.h>
#include <errno.h>
#include <fcntl.h>
#include <os/proc.h>
#include <stdbool.h>
#include <stddef.h>
#include <stdint.h>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <sys/mount.h>
#include <sys/stat.h>
#include <time.h>
#include <unistd.h>

#define CC_MIB ((uint64_t)1024 * 1024)
#define CC_GIB ((uint64_t)1024 * 1024 * 1024)

#define CC_RAM_CHUNK_BYTES (8 * CC_MIB)
#define CC_RAM_HEADROOM_BYTES (192 * CC_MIB)
#define CC_RAM_DEEP_TARGET_PERCENT 50
#define CC_RAM_DEEP_MAX_PASSES 3
#define CC_RAM_DEEP_HOLD_MILLISECONDS 200
#define CC_RAM_DEEP_RECOVERY_MILLISECONDS 100

#define CC_DISK_BUFFER_BYTES (8 * CC_MIB)
#define CC_DISK_MAX_BYTES (4 * CC_GIB)
#define CC_DISK_RESERVE_BYTES (1 * CC_GIB)

static const char *CCDiskFilePrefix = ".cpucores_apfs_pressure_";

static uint64_t CCMinimum(uint64_t lhs, uint64_t rhs) {
    return lhs < rhs ? lhs : rhs;
}

static bool CCIsCancelled(const CCCleanerCancellation *cancellation) {
    if (cancellation == NULL) {
        return false;
    }
    return __atomic_load_n(&cancellation->opaqueCancelled, __ATOMIC_ACQUIRE) != 0;
}

void CCCleanerCancellationReset(CCCleanerCancellation *cancellation) {
    if (cancellation != NULL) {
        __atomic_store_n(&cancellation->opaqueCancelled, 0, __ATOMIC_RELEASE);
    }
}

void CCCleanerCancellationRequest(CCCleanerCancellation *cancellation) {
    if (cancellation != NULL) {
        __atomic_store_n(&cancellation->opaqueCancelled, 1, __ATOMIC_RELEASE);
    }
}

static uint64_t CCNextRandom(uint64_t *state) {
    uint64_t value = *state;
    value ^= value >> 12;
    value ^= value << 25;
    value ^= value >> 27;
    *state = value;
    return value * UINT64_C(2685821657736338717);
}

static void CCFillMemory(void *memory, size_t byteCount, uint64_t *state) {
    volatile uint64_t *words = (volatile uint64_t *)memory;
    size_t wordCount = byteCount / sizeof(uint64_t);
    for (size_t index = 0; index < wordCount; index++) {
        words[index] = CCNextRandom(state);
    }

    volatile uint8_t *tail = (volatile uint8_t *)(words + wordCount);
    for (size_t index = wordCount * sizeof(uint64_t); index < byteCount; index++) {
        tail[index - wordCount * sizeof(uint64_t)] = (uint8_t)CCNextRandom(state);
    }
}

static void CCSleepMilliseconds(uint32_t milliseconds, const CCCleanerCancellation *cancellation) {
    const uint32_t sliceMilliseconds = 20;
    uint32_t remaining = milliseconds;
    while (remaining > 0 && !CCIsCancelled(cancellation)) {
        uint32_t current = remaining < sliceMilliseconds ? remaining : sliceMilliseconds;
        struct timespec duration = {
            .tv_sec = current / 1000,
            .tv_nsec = (long)(current % 1000) * 1000000L
        };
        while (nanosleep(&duration, &duration) != 0 && errno == EINTR) {
        }
        remaining -= current;
    }
}

CCRAMCleanerResult CCCleanRAM(const CCCleanerCancellation *cancellation) {
    CCRAMCleanerResult result;
    memset(&result, 0, sizeof(result));
    result.status = CC_CLEANER_STATUS_UNAVAILABLE;

    uint64_t availableBefore = (uint64_t)os_proc_available_memory();
    result.availableBeforeBytes = availableBefore;
    if (availableBefore == 0) {
        return result;
    }

    if (CCIsCancelled(cancellation)) {
        result.status = CC_CLEANER_STATUS_CANCELLED;
        result.availableAfterBytes = availableBefore;
        return result;
    }

    if (availableBefore <= CC_RAM_HEADROOM_BYTES) {
        result.status = CC_CLEANER_STATUS_NO_WORK;
        result.availableAfterBytes = availableBefore;
        return result;
    }

    // The reverse-engineered "Very Deep" profile targets 50% of physical
    // memory and repeats the pressure up to three times. Keep the same shape,
    // but preserve process headroom so modern iOS can cancel and recover.
    CCSystemMemorySample memorySample;
    uint64_t physicalMemoryBytes = 0;
    if (CCSystemMemoryTakeSample(&memorySample)) {
        physicalMemoryBytes = memorySample.totalBytes;
    }
    if (physicalMemoryBytes == 0) {
        physicalMemoryBytes = availableBefore;
    }

    uint64_t deepTargetBytes = physicalMemoryBytes * CC_RAM_DEEP_TARGET_PERCENT / 100;
    uint64_t randomState = (uint64_t)time(NULL) ^ ((uint64_t)getpid() << 32);
    if (randomState == 0) {
        randomState = UINT64_C(0x9e3779b97f4a7c15);
    }

    for (uint32_t pass = 0; pass < CC_RAM_DEEP_MAX_PASSES; pass++) {
        if (CCIsCancelled(cancellation)) {
            result.status = CC_CLEANER_STATUS_CANCELLED;
            break;
        }

        uint64_t availableAtPassStart = (uint64_t)os_proc_available_memory();
        if (availableAtPassStart <= CC_RAM_HEADROOM_BYTES + CC_MIB) {
            break;
        }

        uint64_t targetBytes = CCMinimum(
            deepTargetBytes,
            availableAtPassStart - CC_RAM_HEADROOM_BYTES
        );
        if (targetBytes < CC_MIB) {
            break;
        }

        uint64_t maximumBlockCount = targetBytes / CC_RAM_CHUNK_BYTES;
        if (targetBytes % CC_RAM_CHUNK_BYTES != 0) {
            maximumBlockCount++;
        }
        if (maximumBlockCount == 0 || maximumBlockCount > SIZE_MAX / sizeof(void *)) {
            result.status = CC_CLEANER_STATUS_ALLOCATION_FAILED;
            break;
        }

        void **blocks = calloc((size_t)maximumBlockCount, sizeof(void *));
        if (blocks == NULL) {
            result.status = CC_CLEANER_STATUS_ALLOCATION_FAILED;
            break;
        }

        size_t blockCount = 0;
        uint64_t committedThisPass = 0;
        while (committedThisPass < targetBytes && blockCount < (size_t)maximumBlockCount) {
            if (CCIsCancelled(cancellation)) {
                result.status = CC_CLEANER_STATUS_CANCELLED;
                break;
            }

            uint64_t availableNow = (uint64_t)os_proc_available_memory();
            if (availableNow <= CC_RAM_HEADROOM_BYTES + CC_MIB) {
                break;
            }

            uint64_t remaining = targetBytes - committedThisPass;
            uint64_t safeAllocation = availableNow - CC_RAM_HEADROOM_BYTES;
            size_t chunkBytes = (size_t)CCMinimum(
                CCMinimum(remaining, safeAllocation),
                CC_RAM_CHUNK_BYTES
            );
            if (chunkBytes < CC_MIB) {
                break;
            }

            void *block = malloc(chunkBytes);
            if (block == NULL) {
                result.status = CC_CLEANER_STATUS_ALLOCATION_FAILED;
                break;
            }

            CCFillMemory(block, chunkBytes, &randomState);
            blocks[blockCount++] = block;
            committedThisPass += (uint64_t)chunkBytes;
            result.committedBytes += (uint64_t)chunkBytes;
            result.status = CC_CLEANER_STATUS_SUCCESS;
        }

        if (committedThisPass > 0 && result.status == CC_CLEANER_STATUS_SUCCESS) {
            CCSleepMilliseconds(CC_RAM_DEEP_HOLD_MILLISECONDS, cancellation);
            if (CCIsCancelled(cancellation)) {
                result.status = CC_CLEANER_STATUS_CANCELLED;
            }
        }

        while (blockCount > 0) {
            free(blocks[--blockCount]);
        }
        free(blocks);

        if (result.status == CC_CLEANER_STATUS_CANCELLED ||
            result.status == CC_CLEANER_STATUS_ALLOCATION_FAILED) {
            break;
        }
        if (committedThisPass == 0) {
            break;
        }

        CCSleepMilliseconds(CC_RAM_DEEP_RECOVERY_MILLISECONDS, cancellation);
        if (CCIsCancelled(cancellation)) {
            result.status = CC_CLEANER_STATUS_CANCELLED;
            break;
        }

        // Very Deep stops early once genuinely free RAM reaches 50%.
        if (CCSystemMemoryTakeSample(&memorySample) &&
            memorySample.totalBytes > 0 &&
            memorySample.freeBytes >=
                memorySample.totalBytes * CC_RAM_DEEP_TARGET_PERCENT / 100) {
            break;
        }
    }

    if (result.committedBytes == 0 && result.status == CC_CLEANER_STATUS_UNAVAILABLE) {
        result.status = CC_CLEANER_STATUS_NO_WORK;
    }

    result.availableAfterBytes = (uint64_t)os_proc_available_memory();
    return result;
}

static bool CCDiskCapacity(const char *directory, uint64_t *totalBytes, uint64_t *availableBytes) {
    struct statfs filesystem;
    memset(&filesystem, 0, sizeof(filesystem));
    if (directory == NULL || statfs(directory, &filesystem) != 0 || filesystem.f_bsize <= 0) {
        return false;
    }

    uint64_t blockSize = (uint64_t)filesystem.f_bsize;
    uint64_t totalBlocks = (uint64_t)filesystem.f_blocks;
    uint64_t availableBlocks = (uint64_t)filesystem.f_bavail;
    if (totalBlocks > UINT64_MAX / blockSize || availableBlocks > UINT64_MAX / blockSize) {
        return false;
    }

    *totalBytes = totalBlocks * blockSize;
    *availableBytes = availableBlocks * blockSize;
    return true;
}

static bool CCIsCleanerFileName(const char *name) {
    size_t prefixLength = strlen(CCDiskFilePrefix);
    return name != NULL && strncmp(name, CCDiskFilePrefix, prefixLength) == 0 &&
           name[prefixLength] != '\0';
}

void CCCleanerRemoveStaleAPFSFiles(const char *directory) {
    if (directory == NULL || directory[0] == '\0') {
        return;
    }

    int directoryFD = open(directory, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (directoryFD < 0) {
        return;
    }

    DIR *stream = fdopendir(directoryFD);
    if (stream == NULL) {
        close(directoryFD);
        return;
    }

    struct dirent *entry = NULL;
    while ((entry = readdir(stream)) != NULL) {
        if (!CCIsCleanerFileName(entry->d_name)) {
            continue;
        }

        struct stat metadata;
        memset(&metadata, 0, sizeof(metadata));
        if (fstatat(directoryFD, entry->d_name, &metadata, AT_SYMLINK_NOFOLLOW) == 0 &&
            S_ISREG(metadata.st_mode)) {
            (void)unlinkat(directoryFD, entry->d_name, 0);
        }
    }

    closedir(stream);
}

static bool CCWriteAll(int fileDescriptor, const uint8_t *buffer, size_t byteCount) {
    size_t written = 0;
    while (written < byteCount) {
        ssize_t amount = write(fileDescriptor, buffer + written, byteCount - written);
        if (amount > 0) {
            written += (size_t)amount;
            continue;
        }
        if (amount < 0 && errno == EINTR) {
            continue;
        }
        return false;
    }
    return true;
}

CCDiskCleanerResult CCCleanAPFS(const char *directory, const CCCleanerCancellation *cancellation) {
    CCDiskCleanerResult result;
    memset(&result, 0, sizeof(result));
    result.status = CC_CLEANER_STATUS_UNAVAILABLE;

    if (directory == NULL || directory[0] == '\0') {
        return result;
    }

    CCCleanerRemoveStaleAPFSFiles(directory);

    uint64_t totalBytes = 0;
    uint64_t availableBefore = 0;
    if (!CCDiskCapacity(directory, &totalBytes, &availableBefore)) {
        return result;
    }
    result.availableBeforeBytes = availableBefore;

    if (CCIsCancelled(cancellation)) {
        result.status = CC_CLEANER_STATUS_CANCELLED;
        result.availableAfterBytes = availableBefore;
        return result;
    }

    if (availableBefore <= CC_DISK_RESERVE_BYTES + CC_DISK_BUFFER_BYTES) {
        result.status = CC_CLEANER_STATUS_NO_WORK;
        result.availableAfterBytes = availableBefore;
        return result;
    }

    uint64_t targetBytes = CCMinimum(availableBefore * 35 / 100, CC_DISK_MAX_BYTES);
    targetBytes = CCMinimum(targetBytes, availableBefore - CC_DISK_RESERVE_BYTES);
    if (targetBytes < CC_DISK_BUFFER_BYTES) {
        result.status = CC_CLEANER_STATUS_NO_WORK;
        result.availableAfterBytes = availableBefore;
        return result;
    }

    int directoryFD = open(directory, O_RDONLY | O_DIRECTORY | O_CLOEXEC);
    if (directoryFD < 0) {
        result.status = CC_CLEANER_STATUS_IO_ERROR;
        return result;
    }

    char fileName[128];
    int nameLength = snprintf(fileName,sizeof(fileName), "%s%d_%08x.tmp", CCDiskFilePrefix, getpid(), arc4random());
    if (nameLength <= 0 || (size_t)nameLength >= sizeof(fileName)) {
        close(directoryFD);
        result.status = CC_CLEANER_STATUS_IO_ERROR;
        return result;
    }

    int fileFD = openat(directoryFD, fileName, O_WRONLY | O_CREAT | O_EXCL | O_CLOEXEC | O_NOFOLLOW, S_IRUSR | S_IWUSR);
    if (fileFD < 0) {
        close(directoryFD);
        result.status = CC_CLEANER_STATUS_IO_ERROR;
        return result;
    }

    (void)fcntl(fileFD, F_NOCACHE, 1);
    uint8_t *buffer = malloc((size_t)CC_DISK_BUFFER_BYTES);
    if (buffer == NULL) {
        close(fileFD);
        (void)unlinkat(directoryFD, fileName, 0);
        close(directoryFD);
        result.status = CC_CLEANER_STATUS_ALLOCATION_FAILED;
        return result;
    }

    arc4random_buf(buffer, (size_t)CC_DISK_BUFFER_BYTES);
    result.status = CC_CLEANER_STATUS_SUCCESS;

    while (result.temporaryBytesWritten < targetBytes) {
        if (CCIsCancelled(cancellation)) {
            result.status = CC_CLEANER_STATUS_CANCELLED;
            break;
        }

        uint64_t currentTotal = 0;
        uint64_t currentAvailable = 0;
        if (!CCDiskCapacity(directory, &currentTotal, &currentAvailable)) {
            result.status = CC_CLEANER_STATUS_IO_ERROR;
            break;
        }
        (void)currentTotal;
        if (currentAvailable <= CC_DISK_RESERVE_BYTES + CC_DISK_BUFFER_BYTES) {
            break;
        }

        uint64_t remaining = targetBytes - result.temporaryBytesWritten;
        size_t writeBytes = (size_t)CCMinimum(remaining, CC_DISK_BUFFER_BYTES);
        uint64_t sequence = result.temporaryBytesWritten / CC_DISK_BUFFER_BYTES;
        memcpy(buffer, &sequence, sizeof(sequence));
        if (!CCWriteAll(fileFD, buffer, writeBytes)) {
            result.status = CC_CLEANER_STATUS_IO_ERROR;
            break;
        }
        result.temporaryBytesWritten += (uint64_t)writeBytes;
    }

    if (fsync(fileFD) != 0 && result.status == CC_CLEANER_STATUS_SUCCESS) {
        result.status = CC_CLEANER_STATUS_IO_ERROR;
    }
    free(buffer);
    close(fileFD);
    if (unlinkat(directoryFD, fileName, 0) != 0 && result.status == CC_CLEANER_STATUS_SUCCESS) {
        result.status = CC_CLEANER_STATUS_IO_ERROR;
    }
    close(directoryFD);

    // Give APFS a brief moment to publish the new capacity after unlink.
    CCSleepMilliseconds(100, cancellation);
    uint64_t finalTotal = 0;
    uint64_t availableAfter = 0;
    if (CCDiskCapacity(directory, &finalTotal, &availableAfter)) {
        result.availableAfterBytes = availableAfter;
        if (availableAfter > availableBefore) {
            result.estimatedReclaimedBytes = availableAfter - availableBefore;
        }
    }
    (void)totalBytes;
    (void)finalTotal;
    return result;
}
