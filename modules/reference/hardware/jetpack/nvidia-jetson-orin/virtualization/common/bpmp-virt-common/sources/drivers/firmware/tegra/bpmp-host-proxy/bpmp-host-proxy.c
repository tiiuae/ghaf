/**
 * 
 * NVIDIA BPMP Host Proxy Kernel Module
 * (c) 2023 Unikie, Oy
 * (c) 2023 Vadim Likholetov vadim.likholetov@unikie.com
 * 
*/
#include <linux/module.h>	  // Core header for modules.
#include <linux/device.h>	  // Supports driver model.
#include <linux/kernel.h>	  // Kernel header for convenient functions.
#include <linux/fs.h>		  // File-system support.
#include <linux/uaccess.h>	  // User access copy function support.
#include <linux/slab.h>
#include <soc/tegra/bpmp.h>
#include <linux/platform_device.h>
#include "bpmp-host-proxy.h"


#define DEVICE_NAME "bpmp-host"   // Device name.
#define CLASS_NAME  "chardrv"	  // < The device class -- this is a character device driver

MODULE_LICENSE("GPL");						 ///< The license type -- this affects available functionality
MODULE_AUTHOR("Vadim Likholetov");					 ///< The author -- visible when you use modinfo
MODULE_DESCRIPTION("NVidia BPMP Host Proxy Kernel Module"); ///< The description -- see modinfo
MODULE_VERSION("0.1");						 ///< A version number to inform users


#define BPMP_HOST_VERBOSE    0

/**
 * Put this flag in 0 in order that the BPMP host proxy only allows
 * the allowed BPMP resources to be used by the VMs.
 * 
 * Put this flag in 1 in order that the BPMP host proxy allows
 * all the BPMP resources to be accessible by the virtual machines.
 * This option is useful for debugging, but is INSECURE, and it could
 * stop the host. To avoid stop the host use 
 * "clk_ignore_unused pd_ignore_unused" in kernel command line
 * 
*/
#define BPMP_HOST_ALLOWS_ALL   0

#if BPMP_HOST_VERBOSE
#define deb_info(...)     printk(KERN_INFO DEVICE_NAME ": "__VA_ARGS__)
#else
#define deb_info(...)
#endif

#define deb_error(...)    printk(KERN_ALERT DEVICE_NAME ": "__VA_ARGS__)
#define deb_warn(...)     printk(KERN_WARNING DEVICE_NAME ": "__VA_ARGS__)

/**
 * Important variables that store data and keep track of relevant information.
 */
static int major_number;

static struct class *bpmp_host_proxy_class = NULL;	///< The device-driver class struct pointer
static struct device *bpmp_host_proxy_device = NULL; ///< The device-driver device struct pointer

/**
 * Prototype functions for file operations.
 */
static int open(struct inode *, struct file *);
static int close(struct inode *, struct file *);
static ssize_t read(struct file *, char *, size_t, loff_t *);
static ssize_t write(struct file *, const char *, size_t, loff_t *);

/**
 * File operations structure and the functions it points to.
 */
static struct file_operations fops =
	{
		.owner = THIS_MODULE,
		.open = open,
		.release = close,
		.read = read,
		.write = write,
};

// BPMP allowed resources structure
static struct bpmp_allowed_res bpmp_ares; 

#if BPMP_HOST_VERBOSE
// Usage:
//     hexDump(desc, addr, len, perLine);
//         desc:    if non-NULL, printed as a description before hex dump.
//         addr:    the address to start dumping from.
//         len:     the number of bytes to dump.
//         perLine: number of bytes on each output line.
void static hexDump (
    const char * desc,
    const void * addr,
    const int len
) {
    // Silently ignore silly per-line values.

    int i;
    unsigned char buff[17];
	unsigned char out_buff[4000];
	unsigned char *p_out_buff = out_buff;
    const unsigned char * pc = (const unsigned char *)addr;



    // Output description if given.

    if (desc != NULL) printk ("%s:\n", desc);

    // Length checks.

    if (len == 0) {
        printk(DEVICE_NAME ":   ZERO LENGTH\n");
        return;
    }
    if (len < 0) {
        printk(DEVICE_NAME ":   NEGATIVE LENGTH: %d\n", len);
        return;
    }

	if(len > 400){
        printk(DEVICE_NAME ":   VERY LONG: %d\n", len);
        return;
    }

    // Process every byte in the data.

    for (i = 0; i < len; i++) {
        // Multiple of perLine means new or first line (with line offset).

        if ((i % 16) == 0) {
            // Only print previous-line ASCII buffer for lines beyond first.

            if (i != 0) {
				p_out_buff += sprintf (p_out_buff, "  %s\n", buff);
			}
            // Output the offset of current line.

            p_out_buff += sprintf (p_out_buff,"  %04x ", i);
        }

        // Now the hex code for the specific character.

        p_out_buff += sprintf (p_out_buff, " %02x", pc[i]);

        // And buffer a printable ASCII character for later.

        if ((pc[i] < 0x20) || (pc[i] > 0x7e)) // isprint() may be better.
            buff[i % 16] = '.';
        else
            buff[i % 16] = pc[i];
        buff[(i % 16) + 1] = '\0';
    }

    // Pad out last line if not exactly perLine characters.

    while ((i % 16) != 0) {
        p_out_buff += sprintf (p_out_buff, "   ");
        i++;
    }

    // And print the final ASCII buffer.

    p_out_buff += sprintf (p_out_buff, "  %s\n", buff);

	printk(DEVICE_NAME ": %s", out_buff);
}
#else
	#define hexDump(...)
