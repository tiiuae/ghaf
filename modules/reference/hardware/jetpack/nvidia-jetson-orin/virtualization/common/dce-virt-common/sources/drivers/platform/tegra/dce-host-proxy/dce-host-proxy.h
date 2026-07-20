// SPDX-License-Identifier: GPL-2.0-only
#ifndef __DCE_HOST_PROXY__H__
#define __DCE_HOST_PROXY__H__

#include <linux/types.h>

/*
 * struct dce_host_msg - write() payload shared with the guest-side QEMU bridge
 * (nvidia_dce_guest.c); layout must stay in lockstep on both sides. iface
 * selects the DCE IPC interface (DCE_CLIENT_IPC_TYPE_*, dce-client-ipc.h),
 * tx/rx mirror struct dce_ipc_message, ret carries back the relay result.
 */
struct dce_host_msg {
	u32 iface;
	struct {
		void *data;
		size_t size;
	} tx;
	struct {
		void *data;
		size_t size;
	} rx;
	s32 ret;
};

/*
 * Reverse doorbell: one async DCE notification handed to userspace. DCE pushes
 * these unsolicited (vblank, flip completion). The bridge poll()s /dev/dce-host
 * and read()s one struct per event; `size` is how many `data` bytes are valid.
 * Sized to DCE's max IPC message so no notification is ever truncated.
 */
#define DCE_HOST_EVENT_MAX_DATA 4096

struct dce_host_event {
	u32 iface;
	u32 size;
	u8 data[DCE_HOST_EVENT_MAX_DATA];
};

#endif
