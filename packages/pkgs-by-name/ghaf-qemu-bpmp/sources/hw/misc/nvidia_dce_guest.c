#include "qemu/osdep.h"
#include "hw/irq.h"
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

/* Single-slot reverse-event window, level SPI, and guest ACK handshake. */
#define FWD_SIZE  0x3000  /* forward window; reverse window sits above it so a
			   * sync send never clobbers EVT_SEQ/EVT_ACK. */
#define EVT_SEQ   0x3000  /* u32: bumped per published event (0 = none yet) */
#define EVT_IFACE 0x3004  /* u32: event interface type (ch_type) */
#define EVT_SIZ   0x3008  /* u32: event payload length (<= EVT_MAX) */
#define EVT_ACK   0x300c  /* u32: guest writes the consumed seq here */
#define EVT_BUF   0x4000  /* page-aligned event payload, up to EVT_MAX */
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
	MemoryRegion container;
	MemoryRegion iomem;
	MemoryRegion evt_payload_ram;
	qemu_irq irq;
	int host_device_fd;
	uint8_t mem[MEM_SIZE];
	uint8_t *evt_payload;
	QemuThread evt_thread;
	QemuMutex evt_lock;
	QemuCond evt_cond;
	bool evt_thread_running;
	bool evt_acked;
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
//      0x3000  -- Event sequence/interface/size/ack control words
//      0x4000 \ Event payload (page-aligned RAM overlay)
//      0x4FFF /

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

/* Block on the host fd, publish one event, then wait for the guest ACK. */
static void *nvidia_dce_guest_evt_thread(void *opaque)
{
	NvidiaDceGuestState *s = opaque;
	struct dce_host_event_wire ev;

	while (!qatomic_read(&s->stopping)) {
		struct pollfd pfd = { .fd = s->host_device_fd, .events = POLLIN };
		ssize_t r;
		uint32_t iface, dsize;
		int n;

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
		memcpy(s->evt_payload, ev.data, dsize);
		memory_region_set_dirty(&s->evt_payload_ram, 0, dsize);
		*(uint32_t *)&s->mem[EVT_IFACE] = iface;
		*(uint32_t *)&s->mem[EVT_SIZ]   = dsize;
		/* Publish the sequence after payload and metadata. */
		smp_wmb();
		s->evt_seq++;
		*(uint32_t *)&s->mem[EVT_SEQ]   = s->evt_seq;	/* publish last */
		/* The BQL prevents a stale ACK while the new sequence is armed. */
		qemu_mutex_lock(&s->evt_lock);
		s->evt_acked = false;
		qemu_set_irq(s->irq, 1);
		qemu_mutex_unlock(&s->evt_lock);
		bql_unlock();

		qemu_mutex_lock(&s->evt_lock);
		while (!s->evt_acked && !qatomic_read(&s->stopping))
			qemu_cond_wait(&s->evt_cond, &s->evt_lock);
		qemu_mutex_unlock(&s->evt_lock);
	}

	return NULL;
}

static uint64_t nvidia_dce_guest_read(void *opaque, hwaddr addr,
				      unsigned int size)
{
	NvidiaDceGuestState *s = opaque;
	uint64_t val = 0;

	/* Bound the full access, not only its start address. */
	if (addr > MEM_SIZE - size)
		return 0xDEADBEEF;

	memcpy(&val, &s->mem[addr], size);
	return val;
}