#endif

/**
 * Initializes module at installation
 */
static int bpmp_host_proxy_probe(struct platform_device *pdev)
{
	int i;
	
	deb_info("%s, installing module.", __func__);

	// Read allowed clocks and resets from the device tree
	// if they are defined or BPMP_HOST_ALLOWS_ALL continue
	bpmp_ares.clocks_size = of_property_read_variable_u32_array(pdev->dev.of_node, 
		"allowed-clocks", bpmp_ares.clock, 0, BPMP_HOST_MAX_CLOCKS_SIZE);

	if(!bpmp_ares.clocks_size && !BPMP_HOST_ALLOWS_ALL){
		deb_error("No allowed clocks defined");
		return EINVAL;
	}

	deb_info("bpmp_ares.clocks_size: %d", bpmp_ares.clocks_size);
	for (i = 0; i < bpmp_ares.clocks_size; i++)	{
		deb_info("bpmp_ares.clock %d", bpmp_ares.clock[i]);
	}

	bpmp_ares.resets_size = of_property_read_variable_u32_array(pdev->dev.of_node, 
		"allowed-resets", bpmp_ares.reset, 0, BPMP_HOST_MAX_RESETS_SIZE);

	if(!bpmp_ares.resets_size && !BPMP_HOST_ALLOWS_ALL){
		deb_error("No allowed resets defined");
		return EINVAL;
	}

	deb_info("bpmp_ares.resets_size: %d", bpmp_ares.resets_size);
	for (i = 0; i < bpmp_ares.resets_size; i++)	{
		deb_info("bpmp_ares.reset %d", bpmp_ares.reset[i]);
	}


	// Read allowed power domains from the device tree
	bpmp_ares.pd_size = of_property_read_variable_u32_array(pdev->dev.of_node, 
		"allowed-power-domains", bpmp_ares.pd, 0, BPMP_HOST_MAX_POWER_DOMAINS_SIZE);

	deb_info("bpmp_ares.pd_size: %d", bpmp_ares.pd_size);
	for (i = 0; i < bpmp_ares.pd_size; i++)	{
		deb_info("bpmp_ares.pd %d", bpmp_ares.pd[i]);
	}

	// Allocate a major number for the device.
	major_number = register_chrdev(0, DEVICE_NAME, &fops);
	if (major_number < 0)
	{
		deb_error("could not register number.\n");
		return major_number;
	}
	deb_info("registered correctly with major number %d\n", major_number);

	// Register the device class
	bpmp_host_proxy_class = class_create(CLASS_NAME);
	if (IS_ERR(bpmp_host_proxy_class))
	{ // Check for error and clean up if there is
		unregister_chrdev(major_number, DEVICE_NAME);
		deb_error("Failed to register device class\n");
		return PTR_ERR(bpmp_host_proxy_class); // Correct way to return an error on a pointer
	}
	deb_info("device class registered correctly\n");

	// Register the device driver
	bpmp_host_proxy_device = device_create(bpmp_host_proxy_class, NULL, MKDEV(major_number, 0), NULL, DEVICE_NAME);
	if (IS_ERR(bpmp_host_proxy_device))
	{								 // Clean up if there is an error
		class_destroy(bpmp_host_proxy_class); 
		unregister_chrdev(major_number, DEVICE_NAME);
		deb_error("Failed to create the device\n");
		return PTR_ERR(bpmp_host_proxy_device);
	}

	deb_info("device class created correctly\n"); // Made it! device was initialized

	return 0;
}



/*
 * Removes module, sends appropriate message to kernel
 */
static int bpmp_host_proxy_remove(struct platform_device *pdev)
{
	deb_info("removing module.\n");
	device_destroy(bpmp_host_proxy_class, MKDEV(major_number, 0)); // remove the device
	class_unregister(bpmp_host_proxy_class);						  // unregister the device class
	class_destroy(bpmp_host_proxy_class);						  // remove the device class
	unregister_chrdev(major_number, DEVICE_NAME);		  // unregister the major number
	deb_info("Goodbye from the LKM!\n");
	unregister_chrdev(major_number, DEVICE_NAME);
	return 0;
}

