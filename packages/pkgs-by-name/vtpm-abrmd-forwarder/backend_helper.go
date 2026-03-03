// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

package main

import (
	"fmt"
	"sync"
	"time"
	"unsafe"
)

type backendHelper struct {
	backendDevice string
	ctx           unsafe.Pointer
	mu            sync.Mutex

	restartBackoff time.Duration
	nextRestartAt  time.Time
}

func startBackendHelper(backendDevice string) (*backendHelper, error) {
	h := &backendHelper{backendDevice: backendDevice}
	h.mu.Lock()
	defer h.mu.Unlock()
	if err := h.restartLocked(); err != nil {
		return nil, err
	}
	return h, nil
}

func (h *backendHelper) Close() {
	h.mu.Lock()
	defer h.mu.Unlock()
	h.closeLocked()
}

func (h *backendHelper) closeLocked() {
	if h.ctx != nil {
		tctiFinalize(h.ctx)
		h.ctx = nil
	}
}

func (h *backendHelper) restartLocked() error {
	now := time.Now()
	if !h.nextRestartAt.IsZero() && now.Before(h.nextRestartAt) {
		return fmt.Errorf("backend context restart cooling down (%s)", time.Until(h.nextRestartAt).Round(10*time.Millisecond))
	}

	h.closeLocked()

	ctx, err := tctiInit()
	if err != nil {
		if h.restartBackoff == 0 {
			h.restartBackoff = helperRestartBackoffMin
		} else {
			h.restartBackoff *= 2
			if h.restartBackoff > helperRestartBackoffMax {
				h.restartBackoff = helperRestartBackoffMax
			}
		}
		h.nextRestartAt = now.Add(h.restartBackoff)
		return fmt.Errorf("backend context restart failed: %w (next retry in %s)", err, h.restartBackoff)
	}

	h.ctx = ctx
	h.restartBackoff = 0
	h.nextRestartAt = time.Time{}
	return nil
}

func (h *backendHelper) Transact(req []byte) ([]byte, error) {
	h.mu.Lock()
	defer h.mu.Unlock()

	if h.ctx == nil {
		if err := h.restartLocked(); err != nil {
			return nil, err
		}
	}

	var lastErr error
	for attempt := 1; attempt <= 2; attempt++ {
		resp, err := tctiTransact(h.ctx, req)
		if err == nil {
			return resp, nil
		}
		lastErr = err
		if attempt == 1 {
			if rerr := h.restartLocked(); rerr != nil {
				return nil, fmt.Errorf("backend context transact failed: %v; restart failed: %v", err, rerr)
			}
		}
	}

	return nil, lastErr
}
