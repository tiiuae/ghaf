#  Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
#  SPDX-License-Identifier: Apache-2.0

obj-m := kvm_ivshmem.o 

# KDIR definition to be used under NixOS
KDIR  := /run/current-system/sw/lib/modules/$(shell uname -r)/build/
#KDIR  := /lib/modules/$(shell uname -r)/build/
PWD   := $(shell pwd)

default:
	cp ../drivers/char/ivshmem/kvm_ivshmem.c .
	cp ../drivers/char/ivshmem/kvm_ivshmem.h .
	$(MAKE) -C $(KDIR) M=$(PWD) modules

install:
	cp kvm_ivshmem.ko /lib/modules/$(shell uname -r)/kernel/drivers/char

clean:
	rm -f *.ko *.o kvm_ivshmem.mod.c Module.symvers
