#include "qemu/osdep.h"
#include "qemu/log.h"
#include "qapi/error.h" /* provides error_fatal() handler */
#include "hw/sysbus.h"	/* provides all sysbus registering func */
#include "hw/misc/nvidia_bpmp_guest.h"

#define TYPE_NVIDIA_BPMP_GUEST "nvidia_bpmp_guest"
typedef struct NvidiaBpmpGuestState NvidiaBpmpGuestState;
DECLARE_INSTANCE_CHECKER(NvidiaBpmpGuestState, NVIDIA_BPMP_GUEST, TYPE_NVIDIA_BPMP_GUEST)

#define TX_BUF   0x0000
#define RX_BUF   0x0200
#define TX_SIZ   0x0400
#define RX_SIZ   0x0408
#define RET_COD  0x0410
#define MRQ      0x0500

#define MEM_SIZE 0x600
#define HOST_DEVICE_PATH "/dev/bpmp-host"
#define MESSAGE_SIZE 0x0200

// qemu_log_mask(LOG_UNIMP, "%s: \n", __func__ );

struct NvidiaBpmpGuestState
{
	SysBusDevice parent_obj;
	MemoryRegion iomem;
	int host_device_fd;
	uint8_t mem[MEM_SIZE];
};

// Device memory map:

// 0x090d0000 +  /* Base address, size 0x01000 */

//      0x0000 \ Tx buffer
//      0x01FF /
//      0x0200 \ Rx buffer
//      0x03FF /
//      0x0400  -- Tx size
//      0x0408  -- Rx size
//      0x0410  -- Ret
//      0x0500  -- mrq



//  Data should be aligned to 64bit paragraph.

//  Protocol is:
//  1. Write data buffers to 0x0000-0x01FF and 0x0200-0x03FF
//  2. Write buffer sizes to 0x0400 (Tx) and 0x0408 (Rx)
//  2. Start operation by writing mrq opcode to address 0x0500
//  3. Read ret code from 0x0410 and response data from the buffers

static uint64_t nvidia_bpmp_guest_read(void *opaque, hwaddr addr, unsigned int size)
{
	NvidiaBpmpGuestState *s = opaque;

	if (addr >= MEM_SIZE)
		return 0xDEADBEEF;

	// Cast buffer location as uint64_t
	return *(uint64_t*)&s->mem[addr];
}

static void nvidia_bpmp_guest_write(void *opaque, hwaddr addr, uint64_t data, unsigned int size)
{
	NvidiaBpmpGuestState *s = opaque;
	int ret;

	struct
	{
		unsigned int mrq;
		struct
		{
			void *data;
			size_t size;
		} tx;
		struct
		{
			void *data;
			size_t size;
			int ret;
		} rx;
	} messg;

	memset(&messg, 0, sizeof(messg));

	if (addr >= MEM_SIZE){
		qemu_log_mask(LOG_UNIMP, "qemu: Error addr >= MEM_SIZE in 0x%lX data: 0x%lX\n", addr, data);
		return;
	}

	switch (addr)
	{
	case MRQ:
		// set up the structure
		messg.mrq = data;
		messg.tx.data = &s->mem[TX_BUF];
		memcpy(&messg.tx.size, &s->mem[TX_SIZ], sizeof(messg.tx.size));
		messg.rx.data = &s->mem[RX_BUF];
		memcpy(&messg.rx.size, &s->mem[RX_SIZ], sizeof(messg.rx.size));

		ret = write(s->host_device_fd, &messg, sizeof(messg)); // Send the data to the host module
		if (ret < 0)
		{
			qemu_log_mask(LOG_UNIMP, "%s: Failed to write the host device..\n", __func__);
			return;
		}

		memcpy(&s->mem[RET_COD], &messg.rx.ret, sizeof(messg.rx.ret));
		memcpy(&s->mem[RX_SIZ], &messg.rx.size, sizeof(messg.rx.size));

		break;

	default:

		memcpy(&s->mem[addr], &data, size);
	}

	return;
}

static const MemoryRegionOps nvidia_bpmp_guest_ops = {
	.read = nvidia_bpmp_guest_read,
	.write = nvidia_bpmp_guest_write,
	.endianness = DEVICE_NATIVE_ENDIAN,
};

static void nvidia_bpmp_guest_instance_init(Object *obj)
{
	NvidiaBpmpGuestState *s = NVIDIA_BPMP_GUEST(obj);

	/* allocate memory map region */
	memory_region_init_io(&s->iomem, obj, &nvidia_bpmp_guest_ops, s, TYPE_NVIDIA_BPMP_GUEST, MEM_SIZE);
	sysbus_init_mmio(SYS_BUS_DEVICE(obj), &s->iomem);

	s->host_device_fd = open(HOST_DEVICE_PATH, O_RDWR); // Open the device with read/write access

	if (s->host_device_fd < 0)
	{
		qemu_log_mask(LOG_UNIMP, "%s: Failed to open the host device..\n", __func__);
		return;
	}
}

/* create a new type to define the info related to our device */
static const TypeInfo nvidia_bpmp_guest_info = {
	.name = TYPE_NVIDIA_BPMP_GUEST,
	.parent = TYPE_SYS_BUS_DEVICE,
	.instance_size = sizeof(NvidiaBpmpGuestState),
	.instance_init = nvidia_bpmp_guest_instance_init,
};

static void nvidia_bpmp_guest_register_types(void)
{
	type_register_static(&nvidia_bpmp_guest_info);
}

type_init(nvidia_bpmp_guest_register_types)

	/*
	 * Create the Nvidia BPMP guest device.
	 */
	DeviceState *nvidia_bpmp_guest_create(hwaddr addr)
{
	DeviceState *dev = qdev_new(TYPE_NVIDIA_BPMP_GUEST);
	sysbus_realize_and_unref(SYS_BUS_DEVICE(dev), &error_fatal);
	sysbus_mmio_map(SYS_BUS_DEVICE(dev), 0, addr);
	return dev;
}
