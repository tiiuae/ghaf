// SPDX-License-Identifier: GPL-2.0-only
/*
 * NVIDIA DCE Guest Proxy Kernel Module
 *
 * Redirects the guest DCE driver's synchronous client IPC through a shared
 * MMIO window ("dce-virtual-pa") to a QEMU bridge that relays it to the
 * host-owned DCE. Like bpmp-guest-proxy: one shared window per transaction
 * (pack request -> write triggers host forward -> read response), spinlock-
 * serialized. Builds INSIDE nvidia-oot to install tegra_dce_ipc_send_redirect,
 * exported by tegra-dce.
 *
 * (c) 2026 Vadim Likholetov
 */
#include <linux/module.h>
#include <linux/kernel.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/mod_devicetable.h>
#include <linux/io.h>
#include <linux/spinlock.h>
#include <linux/minmax.h>
#include <linux/string.h>
#include <linux/kthread.h>
#include <linux/delay.h>
#include <linux/debugfs.h>
#include <linux/platform/tegra/dce/dce-client-ipc.h>

#define DEVICE_NAME "dce-guest"

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Vadim Likholetov");
MODULE_DESCRIPTION("NVidia DCE Guest Proxy Kernel Module");
MODULE_VERSION("0.1");

/*
 * Shared DCE IPC frame layout -- must match the QEMU bridge and host proxy
 * exactly. DCE frames are opaque, up to 4 KB, so the window exceeds BPMP's.
 */
#define TX_BUF          0x0000  /* request payload  (msg->tx.data), <= 0x1000 */
#define RX_BUF          0x1000  /* response payload (msg->rx.data), <= 0x1000 */
#define TX_SIZ          0x2000  /* u64 tx size */
#define RX_SIZ          0x2008  /* u64 rx size (host writes actual length back) */
#define RET_COD         0x2010  /* s32 send_recv return code (host -> guest) */
#define IFACE           0x2018  /* u32 interface type (ch_type) */
#define DOORBELL        0x2100  /* covered by the bulk write; triggers QEMU */
#define FWD_SIZE        0x3000  /* forward window end; reverse window MUST sit
				 * above so a sync send never clobbers
				 * EVT_SEQ/EVT_ACK */

/*
 * Reverse (async) window -- must match nvidia_dce_guest.c. Above FWD_SIZE so
 * sync transactions leave it untouched. QEMU publishes DCE's unsolicited
 * ch_type=3 notifications here and bumps EVT_SEQ; we consume one per bump and
 * write the seq back to EVT_ACK.
 */
#define EVT_SEQ         0x3000  /* u32: bumped per published event */
#define EVT_IFACE       0x3004  /* u32: event interface type (ch_type) */
#define EVT_SIZ         0x3008  /* u32: event payload length */
#define EVT_ACK         0x300c  /* u32: we write the consumed seq here */
#define EVT_BUF         0x3010  /* event payload */
#define EVT_MAX         0x1000  /* max event payload */

#define DCE_MEM_SIZE    0x5000  /* total window (forward + reverse), ioremap size */
#define DCE_MAX_PAYLOAD 0x1000  /* max tx/rx payload (== TX_BUF/RX_BUF slot) */

static void __iomem *mem_iova;
static struct task_struct *dce_evt_task;
static struct dentry *dce_virt_dbg;

/*
 * Single shared window reused per transaction; concurrent sends must serialize.
 * Spinlock not mutex: DCE client IPC may run in atomic context.
 * ponytail: global lock + single window matches host/bridge single-slot design;
 * per-interface windows only if display throughput needs it.
 */
static DEFINE_SPINLOCK(dce_guest_xfer_lock);

/* Defined + exported by tegra-dce (dce-ipc.c) via the dce-virt-hooks patch. */
extern int (*tegra_dce_ipc_send_redirect)(u32 ch_type,
					  struct dce_ipc_message *msg);

static int my_dce_ipc_send(u32 ch_type, struct dce_ipc_message *msg)
{
	size_t org_rx_size = msg->rx.size;
	unsigned long flags;
	u64 rx_size;
	s32 ret;

	/* Payloads must fit their window slots (host applies the same bound). */
	if (msg->tx.size > DCE_MAX_PAYLOAD || msg->rx.size > DCE_MAX_PAYLOAD)
		return -EINVAL;

	spin_lock_irqsave(&dce_guest_xfer_lock, flags);

	/* Copy only the live payload, not the whole window: each MMIO word traps
	 * to QEMU (~µs), so a full-window copy costs ~10ms/RPC -- enough to hold
	 * the display RM lock and serialize event delivery at ~50Hz. Doorbell
	 * LAST: that write runs the host round-trip synchronously in QEMU. */
	if (msg->tx.data && msg->tx.size)
		memcpy_toio(mem_iova + TX_BUF, msg->tx.data, msg->tx.size);
	writeq(msg->tx.size, mem_iova + TX_SIZ);
	writeq(msg->rx.size, mem_iova + RX_SIZ);
	writel(ch_type, mem_iova + IFACE);
	writel(1, mem_iova + DOORBELL);

	ret = (s32)readl(mem_iova + RET_COD);
	rx_size = readq(mem_iova + RX_SIZ);

	/* Clamp the host-reported length to the caller's buffer capacity. */
	msg->rx.size = min_t(size_t, rx_size, org_rx_size);
	if (msg->rx.data && msg->rx.size)
		memcpy_fromio(msg->rx.data, mem_iova + RX_BUF, msg->rx.size);

	spin_unlock_irqrestore(&dce_guest_xfer_lock, flags);

	return ret;
}

