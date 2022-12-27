# SPDX-License-Identifier: EUPL-1.2+
# SPDX-FileCopyrightText: 2021-2022 Alyssa Ross <hi@alyssa.is>
# SPDX-FileCopyrightText: 2022 Unikie


# qemu-kvm is non-standard, but is present in at least Fedora and
# Nixpkgs.  If you don't have qemu-kvm, you'll need to set e.g.
# QEMU_KVM = qemu-system-x86_64 -enable-kvm.
QEMU_KVM = qemu-kvm
CLOUD_HYPERVISOR = cloud-hypervisor

VMM = qemu
SCRIPTS = ../../../scripts

HOST_BUILD_FILES = \
	build/host/data/appvm-usb/blk/root.img \
	build/host/data/appvm-usb/vmlinux \
        build/host/data/appvm-usb/providers/usb/


# We produce a directory, but that doesn't play nice with Make,
# because it won't know to update if some file in the directory is
# changed, or a file is created or removed in a subdirectory.  Using
# the whole directory could also end up including files that aren't
# intended to be part of the input, like temporary editor files or
# .license files.  So for all these reasons, only explicitly listed
# files are included in the build result.
build/svc: $(HOST_BUILD_FILES) $(HOST_FILES)
	rm -rf $@
	mkdir -p $@

	tar -c $(HOST_BUILD_FILES) | tar -C $@ -x --strip-components 2

build/host/data/appvm-usb/vmlinux: $(VMLINUX)
	mkdir -p $$(dirname $@)
	cp $(VMLINUX) $@

build/host/data/appvm-usb/blk/root.img: $(SCRIPTS)/make-gpt.sh $(SCRIPTS)/sfdisk-field.awk build/rootfs.ext4
	mkdir -p $$(dirname $@)
	$(SCRIPTS)/make-gpt.sh $@.tmp \
	    build/rootfs.ext4:4f6888e3-e8cd-4db1-96e7-fbcaf984b709:8881da27-0391-48da-9235-9d2ab2ca7844:root
	mv $@.tmp $@

build/host/data/appvm-usb/providers/usb/:
	mkdir -p $@


# tar2ext4 will leave half a filesystem behind if it's interrupted
# half way through.
build/rootfs.ext4: build/rootfs.tar
	mkdir -p $$(dirname $@)
	tar2ext4 -i build/rootfs.tar -o $@.tmp
	mv $@.tmp $@

VM_FILES = \
    usr/bin/__i \
    usr/bin/usb-import \
	etc/dbus-1/system.conf \
	etc/fstab \
	etc/init \
	etc/mdev.conf \
	etc/mdev/iface \
	etc/nftables.conf \
	etc/passwd \
	etc/s6-linux-init/run-image/service/getty-hvc0/run \
	etc/s6-linux-init/scripts/rc.init \
	etc/sysctl.conf
VM_DIRS = dev etc/s6-linux-init/env run proc sys var/lib/connman

# These are separate because they need to be included, but putting
# them as make dependencies would confuse make.
VM_LINKS = bin var/run

VM_BUILD_FILES = build/etc/s6-rc

build/empty:
	mkdir -p $@

build/rootfs.tar: build/empty $(PACKAGES_TAR) $(VM_FILES) $(VM_BUILD_FILES)
	cp --no-preserve=mode -f $(PACKAGES_TAR) $@
	tar $(TARFLAGS) --append -f $@ $(VM_FILES) $(VM_LINKS)
	echo $(VM_BUILD_FILES) | cut -d/ -f2 | \
	    tar $(TARFLAGS) --append -f $@ -C build -T -
	for m in $(VM_DIRS); do \
	    tar $(TARFLAGS) --append -hf $@ --xform="s,.*,$$m," build/empty ; \
	done

VM_S6_RC_FILES = \
	etc/s6-rc/connman/dependencies \
	etc/s6-rc/connman/run \
	etc/s6-rc/connman/type \
	etc/s6-rc/dbus/notification-fd \
	etc/s6-rc/dbus/run \
	etc/s6-rc/dbus/type \
	etc/s6-rc/mdevd-coldplug/dependencies \
	etc/s6-rc/mdevd-coldplug/type \
	etc/s6-rc/mdevd-coldplug/up \
	etc/s6-rc/mdevd/notification-fd \
	etc/s6-rc/mdevd/run \
	etc/s6-rc/mdevd/type \
	etc/s6-rc/nftables/type \
	etc/s6-rc/nftables/up \
	etc/s6-rc/ok-all/contents \
	etc/s6-rc/ok-all/type \
	etc/s6-rc/sysctl/type \
	etc/s6-rc/sysctl/up

build/etc/s6-rc: $(VM_S6_RC_FILES)
	mkdir -p $$(dirname $@)
	rm -rf $@

	dir=$$(mktemp -d) && \
	    tar -c $(VM_S6_RC_FILES) | tar -C $$dir -x --strip-components 2 && \
	    s6-rc-compile $@ $$dir; \
	    exit=$$?; rm -r $$dir; exit $$exit

run-qemu: build/host/data/appvm-usb/blk/root.img
	$(QEMU_KVM) -m 128 -cpu host -machine q35,kernel=$(KERNEL) -vga none \
	  -drive file=build/host/data/appvm-usb/blk/root.img,if=virtio,format=raw,readonly=on \
	  -append "console=ttyS0 root=PARTLABEL=root" \
	  -netdev user,id=net0 \
	  -device e1000e,netdev=net0 \
	  -netdev user,id=net1 \
	  -device virtio-net,netdev=net1,mac=0A:B3:EC:80:00:00 \
	  -chardev vc,id=virtiocon0 \
	  -device virtio-serial-pci \
	  -device virtconsole,chardev=virtiocon0
.PHONY: run-qemu

run-cloud-hypervisor: build/host/data/appvm-usb/blk/root.img
	$(CLOUD_HYPERVISOR) \
	    --api-socket path=vmm.sock \
	    --memory size=128M \
	    --disk path=build/host/data/appvm-usb/blk/root.img,readonly=on \
	    --net tap=tap0 tap=tap1,mac=0A:B3:EC:80:00:00 \
	    --kernel $(KERNEL) \
	    --cmdline "console=ttyS0 root=PARTLABEL=root" \
	    --console tty \
	    --serial pty
.PHONY: run-cloud-hypervisor

run: run-$(VMM)
.PHONY: run

clean:
	rm -rf build
.PHONY: clean
