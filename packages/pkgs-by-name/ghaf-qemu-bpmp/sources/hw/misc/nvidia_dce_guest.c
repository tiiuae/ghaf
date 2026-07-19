#include "qemu/osdep.h"
#include "qemu/log.h"
#include "qemu/main-loop.h"	/* bql_lock/bql_unlock */
#include "qemu/thread.h"
#include "qemu/atomic.h"
#include <poll.h>
#include "qapi/error.h" /* provides error_fatal() handler */
#include "hw/sysbus.h"	/* provides all sysbus registering func */
#include "hw/misc/nvidia_dce_guest.h"

#define TYPE_NVIDIA_DCE_GUEST "nvidia_dce_guest"
typedef struct NvidiaDceGuestState NvidiaDceGuestState;
DECLARE_INSTANCE_CHECKER(NvidiaDceGuestState, NVIDIA_DCE_GUEST, TYPE_NVIDIA_DCE_GUEST)

/* Forward (sync) window -- guest writes a request, doorbell round-trips it. */
#define TX_BUF   0x0000
#define RX_BUF   0x1000
#define TX_SIZ   0x2000
#define RX_SIZ   0x2008
#define RET_COD  0x2010
#define IFACE    0x2018
#define DOORBELL 0x2100

/*
 * Reverse (async) window -- DCE R5 unsolicited ch_type=3 notifications (vblank,
 * flip-completion a modeset blocks on). Helper thread poll()s /dev/dce-host,
 * read()s one event, publishes it and bumps EVT_SEQ; guest consumes and writes
 * seq to EVT_ACK. Next event held until ACK catches up, so none is overwritten
 * unseen.
 */
#define FWD_SIZE  0x3000  /* forward window; reverse window sits above it so a
			   * sync send never clobbers EVT_SEQ/EVT_ACK. */
#define EVT_SEQ   0x3000  /* u32: bumped per published event (0 = none yet) */
#define EVT_IFACE 0x3004  /* u32: event interface type (ch_type) */
#define EVT_SIZ   0x3008  /* u32: event payload length (<= EVT_MAX) */
#define EVT_ACK   0x300c  /* u32: guest writes the consumed seq here */
#define EVT_BUF   0x3010  /* event payload, up to EVT_MAX */
#define EVT_MAX   0x1000  /* == struct dce_host_event.data[DCE_HOST_EVENT_MAX_DATA] */

#define MEM_SIZE 0x5000
#define HOST_DEVICE_PATH "/dev/dce-host"

/* Mirrors struct dce_host_event (dce-host-proxy.h): one read() per event. */
struct dce_host_event_wire {
	uint32_t iface;
	uint32_t size;
	uint8_t  data[EVT_MAX];
};

// qemu_log_mask(LOG_UNIMP, "%s: \n", __func__ );

struct NvidiaDceGuestState
{
	SysBusDevice parent_obj;
	MemoryRegion iomem;
	int host_device_fd;
	uint8_t mem[MEM_SIZE];
	QemuThread evt_thread;
	bool evt_thread_running;
	uint32_t evt_seq;	/* last seq this device published */
	bool stopping;
};

// Device memory map:

// 0x090e0000 +  /* Base address, size 0x10000 (frame is 0x3000, rest reserved) */

//      0x0000 \ Tx buffer
//      0x0FFF /
//      0x1000 \ Rx buffer
//      0x1FFF /
//      0x2000  -- Tx size  (u64)
//      0x2008  -- Rx size  (u64)
//      0x2010  -- Ret code (s32)
//      0x2018  -- Iface    (u32)
//      0x2100  -- Doorbell -- writing here triggers the forward

//  Data should be aligned to 64bit paragraph.

//  Protocol is:
//  1. Write request payload to 0x0000-0x0FFF
//  2. Write buffer sizes to 0x2000 (Tx) and 0x2008 (Rx), and the interface to 0x2018
//  3. Start the transaction by writing to the doorbell at 0x2100
//  4. Read ret code from 0x2010 and response data from 0x1000-0x1FFF