/*
 * Reverse doorbell, guest end. QEMU publishes DCE's unsolicited ch_type=3
 * notifications (vblank, and the flip-completion nvidia-drm's atomic commit
 * blocks on) into the reverse window and bumps EVT_SEQ. Poll, consume each new
 * event, inject into tegra_dce so dce_client_async_event_work delivers it to
 * nvdisplay's async client callback -- the completion the guest modeset
 * otherwise never gets -- then ack.
 *
 * ponytail: poll loop, not a GIC IRQ. nvidia-drm's flip wait is 3s, so ~1ms
 * latency is irrelevant; wire an SPI only if a hot path needs it.
 */
static int dce_evt_poll_fn(void *arg)
{
	static u8 evbuf[EVT_MAX];	/* single kthread; off the 8K stack */
	u32 last_seq = 0;
	int ret;

	while (!kthread_should_stop()) {
		u32 seq = readl(mem_iova + EVT_SEQ);

		if (seq != last_seq) {
			u32 iface = readl(mem_iova + EVT_IFACE);
			u32 size  = readl(mem_iova + EVT_SIZ);

			if (size > EVT_MAX)
				size = EVT_MAX;
			memcpy_fromio(evbuf, mem_iova + EVT_BUF, size);

			/* pr_debug: the vblank stream makes this a ~100Hz path */
			pr_debug("dce_guest_proxy: EVENT seq=%u iface=%u size=%u\n",
				 seq, iface, size);

			/* Into tegra-dce's FIFO. ACK only on success: a full FIFO
			 * leaves EVT_ACK unchanged so the QEMU pump re-presents
			 * the slot -- opaque events are never dropped (Blocker 2). */
			ret = tegra_dce_client_ipc_inject(iface, size, evbuf);
			if (ret == -ENOSPC) {
				usleep_range(500, 1000);
				continue;	/* re-read same seq, do NOT ack */
			}
			if (ret == -ENOENT || ret == -EINVAL)
				pr_warn_ratelimited("dce_guest_proxy: event iface=%u dropped (ret=%d)\n",
						    iface, ret);

			last_seq = seq;
			writel(seq, mem_iova + EVT_ACK);	/* unblock next */
		}

		usleep_range(500, 1000);
	}

	return 0;
}

static int dce_guest_proxy_probe(struct platform_device *pdev)
{
	u64 vpa = 0;
	int ret;

	if (of_property_read_u64(pdev->dev.of_node, "dce-virtual-pa", &vpa) ||
	    !vpa) {
		dev_err(&pdev->dev, "missing/zero dce-virtual-pa\n");
		return -EINVAL;
	}

	mem_iova = ioremap(vpa, DCE_MEM_SIZE);
	if (!mem_iova) {
		dev_err(&pdev->dev, "ioremap(0x%llX) failed\n", vpa);
		return -ENOMEM;
	}

	dev_info(&pdev->dev, "dce-virtual-pa: 0x%llX -> %p\n", vpa, mem_iova);

	/* Ordered worker for the no-drop event FIFO. Start it BEFORE publishing
	 * the send redirect: a start failure must not leave a dangling
	 * tegra_dce_ipc_send_redirect pointing into the unmapped window. */
	ret = tegra_dce_virt_event_start();
	if (ret) {
		dev_err(&pdev->dev, "virt-event wq start failed: %d\n", ret);
		iounmap(mem_iova);
		mem_iova = NULL;
		return ret;
	}

	dce_virt_dbg = debugfs_create_dir("dce-virt", NULL);
	debugfs_create_atomic_t("enqueued",  0444, dce_virt_dbg, tegra_dce_virt_counter(0));
	debugfs_create_atomic_t("full",      0444, dce_virt_dbg, tegra_dce_virt_counter(1));
	debugfs_create_atomic_t("delivered", 0444, dce_virt_dbg, tegra_dce_virt_counter(2));
	debugfs_create_atomic_t("noclient",  0444, dce_virt_dbg, tegra_dce_virt_counter(3));

	/* Route every guest DCE send through the shared window -- only now the
	 * FIFO worker is live and cannot fail this probe. */
	tegra_dce_ipc_send_redirect = my_dce_ipc_send;

	/* Start draining the reverse window (async DCE notifications). */
	dce_evt_task = kthread_run(dce_evt_poll_fn, NULL, "dce-evt-poll");
	if (IS_ERR(dce_evt_task)) {
		dev_warn(&pdev->dev, "reverse-doorbell poll thread failed: %ld\n",
			 PTR_ERR(dce_evt_task));
		dce_evt_task = NULL;
	}

	return 0;
}

/* 6.12 guest kernel: platform_driver.remove is void since v6.11 (the host proxy
 * on the 6.6 L4T kernel still returns int). */
static void dce_guest_proxy_remove(struct platform_device *pdev)
{
	if (dce_evt_task) {
		kthread_stop(dce_evt_task);	/* no new injects after this */
		dce_evt_task = NULL;
	}
	debugfs_remove_recursive(dce_virt_dbg);
	dce_virt_dbg = NULL;
	tegra_dce_virt_event_stop();		/* flush + destroy the wq */
	tegra_dce_ipc_send_redirect = NULL;
	if (mem_iova) {
		iounmap(mem_iova);		/* only after the wq is gone */
		mem_iova = NULL;
	}
}

static const struct of_device_id dce_guest_proxy_ids[] = {
	{ .compatible = "nvidia,dce-guest-proxy" },
	{ }
};
MODULE_DEVICE_TABLE(of, dce_guest_proxy_ids);

static struct platform_driver dce_guest_proxy_driver = {
	.driver = {
		.name = "dce_guest_proxy",
		.of_match_table = dce_guest_proxy_ids,
	},
	.probe = dce_guest_proxy_probe,
	.remove = dce_guest_proxy_remove,
};
/* Loadable .ko inside nvidia-oot: needs module init, not device_initcall. */
module_platform_driver(dce_guest_proxy_driver);
