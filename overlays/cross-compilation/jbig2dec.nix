# Copyright 2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(_final: prev: {
  jbig2dec = prev.jbig2dec.overrideAttrs (_oa: {
    configureScript = "./autogen.sh";
    preConfigure = "";
  });
})
