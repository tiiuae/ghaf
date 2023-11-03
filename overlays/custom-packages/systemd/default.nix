# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(final: prev: {
  systemd = prev.systemd.overrideAttrs (prevAttrs: {
    patches = prevAttrs.patches ++ [./systemd-timesyncd-disable-nscd.patch];
    postPatch =
      prevAttrs.postPatch
      + ''
        substituteInPlace units/systemd-timesyncd.service.in \
          --replace \
          "Environment=SYSTEMD_NSS_RESOLVE_VALIDATE=0" \
          "${final.lib.concatStringsSep "\n" [
          "Environment=LD_LIBRARY_PATH=$out/lib"
          "Environment=SYSTEMD_NSS_RESOLVE_VALIDATE=0"
        ]}"
      '';
  });
})
