// SPDX-License-Identifier: GPL-2.0-only
// dce-host-proxy: relays a guest's DCE display IPC to the host-owned DCE via
// tegra-dce's CPU_RM client interface. Char-device scaffold and bounce-buffer
// hygiene mirror bpmp-host-proxy.c.
#include <linux/module.h>
#include <linux/device.h>
#include <linux/kernel.h>
#include <linux/fs.h>
#include <linux/uaccess.h>
#include <linux/slab.h>
#include <linux/mutex.h>
#include <linux/platform_device.h>
#include <linux/of.h>
#include <linux/mod_devicetable.h>	  // struct of_device_id (full definition)
#include <linux/poll.h>
#include <linux/sched.h>
#include <linux/spinlock.h>
#include <linux/wait.h>
#include <linux/platform/tegra/dce/dce-client-ipc.h>
#include "dce-host-proxy.h"

#define DEVICE_NAME "dce-host"
#define CLASS_NAME  "dce_chardrv" // distinct from bpmp-host-proxy's "chardrv"
				  // so both can coexist in one kernel without a
				  // duplicate sysfs class.

MODULE_LICENSE("GPL");
MODULE_AUTHOR("Vadim Likholetov");
MODULE_DESCRIPTION("NVidia DCE Host Proxy Kernel Module");
MODULE_VERSION("0.1");


#define DCE_HOST_VERBOSE    0

#if DCE_HOST_VERBOSE
#define deb_info(...)     printk(KERN_INFO DEVICE_NAME ": "__VA_ARGS__)
#else
#define deb_info(...)
#endif

#define deb_error(...)    printk(KERN_ALERT DEVICE_NAME ": "__VA_ARGS__)
#define deb_warn(...)     printk(KERN_WARNING DEVICE_NAME ": "__VA_ARGS__)

static int major_number;

static struct class *dce_host_proxy_class = NULL;
static struct device *dce_host_proxy_device = NULL;

// CPU_RM IPC client, registered lazily on first write() under
// dce_host_client_lock, torn down in remove().
static DEFINE_MUTEX(dce_host_client_lock);
static u32 dce_host_client_handle;
static bool dce_host_client_registered;

/*
 * Reverse doorbell, host end. DCE pushes unsolicited notifications (RM_NOTIFY --
 * vblank, and the flip-completion event nvidia-drm's atomic commit blocks on) to
 * whoever registered the RM_EVENT client; with nobody registered tegra-dce drops
 * them ("Failed to retrieve client info for ch_type: [3]") and the guest's
 * modeset times out. So register RM_EVENT and drain its callback through a small
 * ring: read() pops one event, poll() reports readable.
 */
static DEFINE_MUTEX(dce_host_event_client_lock);
static u32 dce_host_event_handle;
static bool dce_host_event_registered;

#define DCE_EVT_SLOTS 8

static struct dce_host_event *dce_evt_ring;
static unsigned int dce_evt_head, dce_evt_tail;	 /* head==tail => empty */
static DEFINE_SPINLOCK(dce_evt_lock);
static DECLARE_WAIT_QUEUE_HEAD(dce_evt_wq);
static unsigned long dce_evt_dropped;
static unsigned long dce_evt_count;

static bool dce_evt_pending(void)
{
	bool pending;
	unsigned long flags;

	spin_lock_irqsave(&dce_evt_lock, flags);
	pending = dce_evt_head != dce_evt_tail;
	spin_unlock_irqrestore(&dce_evt_lock, flags);

	return pending;
}

/* File-operation prototypes. */
static int open(struct inode *, struct file *);
static int close(struct inode *, struct file *);
static ssize_t read(struct file *, char *, size_t, loff_t *);
static ssize_t write(struct file *, const char *, size_t, loff_t *);
static __poll_t dce_host_poll(struct file *, struct poll_table_struct *);

static struct file_operations fops =
	{
		.owner = THIS_MODULE,
		.open = open,
		.release = close,
		.read = read,
		.write = write,
		.poll = dce_host_poll,
};

/*
 * Queue one DCE notification for the bridge. Called from tegra-dce's IPC
 * callback, which may run in atomic context, so must not sleep. When full the
 * ring drops the oldest rather than block DCE's notify channel; drops are
 * counted/warned because a lost flip completion hangs a guest modeset.
 */
static void dce_host_proxy_queue_event(u32 interface_type, u32 msg_length,
				       void *msg_data)
{
	struct dce_host_event *e;
	unsigned long flags;
	unsigned int next;

	if (msg_length > DCE_HOST_EVENT_MAX_DATA)
		msg_length = DCE_HOST_EVENT_MAX_DATA;

	spin_lock_irqsave(&dce_evt_lock, flags);

	if (!dce_evt_ring) {
		spin_unlock_irqrestore(&dce_evt_lock, flags);
		return;
	}

	next = (dce_evt_head + 1) % DCE_EVT_SLOTS;
	if (next == dce_evt_tail) {
		/* Full: drop the oldest so the newest (most relevant) survives. */
		dce_evt_tail = (dce_evt_tail + 1) % DCE_EVT_SLOTS;
		dce_evt_dropped++;
	}

	e = &dce_evt_ring[dce_evt_head];
	e->iface = interface_type;
	e->size = msg_length;
	if (msg_length && msg_data)
		memcpy(e->data, msg_data, msg_length);

	dce_evt_head = next;
	dce_evt_count++;

	spin_unlock_irqrestore(&dce_evt_lock, flags);

	// First few only: confirm async notifications arrive once RM_EVENT is
	// claimed, without spamming the log at vblank rate.
	if (dce_evt_count <= 4)
		pr_info("dce_host_proxy: EVENT #%lu iface=%u len=%u\n",
			dce_evt_count, interface_type, msg_length);

	wake_up_interruptible(&dce_evt_wq);
}

/* CPU_RM client callback: DCE unsolicited notification on the sync interface. */
static void dce_host_proxy_ipc_cb(u32 handle, u32 interface_type,
				   u32 msg_length, void *msg_data,
				   void *usr_ctx)
{
	deb_info("cpu_rm notify: handle=%u iface=%u len=%u\n",
		 handle, interface_type, msg_length);

	dce_host_proxy_queue_event(interface_type, msg_length, msg_data);
}

/* RM_EVENT client callback: DCE's async notify channel; carries flip completion. */
static void dce_host_proxy_event_cb(u32 handle, u32 interface_type,
				    u32 msg_length, void *msg_data,
				    void *usr_ctx)
{
	dce_host_proxy_queue_event(interface_type, msg_length, msg_data);
}

static int dce_host_proxy_probe(struct platform_device *pdev)
{
	deb_info("%s, installing module.", __func__);

	// Event ring allocated up front: the DCE callback can fire in atomic
	// context as soon as RM_EVENT is registered and must never allocate.
	dce_evt_ring = kcalloc(DCE_EVT_SLOTS, sizeof(*dce_evt_ring), GFP_KERNEL);
	if (!dce_evt_ring)
		return -ENOMEM;

	major_number = register_chrdev(0, DEVICE_NAME, &fops);
	if (major_number < 0)
	{
		deb_error("could not register number.\n");
		kfree(dce_evt_ring);
		dce_evt_ring = NULL;
		return major_number;
	}
	deb_info("registered correctly with major number %d\n", major_number);

	dce_host_proxy_class = class_create(CLASS_NAME);
	if (IS_ERR(dce_host_proxy_class))
	{
		unregister_chrdev(major_number, DEVICE_NAME);
		deb_error("Failed to register device class\n");
		return PTR_ERR(dce_host_proxy_class);
	}
	deb_info("device class registered correctly\n");

	dce_host_proxy_device = device_create(dce_host_proxy_class, NULL, MKDEV(major_number, 0), NULL, DEVICE_NAME);
	if (IS_ERR(dce_host_proxy_device))
	{
		class_destroy(dce_host_proxy_class);
		unregister_chrdev(major_number, DEVICE_NAME);
		deb_error("Failed to create the device\n");
		return PTR_ERR(dce_host_proxy_device);
	}

	deb_info("device class created correctly\n");

	return 0;
}



