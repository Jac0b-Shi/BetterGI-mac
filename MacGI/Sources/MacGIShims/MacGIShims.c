#include "MacGIShims.h"

#include <sys/mman.h>
#include <sys/stat.h>

int32_t bettergi_shm_open(
    const char *name,
    int32_t flags,
    uint32_t mode)
{
    return shm_open(name, flags, (mode_t)mode);
}
