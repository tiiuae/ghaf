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
  dispDevs = lib.optionals dispOn (mkPayload capabilities.dispvm).hostDevices;
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
      assertion = lib.all (c: c.gpu -> c.host1x) (lib.attrValues capabilities);
      message = "Orin capability set invalid: a definition owns GA10B without physical host1x.";
    }
    {
      assertion = lib.all (c: c.media -> c.host1x) (lib.attrValues capabilities);
      message = "Orin capability set invalid: media engines assigned without host1x.";
    }
    {
      assertion = lib.all (c: c.noSyncpointDisplay -> (c.display && !c.host1x)) (
        lib.attrValues capabilities
      );
      message = "Orin capability set invalid: no-syncpoint NVKMS selected outside the display-only (disp-vm) role.";
    }
    {
      assertion = !(guiOn && (gpuOn || dispOn));
      message = "Orin: gui-vm cannot be enabled alongside gpu-vm or disp-vm; accelerated mode owns every combined capability exclusively.";
    }
    {
      assertion =
        let
          displayOn = dispOn || guiOn;
        in
        (displayOn && (lib.length displayOwners == 1)) || (!displayOn && displayOwners == [ ]);
      message = "Orin: exactly one active VM must set GHAF_DCE_GUEST when display is enabled, and none when it is disabled.";
    }
    {
      # Compute mode releases scanout to its display peer.
      assertion = !gpuOn || dispOn || guiOn;
      message = "Orin: gpu-vm (compute) releases the display scanout carveout and requires a display owner on the same host (enable disp-vm, or use the accelerated gui-vm). A standalone gpu-vm leaves scanout unowned.";
    }
    {
      assertion = !dispOn || gpuOn;
      message = "Orin: disp-vm requires gpu-vm on the same host because it reuses gpu-vm's host passthrough plumbing. Enable both for split mode, or use the accelerated gui-vm.";
    }
  ];
}
