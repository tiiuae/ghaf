# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: GPL-2.0-only
#
# Out-of-tree build Makefile for the EMC cap lift module
#
# Override KERNEL_DIR if you want a different kernel build tree:
#   make KERNEL_DIR=/path/to/kernel/build

KERNELRELEASE ?= $(shell uname -r)
KERNEL_DIR  ?= /lib/modules/$(KERNELRELEASE)/build
PWD := $(shell pwd)

obj-m := emc_cap_lift.o

all:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules

install:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) modules_install

clean:
	$(MAKE) -C $(KERNEL_DIR) M=$(PWD) clean