static int dce_host_proxy_remove(struct platform_device *pdev)
{
	deb_info("removing module.\n");

	mutex_lock(&dce_host_client_lock);
	if (dce_host_client_registered) {
		tegra_dce_unregister_ipc_client(dce_host_client_handle);
		dce_host_client_registered = false;
	}
	mutex_unlock(&dce_host_client_lock);

	mutex_lock(&dce_host_event_client_lock);
	if (dce_host_event_registered) {
		tegra_dce_unregister_ipc_client(dce_host_event_handle);
		dce_host_event_registered = false;
	}
	mutex_unlock(&dce_host_event_client_lock);

	// Both clients gone: no callback can queue any more, safe to free the
	// ring. Wake any reader blocked in read() first.
	wake_up_interruptible(&dce_evt_wq);
	kfree(dce_evt_ring);
	dce_evt_ring = NULL;

	if (dce_evt_dropped)
		deb_warn("dropped %lu DCE notification(s) -- ring too small or bridge too slow\n",
			 dce_evt_dropped);

	device_destroy(dce_host_proxy_class, MKDEV(major_number, 0));
	class_unregister(dce_host_proxy_class);
	class_destroy(dce_host_proxy_class);
	unregister_chrdev(major_number, DEVICE_NAME);
	deb_info("Goodbye from the LKM!\n");
	return 0;
}

static int open(struct inode *inodep, struct file *filep)
{
	deb_info("device opened.\n");
	return 0;
}

static int close(struct inode *inodep, struct file *filep)
{
	deb_info("device closed.\n");
	return 0;
}

/*
 * Reverse doorbell: pop one queued DCE notification. Each read returns exactly
 * one event (never partial or coalesced), so the reader never has to frame them.
 */
static ssize_t read(struct file *filep, char *buffer, size_t len, loff_t *offset)
{
	struct dce_host_event *e;
	unsigned long flags;
	unsigned int slot;
	size_t copy;
	int ret;

	if (len < sizeof(struct dce_host_event))
		return -EINVAL;

	if (!dce_evt_pending()) {
		if (filep->f_flags & O_NONBLOCK)
			return -EAGAIN;

		ret = wait_event_interruptible(dce_evt_wq, dce_evt_pending());
		if (ret)
			return ret;
	}

	e = kmalloc(sizeof(*e), GFP_KERNEL);
	if (!e)
		return -ENOMEM;

	spin_lock_irqsave(&dce_evt_lock, flags);
	if (dce_evt_head == dce_evt_tail) {
		/* Raced with another reader. */
		spin_unlock_irqrestore(&dce_evt_lock, flags);
		kfree(e);
		return -EAGAIN;
	}
	/* Peek, don't pop: advance the tail only after copy_to_user succeeds,
	 * else a failed copy loses the event (seen as a replug's plug half never
	 * reaching the guest). Remember the slot so the pop below can tell whether
	 * the producer's full-ring drop moved the tail during the copy window. */
	slot = dce_evt_tail;
	*e = dce_evt_ring[slot];
	spin_unlock_irqrestore(&dce_evt_lock, flags);

	/* Header plus only the bytes this event carries. */
	copy = offsetof(struct dce_host_event, data) + e->size;
	if (copy_to_user(buffer, e, copy)) {
		pr_warn_ratelimited("dce_host_proxy: event copy_to_user failed (len=%zu copy=%zu), event retained\n",
				    len, copy);
		kfree(e);
		return -EFAULT;
	}

	/* Advance only if the tail still points at the slot we delivered. If the
	 * producer's full-ring drop already moved it past our slot, the tail is
	 * correct as-is and a blind advance would skip an undelivered event. */
	spin_lock_irqsave(&dce_evt_lock, flags);
	if (dce_evt_tail == slot)
		dce_evt_tail = (slot + 1) % DCE_EVT_SLOTS;
	spin_unlock_irqrestore(&dce_evt_lock, flags);

	kfree(e);

	return copy;
}