/*
 * write() fop payload consumed by /dev/dce-host (dce-host-proxy.h). Must stay
 * in lockstep with that struct: iface, tx{data,size}, rx{data,size}, ret;
 * no packing pragmas.
 */
struct dce_host_msg
{
	uint32_t iface;
	struct
	{
		void *data;
		size_t size;
	} tx;
	struct
	{
		void *data;
		size_t size;
	} rx;
	int32_t ret;
};

/*
 * Reverse-doorbell pump. poll()s /dev/dce-host, reads one async DCE
 * notification, publishes it into the reverse window. Gated on EVT_ACK so a
 * slow guest never loses an event (unconsumed events stay in the host ring).
 *
 * ponytail: poll(2) + 500us ack-wait spin, no guest IRQ. nvidia-drm's flip
 * wait is 3s so latency is irrelevant; wire a GIC SPI only if a hot path needs it.
 */
static void *nvidia_dce_guest_evt_thread(void *opaque)
{
	NvidiaDceGuestState *s = opaque;
	struct dce_host_event_wire ev;

	while (!qatomic_read(&s->stopping)) {
		struct pollfd pfd = { .fd = s->host_device_fd, .events = POLLIN };
		ssize_t r;
		uint32_t iface, dsize, ack;
		int n;

		/* Hold off until the guest has acked the last published event. */
		if (s->evt_seq) {
			bql_lock();
			ack = *(uint32_t *)&s->mem[EVT_ACK];
			bql_unlock();
			if (ack != s->evt_seq) {
				g_usleep(500);
				continue;
			}
		}

		n = poll(&pfd, 1, 200);	/* 200ms so we notice ->stopping */
		if (n <= 0 || !(pfd.revents & POLLIN))
			continue;

		r = read(s->host_device_fd, &ev, sizeof(ev));
		if (r < (ssize_t)(2 * sizeof(uint32_t))) {
			/* Never silent: a dropped hotplug event cost a day of
			 * debugging. Kernel retains the event on failed copy,
			 * so a retry sees it again. */
			qemu_log("nvidia_dce_guest: event read failed r=%zd errno=%d\n",
				 r, errno);
			g_usleep(10000);
			continue;
		}

		iface = ev.iface;
		dsize = ev.size;
		if (dsize > EVT_MAX)
			dsize = EVT_MAX;

		bql_lock();
		memcpy(&s->mem[EVT_BUF], ev.data, dsize);
		*(uint32_t *)&s->mem[EVT_IFACE] = iface;
		*(uint32_t *)&s->mem[EVT_SIZ]   = dsize;
		s->evt_seq++;
		*(uint32_t *)&s->mem[EVT_SEQ]   = s->evt_seq;	/* publish last */
		bql_unlock();
	}

	return NULL;
}

static uint64_t nvidia_dce_guest_read(void *opaque, hwaddr addr, unsigned int size)
{
	NvidiaDceGuestState *s = opaque;

	// Bound the full width, not just addr: a tail read must not leak adjacent
	// NvidiaDceGuestState fields.
	if (addr > MEM_SIZE - size)
		return 0xDEADBEEF;

	uint64_t val = 0;
	memcpy(&val, &s->mem[addr], size); // honor size, not a fixed u64 deref
	return val;
}

