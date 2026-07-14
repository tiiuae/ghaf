/**
 * 
 * NVIDIA BPMP Guest Proxy Kernel Module
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
#include <linux/mm.h>
#include <linux/memory_hotplug.h>
#include <linux/io.h>
#include <linux/spinlock.h>
#include <soc/tegra/bpmp.h>


#define DEVICE_NAME "bpmp-guest" // Device name.
#define CLASS_NAME "char"	  

MODULE_LICENSE("GPL");						 
MODULE_AUTHOR("Vadim Likholetov");					 
MODULE_DESCRIPTION("NVidia BPMP Guest Proxy Kernel Module"); 
MODULE_VERSION("0.1");				 


#define TX_BUF         0x0000
#define RX_BUF         0x0200
#define TX_SIZ         0x0400
#define RX_SIZ         0x0408
#define RET_COD        0x0410
#define MRQ            0x0500
#define MEM_SIZE       0x0600
#define MESSAGE_SIZE   0x0200


#define BPMP_GUEST_VERBOSE    0

#if BPMP_GUEST_VERBOSE
#define deb_info(...)     printk(KERN_INFO DEVICE_NAME ": "__VA_ARGS__)
#else
#define deb_info(...)
#endif

#define deb_error(...)    printk(KERN_ALERT DEVICE_NAME ": "__VA_ARGS__)


static volatile void __iomem  *mem_iova = NULL;

// The BPMP virtual-pa window is a single shared MMIO region reused for every
// transaction (write request -> trigger -> read response). Guest engines
// (host1x/vic/nvdec/gk20a) probe in parallel and issue bpmp transfers
// concurrently via the threaded tegra_bpmp_transfer path, which holds no
// global lock. Without serialization here, two transfers interleave on the
// window and corrupt each other's request/response. Must be a spinlock, not a
// mutex: the redirect hook is also invoked from tegra_bpmp_transfer_atomic
// (atomic/IRQ context), so sleeping is illegal.
static DEFINE_SPINLOCK(bpmp_guest_xfer_lock);

extern int tegra_bpmp_transfer(struct tegra_bpmp *, struct tegra_bpmp_message *);
extern struct tegra_bpmp *tegra_bpmp_host_device;
int my_tegra_bpmp_transfer(struct tegra_bpmp *, struct tegra_bpmp_message *);


extern int (*tegra_bpmp_transfer_redirect)(struct tegra_bpmp *, struct tegra_bpmp_message *);
extern int tegra_bpmp_outloud;
extern uint64_t bpmp_vpa;


/**
 * Important variables that store data and keep track of relevant information.
 */
static int major_number;

static struct class *bpmp_guest_proxy_class = NULL;	///< The device-driver class struct pointer
static struct device *bpmp_guest_proxy_device = NULL; ///< The device-driver device struct pointer

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