static __poll_t dce_host_poll(struct file *filep, struct poll_table_struct *wait)
{
	poll_wait(filep, &dce_evt_wq, wait);

	return dce_evt_pending() ? (EPOLLIN | EPOLLRDNORM) : 0;
}

/*
 * Register the CPU_RM IPC client lazily on first use. Safe to call on every
 * write(); a no-op once registered.
 */
static int dce_host_proxy_ensure_client(void)
{
	int ret = 0;

	mutex_lock(&dce_host_client_lock);
	if (!dce_host_client_registered) {
		ret = tegra_dce_register_ipc_client(DCE_CLIENT_IPC_TYPE_CPU_RM,
						     dce_host_proxy_ipc_cb, NULL,
						     &dce_host_client_handle);
		if (ret) {
			pr_err("dce_host_proxy: CPU_RM registration failed: %d\n", ret);
		} else {
			dce_host_client_registered = true;
			pr_info("dce_host_proxy: registered CPU_RM client, handle=%u\n",
				 dce_host_client_handle);
		}
	}
	mutex_unlock(&dce_host_client_lock);

	return ret;
}

/*
 * Register the RM_EVENT client (DCE's async notify channel) lazily. Nobody else
 * claims it, so tegra-dce otherwise logs "Failed to retrieve client info for
 * ch_type: [3]" and drops the notifications. Failure only costs async events,
 * not the sync relay, so it warns rather than failing write().
 */
static void dce_host_proxy_ensure_event_client(void)
{
	int ret;

	mutex_lock(&dce_host_event_client_lock);
	if (!dce_host_event_registered) {
		ret = tegra_dce_register_ipc_client(DCE_CLIENT_IPC_TYPE_RM_EVENT,
						    dce_host_proxy_event_cb, NULL,
						    &dce_host_event_handle);
		if (ret) {
			deb_warn("RM_EVENT registration failed: %d (async events, incl. flip completion, will not reach the guest)\n",
				 ret);
		} else {
			dce_host_event_registered = true;
			pr_info("dce_host_proxy: registered RM_EVENT client, handle=%u\n",
				dce_host_event_handle);
		}
	}
	mutex_unlock(&dce_host_event_client_lock);
}

#define BUF_SIZE DCE_CLIENT_MAX_IPC_MSG_SIZE

