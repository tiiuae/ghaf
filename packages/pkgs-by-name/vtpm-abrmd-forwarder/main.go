// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

package main

import (
	"encoding/binary"
	"errors"
	"flag"
	"fmt"
	"io"
	"log"
	"os"
	"os/signal"
	"path/filepath"
	"sync"
	"sync/atomic"
	"syscall"
	"time"
)

const (
	// _IOWR(0xa1, 0x00, struct vtpm_proxy_new_dev)
	// struct size: 5 * __u32 = 20 bytes
	vtpmProxyIOCNewDev = 0xC014A100
	vtpmProxyFlagTPM2  = 1

	tpm2SetLocalityCC = 0x20001000
	tpm2SelfTestCC    = 0x00000143
	tpm2GetCapCC      = 0x0000017A
	tpm2GetRandomCC   = 0x0000017B
	tpm2RCRetry       = 0x00000922
	tpm2RCYielded     = 0x00000908
	tpm2RCTesting     = 0x0000090A

	maxTPMPacketSize = 64 * 1024

	helperRestartBackoffMin = 200 * time.Millisecond
	helperRestartBackoffMax = 5 * time.Second

	backendLockWaitDefault   = 250 * time.Millisecond
	backendLockWaitGetRandom = 100 * time.Millisecond
	backendBudgetDefault     = 1200 * time.Millisecond
	backendBudgetGetRandom   = 300 * time.Millisecond
	backendRetryPause        = 20 * time.Millisecond

	backendBusyTripThreshold = 6
	backendBusyCooldown      = 3 * time.Second
)

var errBackendBusy = errors.New("backend busy")

type saturationGuard struct {
	streak        int
	cooldownUntil time.Time
}

func (g *saturationGuard) active(now time.Time) bool {
	return now.Before(g.cooldownUntil)
}

func (g *saturationGuard) noteBusy(now time.Time) bool {
	g.streak++
	if g.streak < backendBusyTripThreshold {
		return false
	}

	g.streak = 0
	if now.Before(g.cooldownUntil) {
		return false
	}

	g.cooldownUntil = now.Add(backendBusyCooldown)
	return true
}

func (g *saturationGuard) noteSuccess() {
	g.streak = 0
}

func main() {
	var vmName string
	var backendDevice string
	var linkPath string

	flag.StringVar(&vmName, "vm-name", "", "VM name")
	flag.StringVar(&backendDevice, "backend-device", "/dev/tpmrm0", "Host TPM device")
	flag.StringVar(&linkPath, "link-path", "", "Path exposed to VM qemu args")
	flag.Parse()

	if vmName == "" {
		log.Fatal("--vm-name is required")
	}
	if linkPath == "" {
		log.Fatal("--link-path is required")
	}

	info, err := os.Stat(backendDevice)
	if err != nil {
		log.Fatalf("backend device not available: %v", err)
	}
	if info.Mode()&os.ModeDevice == 0 {
		log.Fatalf("backend path is not a device: %s", backendDevice)
	}

	if err := os.MkdirAll(filepath.Dir(linkPath), 0o755); err != nil {
		log.Fatalf("failed to create runtime directory: %v", err)
	}

	if err := os.RemoveAll(linkPath); err != nil {
		log.Fatalf("failed to cleanup old link: %v", err)
	}

	vtpmCtl, err := os.OpenFile("/dev/vtpmx", os.O_RDWR, 0)
	if err != nil {
		log.Fatalf("failed to open /dev/vtpmx: %v", err)
	}
	defer vtpmCtl.Close()

	newDev, proxyFD, guestTPMPath, err := allocateUsableVTPM(vtpmCtl, vmName)
	if err != nil {
		log.Fatalf("failed to allocate usable vTPM: %v", err)
	}
	defer proxyFD.Close()

	helper, err := startBackendHelper(backendDevice)
	if err != nil {
		log.Fatalf("failed to start backend helper: %v", err)
	}
	defer helper.Close()

	backendLock, err := os.OpenFile("/run/ghaf-vtpm/backend.lock", os.O_CREATE|os.O_RDWR, 0o660)
	if err != nil {
		log.Fatalf("failed to open backend lock: %v", err)
	}
	defer backendLock.Close()

	sigCh := make(chan os.Signal, 1)
	signal.Notify(sigCh, syscall.SIGTERM, syscall.SIGINT)

	errCh := make(chan error, 1)
	stopCh := make(chan struct{})
	var once sync.Once

	go forwardProxyLoop(vmName, proxyFD, helper, backendLock, stopCh)

	if err := os.Symlink(guestTPMPath, linkPath); err != nil {
		log.Fatalf("failed to create link %s -> %s: %v", linkPath, guestTPMPath, err)
	}

	log.Printf(
		"vm=%s link=%s guest_tpm=%s backend=%s vtpm=(num=%d major=%d minor=%d)",
		vmName,
		linkPath,
		guestTPMPath,
		backendDevice,
		newDev.TPMNum,
		newDev.Major,
		newDev.Minor,
	)
	sdNotify("READY=1")

	select {
	case sig := <-sigCh:
		once.Do(func() { close(stopCh) })
		fmt.Printf("received signal %s, exiting\n", sig.String())
	case err := <-errCh:
		once.Do(func() { close(stopCh) })
		log.Printf("forwarder exiting due to error: %v", err)
		time.Sleep(250 * time.Millisecond)
		os.Exit(1)
	}
}