#if BPMP_GUEST_VERBOSE
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
	unsigned char out_buff[200];
	unsigned char *p_out_buff = out_buff;
    const unsigned char * pc = (const unsigned char *)addr;



    // Output description if given.

    if (desc != NULL) printk ("%s:\n", desc);

    // Length checks.

    if (len == 0) {
        printk("  ZERO LENGTH\n");
        return;
    }
    if (len < 0) {
        printk("  NEGATIVE LENGTH: %d\n", len);
        return;
    }

	if(len > 2046){
        printk("  VERY LONG: %d\n", len);
        return;
    }

    // Process every byte in the data.

    for (i = 0; i < len; i++) {
        // Multiple of perLine means new or first line (with line offset).

        if ((i % 16) == 0) {
            // Only print previous-line ASCII buffer for lines beyond first.

            if (i != 0) {
				p_out_buff += sprintf (p_out_buff, "  %s\n", buff);
				printk("%s", out_buff);
				memset(out_buff, 0, sizeof(out_buff));
				p_out_buff = out_buff;
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

	printk("%s", out_buff);
}
#else
	#define hexDump(...)
#endif

/**
 * Initializes module at installation
 */
int tegra_bpmp_guest_init(void)
{

	
	deb_info("%s, installing module.", __func__);

	deb_info("bpmp_vpa: 0x%llX", bpmp_vpa);

	if(!bpmp_vpa){
		deb_error("Failed, bpmp_vpa not defined\n");
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
	bpmp_guest_proxy_class = class_create(CLASS_NAME);
	if (IS_ERR(bpmp_guest_proxy_class))
	{ // Check for error and clean up if there is
		unregister_chrdev(major_number, DEVICE_NAME);
		deb_error("Failed to register device class\n");
		return PTR_ERR(bpmp_guest_proxy_class); // Correct way to return an error on a pointer
	}
	deb_info("device class registered correctly\n");

	// Register the device driver
	bpmp_guest_proxy_device = device_create(bpmp_guest_proxy_class, NULL, MKDEV(major_number, 0), NULL, DEVICE_NAME);
	if (IS_ERR(bpmp_guest_proxy_device))
	{								 // Clean up if there is an error
		class_destroy(bpmp_guest_proxy_class); 
		unregister_chrdev(major_number, DEVICE_NAME);
		deb_error("Failed to create the device\n");
		return PTR_ERR(bpmp_guest_proxy_device);
	}
	deb_info("device class created correctly\n"); // Made it! device was initialized

	// map iomem
	mem_iova = ioremap(bpmp_vpa, MEM_SIZE);

	if (!mem_iova) {
        deb_error("ioremap failed\n");
        return -ENOMEM;
    }

	deb_info("bpmp_vpa: 0x%llX, mem_iova: %p\n", bpmp_vpa, mem_iova);

	tegra_bpmp_transfer_redirect = my_tegra_bpmp_transfer; // Hook func

	return 0;
}

EXPORT_SYMBOL(tegra_bpmp_guest_init);



/*
 * Removes module, sends appropriate message to kernel
 */
void tegra_bpmp_guest_cleanup(void)
{
	deb_info("removing module.\n");

	// unmap iomem
	iounmap((void __iomem*)bpmp_vpa);

    tegra_bpmp_transfer_redirect = NULL;   // unhook function
	device_destroy(bpmp_guest_proxy_class, MKDEV(major_number, 0)); // remove the device
	class_unregister(bpmp_guest_proxy_class);						  // unregister the device class
	class_destroy(bpmp_guest_proxy_class);						  // remove the device class
	unregister_chrdev(major_number, DEVICE_NAME);		  // unregister the major number
	deb_info("Goodbye from the LKM!\n");
	unregister_chrdev(major_number, DEVICE_NAME);
	return;
}

/*
 * Opens device module, sends appropriate message to kernel
 */
static int open(struct inode *inodep, struct file *filep)
{
	deb_info("device opened.\n");
    tegra_bpmp_outloud = 1;
	return 0;
}

/*
 * Closes device module, sends appropriate message to kernel
 */
static int close(struct inode *inodep, struct file *filep)
{
	deb_info("device closed.\n");
    tegra_bpmp_outloud = 0;
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



int my_tegra_bpmp_transfer(struct tegra_bpmp *bpmp, struct tegra_bpmp_message *msg)
{   

	unsigned char io_buffer[MEM_SIZE];
	size_t org_tx_size = 0;
	size_t org_rx_size = 0;
	unsigned long flags;

	deb_info("%s\n", __func__);

	memset(io_buffer, 0, sizeof(io_buffer));

    if (msg->tx.size >= MESSAGE_SIZE)
		return -EINVAL;

	org_tx_size = msg->tx.size;
	org_rx_size = msg->rx.size;

	// Copy msg, tx data and rx data to a single io_buffer
    memcpy(&io_buffer[TX_BUF], msg->tx.data, msg->tx.size);
	memcpy(&io_buffer[TX_SIZ], &msg->tx.size, sizeof(msg->tx.size));
	
	memcpy(&io_buffer[RX_BUF], msg->rx.data, msg->rx.size);
	memcpy(&io_buffer[RX_SIZ], &msg->rx.size, sizeof(msg->rx.size));

	memcpy(&io_buffer[MRQ], &msg->mrq, sizeof(msg->mrq));
	

    hexDump("msg", &msg, sizeof(struct tegra_bpmp_message));
    deb_info("msg.tx.data: %p\n", msg->tx.data);
    hexDump("msg.tx.data", msg->tx.data, msg->tx.size);
	deb_info("msg->rx.size: %ld\n", msg->rx.size);
	
	// Serialize the whole request/response against the shared window.
	spin_lock_irqsave(&bpmp_guest_xfer_lock, flags);

	// Execute the request by coping the io_buffer
	memcpy_toio(mem_iova, io_buffer, MEM_SIZE);

	// Read response to io_buffer
	memcpy_fromio(io_buffer, mem_iova, MEM_SIZE);

	spin_unlock_irqrestore(&bpmp_guest_xfer_lock, flags);

	// Copy from io_buffer to msg, tx data and rx data
	memcpy(&msg->tx.size, &io_buffer[TX_SIZ], sizeof(msg->tx.size));
	memcpy(&msg->rx.size, &io_buffer[RX_SIZ], sizeof(msg->rx.size));
	
	// If new msg->tx/rx.size is greater than the original msg->tx/rx.size, 
	// use the original because it is the max size of the destination buffer.
	if(msg->tx.size > org_tx_size)
		msg->tx.size = org_tx_size;

	if(msg->rx.size > org_rx_size)
		msg->rx.size = org_rx_size;

	// Do not return error if buffers not defined, because for some cases
	// the BPMP communicates with empty buffer
	if(msg->tx.data)
		memcpy((void *)msg->tx.data, &io_buffer[TX_BUF], msg->tx.size);

	if(msg->rx.data)
		memcpy(msg->rx.data, &io_buffer[RX_BUF], msg->rx.size);
	
	memcpy(&msg->rx.ret, &io_buffer[RET_COD], sizeof(msg->rx.ret));

	deb_info("%s, END ret: %d\n", __func__, msg->rx.ret);

    return msg->rx.ret;
}

/*
 * Writes to the device
 */

#define BUF_SIZE 1024 

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

	deb_info(" wants to write %zu bytes\n", len);

	if (len!=sizeof(struct tegra_bpmp_message ))
	{
		deb_error("message size %zu != %zu", len, sizeof(struct tegra_bpmp_message));
		goto out_notok;
	}

	ret = -ENOMEM;
	kbuf = kmalloc(len, GFP_KERNEL);
	txbuf = kmalloc(BUF_SIZE, GFP_KERNEL);
	rxbuf = kmalloc(BUF_SIZE, GFP_KERNEL);

	if (!kbuf || !txbuf || !rxbuf)
		goto out_nomem;

	memset(kbuf, 0, len);
	memset(txbuf, 0, len);
	memset(rxbuf, 0, len);

	ret = -EFAULT;
	
	if (copy_from_user(kbuf, buffer, len)) {
		deb_error("copy_from_user(1) failed\n");
		goto out_cfu;
	}

	if (copy_from_user(txbuf, kbuf->tx.data, kbuf->tx.size)) {
		deb_error("copy_from_user(2) failed\n");
		goto out_cfu;
	}

	if (copy_from_user(rxbuf, kbuf->rx.data, kbuf->rx.size)) {
		deb_error("copy_from_user(3) failed\n");
		goto out_cfu;
	}	

	usertxbuf = (void*)kbuf->tx.data; //save userspace buffers addresses
	userrxbuf = kbuf->rx.data;

	kbuf->tx.data=txbuf; //reassing to kernel space buffers
	kbuf->rx.data=rxbuf;


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
	return len;
out_notok:
out_nomem:
	deb_error ("memory allocation failed");
out_cfu:
	kfree(kbuf);
	kfree(txbuf);
	kfree(rxbuf);
    return -EINVAL;
}

