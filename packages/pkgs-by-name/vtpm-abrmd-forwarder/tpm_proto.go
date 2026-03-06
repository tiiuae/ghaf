// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

package main

import (
	"encoding/binary"
	"errors"
	"fmt"
	"io"
	"os"
	"strings"
	"syscall"
)

func isSetLocalityCommand(cmd []byte) bool {
	if len(cmd) < 10 {
		return false
	}
	cc := binary.BigEndian.Uint32(cmd[6:10])
	return cc == tpm2SetLocalityCC
}

func isSelfTestCommand(cmd []byte) bool {
	if len(cmd) < 10 {
		return false
	}
	cc := binary.BigEndian.Uint32(cmd[6:10])
	return cc == tpm2SelfTestCC
}

func tpmRetryResponse(cmd []byte) []byte {
	resp := make([]byte, 10)
	binary.BigEndian.PutUint16(resp[0:2], binary.BigEndian.Uint16(cmd[0:2]))
	binary.BigEndian.PutUint32(resp[2:6], uint32(len(resp)))
	binary.BigEndian.PutUint32(resp[6:10], tpm2RCRetry)
	return resp
}

func tpmSuccessResponse(cmd []byte) []byte {
	tagA := byte(0x80)
	tagB := byte(0x01)
	if len(cmd) >= 2 {
		tagA = cmd[0]
		tagB = cmd[1]
	}
	return []byte{tagA, tagB, 0x00, 0x00, 0x00, 0x0A, 0x00, 0x00, 0x00, 0x00}
}

func writeAll(f *os.File, buf []byte) error {
	n, err := f.Write(buf)
	if err != nil {
		return err
	}
	if n != len(buf) {
		return io.ErrShortWrite
	}
	return nil
}

func readTPMPacketProxy(f *os.File) ([]byte, error) {
	buf := make([]byte, maxTPMPacketSize)
	n, err := f.Read(buf)
	if err != nil {
		return nil, err
	}
	if n == 0 {
		return nil, io.EOF
	}
	if n < 6 {
		return nil, fmt.Errorf("short TPM header (%d bytes)", n)
	}

	want := int(binary.BigEndian.Uint32(buf[2:6]))
	if want <= 0 || want > maxTPMPacketSize {
		return nil, fmt.Errorf("invalid TPM packet size: %d", want)
	}
	if want < 6 {
		return nil, fmt.Errorf("invalid TPM packet size: %d", want)
	}
	if want > n {
		return nil, fmt.Errorf("short TPM packet read: got %d bytes, expected %d", n, want)
	}

	out := make([]byte, want)
	copy(out, buf[:want])
	return out, nil
}

func isIdleProxyReadError(err error) bool {
	if err == nil {
		return false
	}
	if errors.Is(err, io.EOF) || errors.Is(err, syscall.EPIPE) || errors.Is(err, syscall.ENODEV) || errors.Is(err, syscall.EIO) {
		return true
	}
	if strings.Contains(err.Error(), "short TPM header") || strings.Contains(err.Error(), "short TPM packet read") {
		return true
	}
	return false
}

func isTransientRC(resp []byte) bool {
	if len(resp) < 10 {
		return false
	}
	rc := binary.BigEndian.Uint32(resp[6:10])
	return rc == tpm2RCRetry || rc == tpm2RCYielded || rc == tpm2RCTesting
}