func forwardProxyLoop(vmName string, proxyFD *os.File, helper *backendHelper, backendLock *os.File, stopCh <-chan struct{}) {
	idleBackoff := 20 * time.Millisecond
	var totalCmd uint64
	var okCmd uint64
	var backendErrCmd uint64
	var backendBusyCmd uint64
	var backendCircuitCmd uint64
	var proxyWriteErrCmd uint64
	var debugCmdCount int32
	guard := &saturationGuard{}

	for {
		select {
		case <-stopCh:
			return
		default:
		}

		cmd, err := readTPMPacketProxy(proxyFD)
		if err != nil {
			if isIdleProxyReadError(err) {
				time.Sleep(idleBackoff)
				if idleBackoff < 500*time.Millisecond {
					idleBackoff *= 2
				}
				continue
			}
			idleBackoff = 20 * time.Millisecond
			log.Printf("proxy read failed: %v", err)
			time.Sleep(100 * time.Millisecond)
			continue
		}
		idleBackoff = 20 * time.Millisecond

		cmdCC := uint32(0)
		if len(cmd) >= 10 {
			cmdCC = binary.BigEndian.Uint32(cmd[6:10])
		}
		cmdName := tpm2CommandName(cmdCC)

		if atomic.LoadInt32(&debugCmdCount) < 10 {
			log.Printf("proxy cmd size=%d cc=0x%08x(%s) bytes=%x", len(cmd), cmdCC, cmdName, cmd)
			atomic.AddInt32(&debugCmdCount, 1)
		}
		totalCmd++

		if isSetLocalityCommand(cmd) {
			if err := writeAll(proxyFD, tpmSuccessResponse(cmd)); err != nil {
				log.Printf("proxy write failed for set-locality: %v", err)
				time.Sleep(100 * time.Millisecond)
				continue
			}
			continue
		}

		if isSelfTestCommand(cmd) {
			if err := writeAll(proxyFD, tpmSuccessResponse(cmd)); err != nil {
				log.Printf("proxy write failed for self-test: %v", err)
				time.Sleep(100 * time.Millisecond)
				continue
			}
			continue
		}

		start := time.Now()
		var (
			resp       []byte
			backendErr error
		)
		if guard.active(start) {
			backendErr = errBackendBusy
			backendCircuitCmd++
		} else {
			resp, backendErr = transactBackend(helper, backendLock, cmdCC, cmd)
		}
		if backendErr != nil {
			backendErrCmd++
			if err := writeAll(proxyFD, tpmRetryResponse(cmd)); err != nil {
				proxyWriteErrCmd++
				log.Printf("proxy write failed while sending retry cc=0x%08x(%s): %v", cmdCC, cmdName, err)
				time.Sleep(100 * time.Millisecond)
				continue
			}
			if errors.Is(backendErr, errBackendBusy) {
				backendBusyCmd++
				if guard.noteBusy(time.Now()) {
					log.Printf("backend saturation guard engaged vm=%s cooldown=%s", vmName, backendBusyCooldown)
				}
				log.Printf("backend busy cc=0x%08x(%s) dur=%s, replied TPM2_RC_RETRY", cmdCC, cmdName, time.Since(start).Round(time.Millisecond))
			} else {
				log.Printf("backend transact failed cc=0x%08x(%s) dur=%s (%v), replied TPM2_RC_RETRY", cmdCC, cmdName, time.Since(start).Round(time.Millisecond), backendErr)
				time.Sleep(25 * time.Millisecond)
			}
			continue
		}
		guard.noteSuccess()
		okCmd++

		dur := time.Since(start)
		if dur > 2*time.Second {
			rc := uint32(0)
			if len(resp) >= 10 {
				rc = binary.BigEndian.Uint32(resp[6:10])
			}
			log.Printf("slow backend response cc=0x%08x(%s) rc=0x%08x dur=%s", cmdCC, cmdName, rc, dur.Round(time.Millisecond))
		}

		if atomic.LoadInt32(&debugCmdCount) <= 10 {
			log.Printf("backend resp size=%d", len(resp))
		}

		if err := writeAll(proxyFD, resp); err != nil {
			proxyWriteErrCmd++
			log.Printf("proxy write failed cc=0x%08x(%s) dur=%s: %v", cmdCC, cmdName, dur.Round(time.Millisecond), err)
			time.Sleep(100 * time.Millisecond)
			continue
		}

		if totalCmd%100 == 0 {
			log.Printf("forwarder stats vm=%s total=%d ok=%d backend_err=%d backend_busy=%d circuit=%d write_err=%d", vmName, totalCmd, okCmd, backendErrCmd, backendBusyCmd, backendCircuitCmd, proxyWriteErrCmd)
		}
	}
}

