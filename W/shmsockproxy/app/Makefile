#  Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
#  SPDX-License-Identifier: Apache-2.0

CPPFLAGS = -Wformat-extra-args -Wformat-overflow -Wformat

memsocket: memsocket.c

memsocket.c: ../drivers/char/ivshmem/kvm_ivshmem.h

clean:
	-rm memsocket