/*
 * Opens device module, sends appropriate message to kernel
 */
static int open(struct inode *inodep, struct file *filep)
{
	deb_info("device opened.\n");
	return 0;
}

/*
 * Closes device module, sends appropriate message to kernel
 */
static int close(struct inode *inodep, struct file *filep)
{
	deb_info("device closed.\n");
	return 0;
}

/*
 * Reads from device, displays in userspace, and deletes the read data
 */
static ssize_t read(struct file *filep, char *buffer, size_t len, loff_t *offset)
{
	deb_info("read stub");
	return 0;
}

/*
 * Checks if the msg that wants to transmit through the
 * bpmp-host is allowed by the device tree configuration
 */
/*
 * Host-critical shared clock roots the host TCB depends on (always-on). The
 * guest's display clock tree parents up to these, so they must be allow-listed
 * -- but MRQ_CLK is gated by id, not command, so a guest could otherwise
 * DISABLE/reparent/rerate them and destabilise the host. Enable (a BPMP
 * refcount no-op on always-on roots) and reads stay permitted; mutating
 * commands on these ids are denied in check_if_allowed().
 */
static const uint32_t protected_clk_roots[] = {
	14,  /* TEGRA234_CLK_CLK_M */
	102, /* TEGRA234_CLK_PLLP_OUT0 */
};

static bool clk_root_is_protected(uint32_t clk_id)
{
	int i;

	for (i = 0; i < ARRAY_SIZE(protected_clk_roots); i++)
		if (protected_clk_roots[i] == clk_id)
			return true;
	return false;
}

static bool check_if_allowed(struct tegra_bpmp_message *msg)
{
	struct mrq_reset_request *reset_req = NULL;
	struct mrq_clk_request *clock_req = NULL;
	struct mrq_pg_request *pg_req = NULL;
	uint32_t clk_cmd = 0;
	int i = 0;

	// Allow get information, DVFS, ISO Client and bandwidth mrqs
	if(msg->mrq == MRQ_PING ||
	   msg->mrq == MRQ_QUERY_TAG ||
	   msg->mrq == MRQ_THREADED_PING ||
	   msg->mrq == MRQ_QUERY_ABI ||
	   msg->mrq == MRQ_DEBUG ||
	   msg->mrq == MRQ_EMC_DVFS_LATENCY ||
	   msg->mrq == MRQ_EMC_DVFS_EMCHUB ||
	   msg->mrq == MRQ_ISO_CLIENT ||
	   msg->mrq == MRQ_STRAP ||
	   msg->mrq == MRQ_BWMGR || 
	   msg->mrq == MRQ_QUERY_FW_TAG ){
		return true;
	}

	// Check for reset and clock mrq
	if(msg->mrq == MRQ_RESET){
		reset_req = (struct mrq_reset_request*) msg->tx.data;

		for(i = 0; i < bpmp_ares.resets_size; i++){
			if(bpmp_ares.reset[i] == reset_req->reset_id){
				return true;
			}
		}
		deb_warn("Warning, reset not allowed for: %d", reset_req->reset_id);
		return false;
	}
	else if (msg->mrq == MRQ_CLK){
		clock_req = (struct mrq_clk_request*) msg->tx.data;
		clk_cmd = (clock_req->cmd_and_id >> 24) & 0x000F;

		for(i = 0; i < bpmp_ares.clocks_size; i++){
			// bits[23..0] are the clock id
			if(bpmp_ares.clock[i] == (clock_req->cmd_and_id & 0x0FFF)){
				// A guest may enable/read an allowed clock, but must never
				// disable, reparent or rerate a host-critical shared root.
				if(clk_root_is_protected(clock_req->cmd_and_id & 0x0FFF) &&
				   (clk_cmd == CMD_CLK_DISABLE ||
				    clk_cmd == CMD_CLK_SET_RATE ||
				    clk_cmd == CMD_CLK_SET_PARENT)){
					deb_warn("Warning, protected clock root %d: command %d denied",
						clock_req->cmd_and_id & 0x0FFF, clk_cmd);
					return false;
				}
				return true;
			}
		}

		// If there is a get info command, allow it no matters the ID
		if(clk_cmd == CMD_CLK_GET_MAX_CLK_ID ||
		   clk_cmd == CMD_CLK_GET_ALL_INFO ||
		   clk_cmd == CMD_CLK_GET_PARENT){
			return true;
		}

		deb_warn("Warning, clock not allowed for: %d, with command: %d", 
			clock_req->cmd_and_id & 0x0FFF, clk_cmd);
		return false;
	}
	else if(msg->mrq == MRQ_PG){
		pg_req = (struct mrq_pg_request*) msg->tx.data;

		for(i = 0; i < bpmp_ares.pd_size; i++){
			if(bpmp_ares.pd[i] == pg_req->id){
				return true;
			}
		}
		
		// If there is a get info command, allow it no matters the ID
		if(pg_req->cmd == CMD_PG_GET_STATE ||
		   pg_req->cmd == CMD_PG_GET_NAME ||
		   pg_req->cmd == CMD_PG_GET_MAX_ID){
			return true;
		}

		deb_warn("Warning, pg not allowed for: %d, with command: %d", 
			pg_req->id, pg_req->cmd);
		return false;
	}

	/* DIAGNOSTIC: log EVERY rejected MRQ with its command/payload so a display
	 * bring-up that needs a display-specific MRQ (e.g. MRQ_UPHY) the proxy does
	 * not relay is visible. tx.data[0] is the MRQ sub-command for most MRQs. */
	{
		const u32 *d = (const u32 *)msg->tx.data;
		deb_warn("REJECTED mrq=%u tx_size=%zu data0=0x%08x data1=0x%08x",
			 msg->mrq, msg->tx.size,
			 (d && msg->tx.size >= 4) ? d[0] : 0u,
			 (d && msg->tx.size >= 8) ? d[1] : 0u);
	}

	return false;
}

