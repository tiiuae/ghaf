# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
(final: prev: {
  systemd = let
    # The patch has been added nixpkgs upstream, don't override attributes if
    # the patch is already present.
    #
    # https://github.com/NixOS/nixpkgs/pull/239201
    shouldOverride = !(final.lib.lists.any (p: final.lib.strings.hasSuffix "timesyncd-disable-NSCD-when-DNSSEC-validation-is-dis.patch" (toString p)) prev.systemd.patches);
  in
    prev.systemd.overrideAttrs (prevAttrs:
      final.lib.optionalAttrs shouldOverride {
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
