// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

package main

import (
	"errors"
	"fmt"
	"log"
	"os"
	"os/user"
	"strconv"
	"syscall"
	"time"
	"unsafe"
)

type vtpmProxyNewDev struct {
	Flags  uint32
	TPMNum uint32
	FD     uint32
	Major  uint32
	Minor  uint32
}

func chmodTPMNode(path string) error {
	if err := os.Chmod(path, 0o660); err != nil {
		return err
	}

	grp, err := user.LookupGroup("kvm")
	if err != nil {
		return err
	}
	gid, err := strconv.Atoi(grp.Gid)
	if err != nil {
		return err
	}

	return os.Chown(path, -1, gid)
}

func allocateUsableVTPM(vtpmCtl *os.File, vmName string) (vtpmProxyNewDev, *os.File, string, error) {
	var lastErr error

	for attempt := 1; attempt <= 8; attempt++ {
		newDev := vtpmProxyNewDev{Flags: vtpmProxyFlagTPM2}
		_, _, errno := syscall.Syscall(
			syscall.SYS_IOCTL,
			vtpmCtl.Fd(),
			uintptr(vtpmProxyIOCNewDev),
			uintptr(unsafe.Pointer(&newDev)),
		)
		if errno != 0 {
			lastErr = errno
			time.Sleep(150 * time.Millisecond)
			continue
		}

		proxyFD := os.NewFile(uintptr(newDev.FD), fmt.Sprintf("vtpm-proxy-%s", vmName))
		if proxyFD == nil {
			lastErr = errors.New("failed to create proxy fd handle")
			time.Sleep(150 * time.Millisecond)
			continue
		}

		guestTPMPath := fmt.Sprintf("/dev/tpm%d", newDev.TPMNum)
		if err := ensureTPMNode(guestTPMPath, newDev.Major, newDev.Minor); err != nil {
			_ = proxyFD.Close()
			return vtpmProxyNewDev{}, nil, "", err
		}
		if err := chmodTPMNode(guestTPMPath); err != nil {
			log.Printf("warning: could not adjust TPM node permissions: %v", err)
		}

		return newDev, proxyFD, guestTPMPath, nil
	}

	if lastErr == nil {
		lastErr = errors.New("vTPM allocation failed")
	}
	return vtpmProxyNewDev{}, nil, "", lastErr
}

func ensureTPMNode(path string, major, minor uint32) error {
	wantDev := makeLinuxDev(major, minor)

	if info, err := os.Stat(path); err == nil {
		if info.Mode()&os.ModeDevice == 0 {
			return fmt.Errorf("existing path is not a device: %s", path)
		}

		st, ok := info.Sys().(*syscall.Stat_t)
		if !ok {
			return fmt.Errorf("failed to inspect existing device node: %s", path)
		}

		if uint64(st.Rdev) == wantDev {
			return nil
		}

		if err := os.Remove(path); err != nil {
			return fmt.Errorf("failed to replace stale TPM node %s: %w", path, err)
		}
	} else if !os.IsNotExist(err) {
		return err
	}

	mode := uint32(syscall.S_IFCHR | 0o660)
	dev := int(wantDev)
	if err := syscall.Mknod(path, mode, dev); err != nil {
		if os.IsExist(err) {
			return nil
		}
		return err
	}

	return nil
}

func makeLinuxDev(major, minor uint32) uint64 {
	maj := uint64(major)
	min := uint64(minor)
	return (min & 0xff) | ((maj & 0xfff) << 8) | ((min &^ 0xff) << 12) | ((maj &^ 0xfff) << 32)
}
