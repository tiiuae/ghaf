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
	{ 0xa2c54569, "consume_skb" },
	{ 0x4d0decbc, "alloc_etherdev_mqs" },
	{ 0x7e722be1, "register_netdev" },
	{ 0xf5617bc3, "free_netdev" },
	{ 0xa08af381, "unregister_netdev" },
	{ 0xa65c6def, "alt_cb_patch_nops" },
	{ 0xb0bb5523, "module_layout" },
};

MODULE_INFO(depends, "");


MODULE_INFO(srcversion, "6520547521D5AAA3151D66E");
