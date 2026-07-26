#ifndef MACGI_SHIMS_H
#define MACGI_SHIMS_H

#include <stdint.h>

int32_t bettergi_shm_open(
    const char *name,
    int32_t flags,
    uint32_t mode);

#endif
