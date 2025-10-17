# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: GPL-2.0-only
#
# Out-of-tree build Makefile for the fake battery driver
#
# Usage:
#   make
#   sudo insmod fake_battery.ko
#   ... test ...
#   sudo rmmod fake_battery
#
# Override KDIR if you want a different kernel build tree:
#   make KERNEL_DIR=/path/to/kernel/build

KERNELRELEASE ?= $(shell uname -r)
KERNEL_DIR  ?= /lib/modules/$(KERNELRELEASE)/build
PWD := $(shell pwd)

obj-m := fake_battery.o

all:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules

install:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules_install

clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean
