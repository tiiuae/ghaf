#!/bin/bash
#time qemu-system-aarch64  -machine virt -cpu cortex-a53  -kernel ../k/dst/linux-x86-allnoconfig/arch/arm64/boot/Image -initrd tiny-initrd.img -m 1000 -display none -serial stdio -audiodev id=none,driver=none 
time ../qemu-8.2/build/qemu-system-aarch64  -machine virt -cpu cortex-a53  -kernel /boot/vmlinux -initrd tiny-initrd.img -m 1000 -display none -serial stdio -audiodev id=none,driver=none  -usb      -device nec-usb-xhci,id=xhci   -device u2f-passthru,hidraw=/dev/hidraw5 -device usb-ccid -device ccid-card-emulated,backend=nss-emulated,id=smartcard0
