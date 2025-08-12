# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ prev }:
prev.intel-gpu-tools.overrideAttrs {
  patches = [ ./feat-dynamically-detect-iGPU-PCI-address-at-runtime.patch ];
}
