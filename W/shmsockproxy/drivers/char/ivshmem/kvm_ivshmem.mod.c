#include <linux/module.h>
#define INCLUDE_VERMAGIC
#include <linux/build-salt.h>
#include <linux/elfnote-lto.h>
#include <linux/export-internal.h>
#include <linux/vermagic.h>
#include <linux/compiler.h>

#ifdef CONFIG_UNWINDER_ORC
#include <asm/orc_header.h>
ORC_HEADER;
#endif

BUILD_SALT;
BUILD_LTO_INFO;

MODULE_INFO(vermagic, VERMAGIC_STRING);
MODULE_INFO(name, KBUILD_MODNAME);

__visible struct module __this_module
__section(".gnu.linkonce.this_module") = {
	.name = KBUILD_MODNAME,
	.init = init_module,
#ifdef CONFIG_MODULE_UNLOAD
	.exit = cleanup_module,
#endif
	.arch = MODULE_ARCH_INIT,
};

#ifdef CONFIG_RETPOLINE
MODULE_INFO(retpoline, "Y");
#endif



static const struct modversion_info ____versions[]
__used __section("__versions") = {
	{ 0x122c3a7e, "_printk" },
	{ 0x5b40b26d, "misc_register" },
	{ 0x86cd716f, "__pci_register_driver" },
	{ 0xd9a5ea54, "__init_waitqueue_head" },
	{ 0xc7062395, "misc_deregister" },
	{ 0x4789539b, "pci_irq_vector" },
	{ 0x3ce4ca6f, "disable_irq" },
	{ 0xc1514a3b, "free_irq" },
	{ 0xfec8e386, "pci_free_irq_vectors" },
	{ 0x52abe0fe, "pci_iounmap" },
	{ 0x7c4a4bb8, "pci_release_regions" },
	{ 0x1d8e31d, "pci_disable_device" },
	{ 0xba8fbd64, "_raw_spin_lock" },
	{ 0xb5b54b34, "_raw_spin_unlock" },
	{ 0xe2964344, "__wake_up" },
	{ 0x57bc19d2, "down_write" },
	{ 0xce807a25, "up_write" },
	{ 0x353e08dc, "remap_pfn_range" },
	{ 0x76bbad0f, "pci_unregister_driver" },
	{ 0x62ced28d, "pci_enable_device" },
	{ 0xe3cfd2dc, "pci_request_regions" },
	{ 0x6310d399, "pci_iomap" },
	{ 0x18b48e28, "__memset_io" },
	{ 0x702174d, "kmalloc_caches" },
	{ 0x55a468f3, "kmalloc_trace" },
	{ 0x18fd4447, "pci_alloc_irq_vectors" },
	{ 0x656e4a6e, "snprintf" },
	{ 0x92d5838e, "request_threaded_irq" },
	{ 0x76b3e0d0, "pci_set_master" },
	{ 0x88db9f48, "__check_object_size" },
	{ 0x6cbbfc54, "__arch_copy_to_user" },
	{ 0x12a4e128, "__arch_copy_from_user" },
	{ 0xdcb764ad, "memset" },
	{ 0x34db050b, "_raw_spin_lock_irqsave" },
	{ 0xd35cce70, "_raw_spin_unlock_irqrestore" },
	{ 0xf0fdf6cb, "__stack_chk_fail" },
	{ 0xcbd4898c, "fortify_panic" },
	{ 0xb0bb5523, "module_layout" },
};

MODULE_INFO(depends, "");

MODULE_ALIAS("pci:v00001AF4d00001110sv*sd*bc*sc*i*");

MODULE_INFO(srcversion, "3F7BC6CA76BDFC7548C007E");
