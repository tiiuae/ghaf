// SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
// SPDX-License-Identifier: Apache-2.0

package main

/*
#cgo pkg-config: tss2-tcti-tabrmd
#include <stdint.h>
#include <stdlib.h>
#include <string.h>
#include <tss2/tss2_tcti.h>

TSS2_RC Tss2_Tcti_Tabrmd_Init(TSS2_TCTI_CONTEXT *tcti_context, size_t *size, const char *conf);

static uint32_t tcti_init(void **out_ctx) {
  const char *conf = "bus_type=system";
  size_t ctx_size = 0;
  TSS2_RC rc = Tss2_Tcti_Tabrmd_Init(NULL, &ctx_size, conf);
  if (rc != TSS2_RC_SUCCESS || ctx_size == 0) {
    return rc;
  }

  TSS2_TCTI_CONTEXT *ctx = (TSS2_TCTI_CONTEXT *)calloc(1, ctx_size);
  if (!ctx) {
    return 0xFFFFFFFF;
  }

  rc = Tss2_Tcti_Tabrmd_Init(ctx, &ctx_size, conf);
  if (rc != TSS2_RC_SUCCESS) {
    free(ctx);
    return rc;
  }

  *out_ctx = ctx;
  return TSS2_RC_SUCCESS;
}

static void tcti_finalize(void *ctx) {
  if (!ctx) {
    return;
  }
  Tss2_Tcti_Finalize((TSS2_TCTI_CONTEXT *)ctx);
  free(ctx);
}

static uint32_t tcti_transmit(void *ctx, size_t len, uint8_t *buf) {
  return Tss2_Tcti_Transmit((TSS2_TCTI_CONTEXT *)ctx, len, buf);
}

static uint32_t tcti_receive(void *ctx, size_t *len, uint8_t *buf) {
  return Tss2_Tcti_Receive((TSS2_TCTI_CONTEXT *)ctx, len, buf, TSS2_TCTI_TIMEOUT_BLOCK);
}

static uint32_t rc_try_again(void) {
  return TSS2_TCTI_RC_TRY_AGAIN;
}

static uint32_t rc_insufficient_buffer(void) {
  return TSS2_TCTI_RC_INSUFFICIENT_BUFFER;
}
*/
import "C"

import (
	"fmt"
	"time"
	"unsafe"
)

func tctiInit() (unsafe.Pointer, error) {
	var ctx unsafe.Pointer
	rc := uint32(C.tcti_init((*unsafe.Pointer)(unsafe.Pointer(&ctx))))
	if rc != 0 || ctx == nil {
		return nil, fmt.Errorf("Tcti_Tabrmd_Init failed rc=0x%08x", rc)
	}
	return ctx, nil
}

func tctiFinalize(ctx unsafe.Pointer) {
	C.tcti_finalize(ctx)
}

func tctiTransact(ctx unsafe.Pointer, req []byte) ([]byte, error) {
	if len(req) == 0 {
		return nil, fmt.Errorf("empty request")
	}

	rc := uint32(C.tcti_transmit(ctx, C.size_t(len(req)), (*C.uint8_t)(unsafe.Pointer(&req[0]))))
	if rc != 0 {
		return nil, fmt.Errorf("Transmit failed rc=0x%08x", rc)
	}

	for {
		resp := make([]byte, 4096)
		got := C.size_t(len(resp))
		rc = uint32(C.tcti_receive(ctx, &got, (*C.uint8_t)(unsafe.Pointer(&resp[0]))))

		if rc == uint32(C.rc_try_again()) {
			time.Sleep(10 * time.Millisecond)
			continue
		}

		if rc == uint32(C.rc_insufficient_buffer()) && int(got) > len(resp) && int(got) <= maxTPMPacketSize {
			resp = make([]byte, int(got))
			got = C.size_t(len(resp))
			rc = uint32(C.tcti_receive(ctx, &got, (*C.uint8_t)(unsafe.Pointer(&resp[0]))))
			if rc == uint32(C.rc_try_again()) {
				time.Sleep(10 * time.Millisecond)
				continue
			}
		}

		if rc != 0 {
			return nil, fmt.Errorf("Receive failed rc=0x%08x", rc)
		}

		n := int(got)
		if n <= 0 || n > maxTPMPacketSize {
			return nil, fmt.Errorf("invalid response size %d", n)
		}

		return resp[:n], nil
	}
}