static void nvidia_dce_guest_write(void *opaque, hwaddr addr, uint64_t data,
				   unsigned int size)
{
	NvidiaDceGuestState *s = opaque;
	struct dce_host_msg messg;
	int ret;

	memset(&messg, 0, sizeof(messg));

	/* Bound the full access, not only its start address. */
	if (addr > MEM_SIZE - size) {
		qemu_log_mask(LOG_UNIMP,
			      "nvidia_dce_guest: addr+size exceeds window at "
			      "0x%" HWADDR_PRIx "\n", addr);
		return;
	}

	switch (addr) {
	case EVT_ACK: {
		uint32_t ack;

		memcpy(&s->mem[addr], &data, size);
		memcpy(&ack, &s->mem[EVT_ACK], sizeof(ack));
		if (ack == s->evt_seq) {
			qemu_set_irq(s->irq, 0);
			qemu_mutex_lock(&s->evt_lock);
			s->evt_acked = true;
			qemu_cond_signal(&s->evt_cond);
			qemu_mutex_unlock(&s->evt_lock);
		}
		break;
	}

	case DOORBELL:
		memcpy(&messg.iface, &s->mem[IFACE], sizeof(messg.iface));
		messg.tx.data = &s->mem[TX_BUF];
		memcpy(&messg.tx.size, &s->mem[TX_SIZ],
		       sizeof(messg.tx.size));
		messg.rx.data = &s->mem[RX_BUF];
		memcpy(&messg.rx.size, &s->mem[RX_SIZ],
		       sizeof(messg.rx.size));

		ret = write(s->host_device_fd, &messg, sizeof(messg));
		if (ret < 0) {
			qemu_log_mask(LOG_UNIMP,
				      "%s: failed to write the host device\n",
				      __func__);
			return;
		}

		memcpy(&s->mem[RET_COD], &messg.ret, sizeof(messg.ret));
		memcpy(&s->mem[RX_SIZ], &messg.rx.size,
		       sizeof(messg.rx.size));
		break;

	default:
		memcpy(&s->mem[addr], &data, size);
	}
}

static const MemoryRegionOps nvidia_dce_guest_ops = {
	.read = nvidia_dce_guest_read,
	.write = nvidia_dce_guest_write,
	.endianness = DEVICE_NATIVE_ENDIAN,
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

	/* Keep controls in MMIO and overlay the aligned event payload with RAM. */
	memory_region_init(&s->container, obj, TYPE_NVIDIA_DCE_GUEST, MEM_SIZE);
	memory_region_init_io(&s->iomem, obj, &nvidia_dce_guest_ops, s,
			      TYPE_NVIDIA_DCE_GUEST ".io", MEM_SIZE);
	memory_region_add_subregion(&s->container, 0, &s->iomem);

	memory_region_init_ram(&s->evt_payload_ram, obj,
			       TYPE_NVIDIA_DCE_GUEST ".event-payload", EVT_MAX,
			       &error_fatal);
	s->evt_payload = memory_region_get_ram_ptr(&s->evt_payload_ram);
	memory_region_add_subregion_overlap(&s->container, EVT_BUF,
					    &s->evt_payload_ram, 1);

	sysbus_init_mmio(SYS_BUS_DEVICE(obj), &s->container);
	sysbus_init_irq(SYS_BUS_DEVICE(obj), &s->irq);
	qemu_mutex_init(&s->evt_lock);
	qemu_cond_init(&s->evt_cond);
	s->evt_acked = true;

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
		qemu_mutex_lock(&s->evt_lock);
		qemu_cond_broadcast(&s->evt_cond);
		qemu_mutex_unlock(&s->evt_lock);
		qemu_thread_join(&s->evt_thread);
		s->evt_thread_running = false;
	}
	qemu_set_irq(s->irq, 0);
	if (s->host_device_fd >= 0)
		close(s->host_device_fd);
	qemu_cond_destroy(&s->evt_cond);
	qemu_mutex_destroy(&s->evt_lock);
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

	/* The machine wires the reverse-event IRQ to the guest-DT SPI. */
	DeviceState *nvidia_dce_guest_create(hwaddr addr)
{
	DeviceState *dev = qdev_new(TYPE_NVIDIA_DCE_GUEST);
	sysbus_realize_and_unref(SYS_BUS_DEVICE(dev), &error_fatal);
	sysbus_mmio_map(SYS_BUS_DEVICE(dev), 0, addr);
	return dev;
}