func transactBackend(helper *backendHelper, backendLock *os.File, cmdCC uint32, cmd []byte) ([]byte, error) {
	var lastErr error
	lockWait := backendLockWaitDefault
	budget := backendBudgetDefault
	if cmdCC == tpm2GetRandomCC {
		lockWait = backendLockWaitGetRandom
		budget = backendBudgetGetRandom
	}

	if err := acquireBackendLock(backendLock, lockWait); err != nil {
		return nil, err
	}
	defer func() {
		_ = syscall.Flock(int(backendLock.Fd()), syscall.LOCK_UN)
	}()

	deadline := time.Now().Add(budget)
	for attempt := 1; attempt <= 2; attempt++ {
		if time.Now().After(deadline) {
			return nil, errBackendBusy
		}

		resp, err := helper.Transact(cmd)
		if err != nil {
			lastErr = err
			time.Sleep(backendRetryPause)
			continue
		}

		if isTransientRC(resp) {
			lastErr = fmt.Errorf("transient rc=0x%08x", binary.BigEndian.Uint32(resp[6:10]))
			time.Sleep(backendRetryPause)
			continue
		}

		return resp, nil
	}

	if lastErr == nil {
		lastErr = io.ErrUnexpectedEOF
	}
	return nil, lastErr
}

func acquireBackendLock(backendLock *os.File, timeout time.Duration) error {
	deadline := time.Now().Add(timeout)
	for {
		err := syscall.Flock(int(backendLock.Fd()), syscall.LOCK_EX|syscall.LOCK_NB)
		if err == nil {
			return nil
		}
		if !errors.Is(err, syscall.EWOULDBLOCK) && !errors.Is(err, syscall.EAGAIN) {
			return err
		}
		if time.Now().After(deadline) {
			return errBackendBusy
		}
		time.Sleep(5 * time.Millisecond)
	}
}

func tpm2CommandName(cc uint32) string {
	switch cc {
	case tpm2SetLocalityCC:
		return "SetLocality"
	case tpm2SelfTestCC:
		return "SelfTest"
	case tpm2GetCapCC:
		return "GetCapability"
	case tpm2GetRandomCC:
		return "GetRandom"
	default:
		return "unknown"
	}
}