static ssize_t write(struct file *filep, const char *buffer, size_t len, loff_t *offset)
{

	int ret = len;
	struct dce_host_msg *kbuf = NULL;
	void *txbuf = NULL;
	void *rxbuf = NULL;
	void *usertxbuf = NULL;
	void *userrxbuf = NULL;
	struct dce_ipc_message m;

	if (len > 65535) {	/* paranoia */
		deb_error("count %zu exceeds max # of bytes allowed, "
			"aborting write\n", len);
		goto out_nomem;
	}

	ret = -ENOMEM;
	kbuf = kmalloc(len, GFP_KERNEL);


	if (!kbuf)
		goto out_nomem;

	memset(kbuf, 0, len);

	ret = -EFAULT;

	if (copy_from_user(kbuf, buffer, len)) {
		deb_error("copy_from_user(1) failed\n");
		goto out_cfu;
	}

	deb_info("\nwants to write %zu bytes, with iface: %u\n", len, kbuf->iface);

	// Reject tx/rx sizes over BUF_SIZE: a malicious guest could otherwise
	// overflow the host slab bounce buffers below. DCE messages are bounded
	// by DCE_CLIENT_MAX_IPC_MSG_SIZE.
	if (kbuf->tx.size > BUF_SIZE || kbuf->rx.size > BUF_SIZE) {
		deb_error("tx.size %zu / rx.size %zu exceeds %d, rejecting\n",
			  kbuf->tx.size, kbuf->rx.size, BUF_SIZE);
		goto out_cfu;
	}

	if(kbuf->tx.size > 0){
		txbuf = kmalloc(BUF_SIZE, GFP_KERNEL);
		if (!txbuf)
			goto out_nomem;
		memset(txbuf, 0, BUF_SIZE);
		if (copy_from_user(txbuf, kbuf->tx.data, kbuf->tx.size)) {
			deb_error("copy_from_user(2) failed\n");
			goto out_cfu;
		}
	}

	rxbuf = kmalloc(BUF_SIZE, GFP_KERNEL);
	if (!rxbuf)
		goto out_nomem;

	memset(rxbuf, 0, BUF_SIZE);
	if (copy_from_user(rxbuf, kbuf->rx.data, kbuf->rx.size)) {
		deb_error("copy_from_user(3) failed\n");
		goto out_cfu;
	}


	usertxbuf = (void*)kbuf->tx.data; // save userspace addresses
	userrxbuf = kbuf->rx.data;


	kbuf->tx.data = txbuf; // reassign to kernel-space buffers
	kbuf->rx.data = rxbuf;

	ret = dce_host_proxy_ensure_client();
	if (ret) {
		deb_error("no CPU_RM client available, can't do transfer!\n");
		goto out_cfu;
	}

	// Claim the async notify channel so its events (vblank, flip completion)
	// reach us instead of being dropped. Best-effort; sync relay works without it.
	dce_host_proxy_ensure_event_client();

	m.tx.data = txbuf;
	m.tx.size = kbuf->tx.size;
	m.rx.data = rxbuf;
	m.rx.size = kbuf->rx.size;

	ret = tegra_dce_client_ipc_send_recv(dce_host_client_handle, &m);
	kbuf->ret = ret;
	/* Clamp DCE's reported rx length to the capacity we handed it (bounded to
	 * BUF_SIZE above): a corrupted DCE reporting more would drive an OOB read
	 * of the bounce buffer and an oversized copy_to_user into QEMU. */
	kbuf->rx.size = min_t(size_t, m.rx.size, kbuf->rx.size);   /* actual received length */

	if (copy_to_user((void *)usertxbuf, kbuf->tx.data, kbuf->tx.size)) {
		deb_error("copy_to_user(2) failed\n");
		goto out_notok;
	}

	if (copy_to_user((void *)userrxbuf, kbuf->rx.data, kbuf->rx.size)) {
		deb_error("copy_to_user(3) failed\n");
		goto out_notok;
	}

	kbuf->tx.data=usertxbuf;
	kbuf->rx.data=userrxbuf;

	if (copy_to_user((void *)buffer, kbuf, len)) {
		deb_error("copy_to_user(1) failed\n");
		goto out_notok;
	}



	kfree(kbuf);
	kfree(txbuf);
	kfree(rxbuf);
	return len;
out_notok:
out_nomem:
	deb_error("memory allocation failed");
out_cfu:
	kfree(kbuf);
	kfree(txbuf);
	kfree(rxbuf);
    return -EINVAL;

}

static const struct of_device_id dce_host_proxy_ids[] = {
	{ .compatible = "nvidia,dce-host-proxy" },
	{ }
};
MODULE_DEVICE_TABLE(of, dce_host_proxy_ids);

static struct platform_driver dce_host_proxy_driver = {
	.driver = {
		.name = "dce_host_proxy",
		.of_match_table = dce_host_proxy_ids,
	},
	.probe = dce_host_proxy_probe,
	.remove = dce_host_proxy_remove,
};
/* Loadable .ko inside nvidia-oot (links its DCE client IPC symbols), so it
 * registers via module init/exit -- builtin_platform_driver's device_initcall
 * never runs on insmod. */
module_platform_driver(dce_host_proxy_driver);
