# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
# Wire the Ghaf-patched QEMU into microvm.nix so all VMs use it.
#
{ config, inputs, ... }:
{
  imports = [ inputs.self.nixosModules.ghaf-qemu ];

  microvm.qemu.package = config.ghaf.virtualization.qemu.package;
}
