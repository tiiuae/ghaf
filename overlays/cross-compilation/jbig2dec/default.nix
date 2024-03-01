# Copyright 2023-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{prev}:
prev.jbig2dec.overrideAttrs (_oa: {
  configureScript = "./autogen.sh";
  preConfigure = "";
})
