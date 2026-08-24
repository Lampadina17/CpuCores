#include "DiskSampler.h"

#include <limits.h>
#include <stddef.h>
#include <string.h>
#include <sys/mount.h>

static bool CCBytesForBlocks(uint64_t blocks, uint64_t bytesPerBlock, uint64_t *bytes) {
    if (bytes == NULL || (bytesPerBlock != 0 && blocks > UINT64_MAX / bytesPerBlock)) {
        return false;
    }

    *bytes = blocks * bytesPerBlock;
    return true;
}

bool CCDiskTakeSample(const char *path, CCDiskSample *sample) {
    if (sample == NULL) {
        return false;
    }

    memset(sample, 0, sizeof(*sample));
    if (path == NULL || path[0] == '\0') {
        return false;
    }

    struct statfs filesystem;
    memset(&filesystem, 0, sizeof(filesystem));
    if (statfs(path, &filesystem) != 0 || filesystem.f_bsize == 0) {
        return false;
    }

    uint64_t bytesPerBlock = (uint64_t)filesystem.f_bsize;
    if (!CCBytesForBlocks((uint64_t)filesystem.f_blocks, bytesPerBlock, &sample->totalBytes) || !CCBytesForBlocks((uint64_t)filesystem.f_bfree, bytesPerBlock, &sample->freeBytes)) {
        memset(sample, 0, sizeof(*sample));
        return false;
    }

    // A filesystem should never report more free bytes than its capacity, but
    // clamping keeps the derived values safe if a transient snapshot does.
    if (sample->freeBytes > sample->totalBytes) {
        sample->freeBytes = sample->totalBytes;
    }

    sample->usedBytes = sample->totalBytes - sample->freeBytes;
    sample->usedFraction = sample->totalBytes == 0 ? 0.0 : (double)sample->usedBytes / (double)sample->totalBytes;
    return sample->totalBytes != 0;
}
