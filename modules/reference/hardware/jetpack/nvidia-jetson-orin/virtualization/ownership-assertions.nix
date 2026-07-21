# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}:
let
  inherit (import ./passthrough/payload { inherit lib pkgs; }) capabilities mkPayload;
  mv = config.ghaf.virtualization.microvm;
  gpuOn = mv.gpuvm.enable or false;
  dispOn = mv.dispvm.enable or false;
  guiOn = mv.guivm.enable or false;

  gpuDevs = lib.optionals gpuOn (mkPayload capabilities.gpuvm).hostDevices;
  dispDevs = lib.optionals dispOn [
    "b0000000.scanout_p"
    "b8000000.dispram_lo_p"
    "200000000.dispram_hi_p"
    "13830000.disp_caps_pt"
    "13870000.disp_chan_pt"
  ];
  overlap = lib.intersectLists gpuDevs dispDevs;

  displayOwners = lib.optional dispOn "disp-vm" ++ lib.optional guiOn "gui-vm";
in
{
  assertions = [
    {
      assertion = overlap == [ ];
      message = "Orin passthrough: gpu-vm and disp-vm claim the same VFIO device(s): ${lib.concatStringsSep ", " overlap}. Every physical device needs exactly one active owner.";
    }
    {
      assertion = lib.length displayOwners <= 1;
      message = "Orin passthrough: more than one display owner active (${lib.concatStringsSep ", " displayOwners}); exactly one VM may hold DCE/scanout and set GHAF_DCE_GUEST.";
    }
    {
      # spec item 5: GA10B and host1x share an owner in every supported cap
      assertion = lib.all (c: c.gpu -> c.host1x) (lib.attrValues capabilities);
      message = "Orin capability set invalid: a definition owns GA10B without physical host1x.";
    }
    {
      # spec item 6: media engines live with the host1x owner
      assertion = lib.all (c: c.media -> c.host1x) (lib.attrValues capabilities);
      message = "Orin capability set invalid: media engines assigned without host1x.";
    }
    {
      # spec item 9: no-syncpoint path only where display but no host1x (disp-vm)
      assertion = lib.all (c: c.noSyncpointDisplay -> (c.display && !c.host1x)) (
        lib.attrValues capabilities
      );
      message = "Orin capability set invalid: no-syncpoint NVKMS selected outside the display-only (disp-vm) role.";
    }
  ];
}