extern int tegra_bpmp_transfer(struct tegra_bpmp *, struct tegra_bpmp_message *);
extern struct tegra_bpmp *tegra_bpmp_host_device;

#define BUF_SIZE 1024 

/*
 * Writes to the device
 */

static ssize_t write(struct file *filep, const char *buffer, size_t len, loff_t *offset)
{

	int ret = len;
	struct tegra_bpmp_message *kbuf = NULL;
	void *txbuf = NULL;
	void *rxbuf = NULL;
	void *usertxbuf = NULL;
	void *userrxbuf = NULL;

	if (len > 65535) {	/* paranoia */
		deb_error("count %zu exceeds max # of bytes allowed, "
			"aborting write\n", len);
		goto out_nomem;
	}

	/* Short write -> kbuf->mrq/tx.size/rx.size below read past kmalloc(len). */
	if (len < sizeof(*kbuf)) {
		deb_error("count %zu shorter than message header, aborting write\n", len);
		ret = -EINVAL;
		goto out_nomem;
	}

	ret = -ENOMEM;
	kbuf = kmalloc(len, GFP_KERNEL);


	if (!kbuf)
		goto out_nomem;

	memset(kbuf, 0, len);

	ret = -EFAULT;
	
	// Copy header
	if (copy_from_user(kbuf, buffer, len)) {
		deb_error("copy_from_user(1) failed\n");
		goto out_cfu;
	}

	deb_info("\nwants to write %zu bytes, with mrq: %d\n", len, kbuf->mrq);

	// A malformed or malicious guest can set tx.size/rx.size larger than the
	// BUF_SIZE bounce buffers below; copy_from_user would then overflow the host
	// slab and corrupt unrelated allocations (observed as SLUB freelist faults in
	// __kmem_cache_alloc_node from unrelated syscalls). Real MRQs are bounded by
	// the guest BPMP window (< MESSAGE_SIZE), so anything larger is rejected. The
	// guest proxy only caps tx.size, so rx.size must be checked here.
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


	usertxbuf = (void*)kbuf->tx.data; //save userspace buffers addresses
	userrxbuf = kbuf->rx.data;


	kbuf->tx.data = txbuf; //reassing to kernel space buffers
	kbuf->rx.data = rxbuf;

	if(!tegra_bpmp_host_device){
		deb_error("host device not initialised, can't do transfer!");
		goto out_cfu;
	}

	// Only continue if allowed or BPMP_HOST_ALLOWS_ALL
	if(!check_if_allowed(kbuf) && !BPMP_HOST_ALLOWS_ALL){
		goto out_cfu;
	}

	hexDump (DEVICE_NAME ": kbuf", kbuf, len);
	hexDump (DEVICE_NAME ": txbuf", txbuf, kbuf->tx.size);

	ret = tegra_bpmp_transfer(tegra_bpmp_host_device, (struct tegra_bpmp_message *)kbuf);



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

static const struct of_device_id bpmp_host_proxy_ids[] = {
	{ .compatible = "nvidia,bpmp-host-proxy" },
	{ }
};

static struct platform_driver bpmp_host_proxy_driver = {
	.driver = {
		.name = "bpmp_host_proxy",
		.of_match_table = bpmp_host_proxy_ids,
	},
	.probe = bpmp_host_proxy_probe,
	.remove = bpmp_host_proxy_remove,
};
builtin_platform_driver(bpmp_host_proxy_driver);