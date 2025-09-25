# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{ prev }:
prev.tpm2-tools.override {
  abrmdSupport = false;
}