static void nvidia_dce_guest_write(void *opaque, hwaddr addr, uint64_t data, unsigned int size)
{
	NvidiaDceGuestState *s = opaque;
	int ret;

	struct dce_host_msg messg;

	memset(&messg, 0, sizeof(messg));

	// Bound the full width: a tail write must not clobber adjacent
	// NvidiaDceGuestState fields (host_device_fd, thread state, evt_seq).
	if (addr > MEM_SIZE - size){
		qemu_log_mask(LOG_UNIMP, "qemu: Error addr+size > MEM_SIZE in 0x%lX data: 0x%lX\n", addr, data);
		return;
	}

	switch (addr)
	{
	case DOORBELL:
		// set up the structure from the fields already written into mem[]
		memcpy(&messg.iface, &s->mem[IFACE], sizeof(messg.iface));
		messg.tx.data = &s->mem[TX_BUF];
		memcpy(&messg.tx.size, &s->mem[TX_SIZ], sizeof(messg.tx.size));
		messg.rx.data = &s->mem[RX_BUF];
		memcpy(&messg.rx.size, &s->mem[RX_SIZ], sizeof(messg.rx.size));

		ret = write(s->host_device_fd, &messg, sizeof(messg)); // Send the data to the host module, synchronous round-trip
		if (ret < 0)
		{
			qemu_log_mask(LOG_UNIMP, "%s: Failed to write the host device..\n", __func__);
			return;
		}

		memcpy(&s->mem[RET_COD], &messg.ret, sizeof(messg.ret));
		memcpy(&s->mem[RX_SIZ], &messg.rx.size, sizeof(messg.rx.size));

		break;

	default:

		memcpy(&s->mem[addr], &data, size);
	}

	return;
}

static const MemoryRegionOps nvidia_dce_guest_ops = {
	.read = nvidia_dce_guest_read,
	.write = nvidia_dce_guest_write,
	.endianness = DEVICE_NATIVE_ENDIAN,
	// QEMU clamps to 1..8-byte aligned accesses before the handlers run.
	.valid = {
		.min_access_size = 1,
		.max_access_size = 8,
		.unaligned = false,
	},
	.impl = {
		.min_access_size = 1,
		.max_access_size = 8,
	},
};

static void nvidia_dce_guest_instance_init(Object *obj)
{
	NvidiaDceGuestState *s = NVIDIA_DCE_GUEST(obj);

	/* allocate memory map region */
	memory_region_init_io(&s->iomem, obj, &nvidia_dce_guest_ops, s, TYPE_NVIDIA_DCE_GUEST, MEM_SIZE);
	sysbus_init_mmio(SYS_BUS_DEVICE(obj), &s->iomem);

	s->host_device_fd = open(HOST_DEVICE_PATH, O_RDWR); // Open the device with read/write access

	if (s->host_device_fd < 0)
	{
		qemu_log_mask(LOG_UNIMP, "%s: Failed to open the host device..\n", __func__);
		return;
	}

	/* Start the reverse-doorbell pump now that the host fd is open. */
	s->stopping = false;
	qemu_thread_create(&s->evt_thread, "dce-evt",
			   nvidia_dce_guest_evt_thread, s, QEMU_THREAD_JOINABLE);
	s->evt_thread_running = true;
}

static void nvidia_dce_guest_instance_finalize(Object *obj)
{
	NvidiaDceGuestState *s = NVIDIA_DCE_GUEST(obj);

	if (s->evt_thread_running) {
		qatomic_set(&s->stopping, true);
		qemu_thread_join(&s->evt_thread);
		s->evt_thread_running = false;
	}
	if (s->host_device_fd >= 0)
		close(s->host_device_fd);
}

/* create a new type to define the info related to our device */
static const TypeInfo nvidia_dce_guest_info = {
	.name = TYPE_NVIDIA_DCE_GUEST,
	.parent = TYPE_SYS_BUS_DEVICE,
	.instance_size = sizeof(NvidiaDceGuestState),
	.instance_init = nvidia_dce_guest_instance_init,
	.instance_finalize = nvidia_dce_guest_instance_finalize,
};

static void nvidia_dce_guest_register_types(void)
{
	type_register_static(&nvidia_dce_guest_info);
}

type_init(nvidia_dce_guest_register_types)

	/*
	 * Forward (sync) path via doorbell + reverse (RM_NOTIFY) window drained
	 * by the poll thread from instance_init. Delivery is poll-based (guest
	 * watches EVT_SEQ), so no sysbus IRQ is wired here.
	 */
	DeviceState *nvidia_dce_guest_create(hwaddr addr)
{
	DeviceState *dev = qdev_new(TYPE_NVIDIA_DCE_GUEST);
	sysbus_realize_and_unref(SYS_BUS_DEVICE(dev), &error_fatal);
	sysbus_mmio_map(SYS_BUS_DEVICE(dev), 0, addr);
	return dev;
}
