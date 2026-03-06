// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

package main

import (
	"log"
	"net"
	"os"
	"strings"
)

func sdNotify(state string) {
	sock := os.Getenv("NOTIFY_SOCKET")
	if sock == "" {
		return
	}

	addr := sock
	if strings.HasPrefix(addr, "@") {
		addr = "\x00" + strings.TrimPrefix(addr, "@")
	}

	conn, err := net.DialUnix("unixgram", nil, &net.UnixAddr{Name: addr, Net: "unixgram"})
	if err != nil {
		log.Printf("sd_notify dial failed: %v", err)
		return
	}
	defer conn.Close()

	if _, err := conn.Write([]byte(state)); err != nil {
		log.Printf("sd_notify write failed: %v", err)
	}
}
