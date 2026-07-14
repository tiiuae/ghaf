#ifndef __BPMP_HOST_PROXY__H__
#define __BPMP_HOST_PROXY__H__

#include <linux/types.h>

#define BPMP_HOST_MAX_CLOCKS_SIZE          256
#define BPMP_HOST_MAX_RESETS_SIZE          256
#define BPMP_HOST_MAX_POWER_DOMAINS_SIZE   256

struct bpmp_allowed_res {
	int clocks_size;
    uint32_t clock[BPMP_HOST_MAX_CLOCKS_SIZE];
    int resets_size;
    uint32_t reset[BPMP_HOST_MAX_RESETS_SIZE];
    int pd_size;
    uint32_t pd[BPMP_HOST_MAX_POWER_DOMAINS_SIZE];

};

#endif