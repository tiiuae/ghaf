# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  dtb,
  payload,
  policy,
}:
{
  inputs,
  lib,
  pkgs,
  ...
}:
{
  imports = [ inputs.jetpack-nixos.nixosModules.orin-virtualization ];

  hardware.nvidia-jetpack.virtualization.gpuPassthroughGuest = {
    enable = true;
    role = policy;
  };

  services.udev.extraRules = lib.mkIf (policy == "compute") ''
    ENV{DEVNAME}=="/dev/nvgpu/igpu0/ctrl", TAG+="systemd"
  '';

  systemd.services.gpu-vm-node-access = lib.mkIf (policy == "compute") {
    description = "Grant video-group access to the passed-through GPU nodes";
    wantedBy = [ "multi-user.target" ];
    requires = [ "dev-nvgpu-igpu0-ctrl.device" ];
    after = [ "dev-nvgpu-igpu0-ctrl.device" ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
    };
    script = ''
      for node in /dev/nvgpu /dev/nvhost-* /dev/nvmap; do
        [ -e "$node" ] || continue
        chgrp -R video "$node"
        chmod -R g+rw "$node"
      done
    '';
  };

  users.users.ghaf.extraGroups = lib.optionals (policy == "compute") [ "video" ];
  ghaf.virtualization.qemu.package = lib.mkForce pkgs.ghaf-nvidia-qemu-bpmp-gpu;
  microvm.qemu.extraArgs = [
    "-dtb"
    "${dtb}/${payload.dtbName}"
  ]
  ++ payload.vfioArgs;
}
