# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
#
{
  config,
  lib,
  ...
}:
let
  inherit (lib)
    mkOption
    types
    optionals
    optionalAttrs
    ;
in
{
  _file = ./qemu.nix;

  options.ghaf.qemu = {
    guivm = mkOption {
      type = types.attrs;
      default = { };
      description = "Extra qemu arguments for GuiVM";
    };
    audiovm = mkOption {
      type = types.attrs;
      default = { };
      description = "Extra qemu arguments for AudioVM";
    };
    netvm = mkOption {
      type = types.attrs;
      default = { };
      description = "Extra qemu arguments for NetVM";
    };
  };

  config = {
    ghaf.qemu.guivm = optionalAttrs (config.ghaf.type == "host") {
      microvm.qemu.extraArgs =
        optionals (config.ghaf.hardware.definition.type == "laptop") [
          # Lid Button
          "-device"
          "button,use-qmp=false,enable-procfs=true,probe_interval=2000"
          # Battery is 20 seconds too long enough for polling
          "-device"
          "battery,use-qmp=false,enable-sysfs=true,probe_interval=20000"
          # AC adapter
          "-device"
          "acad,use-qmp=false,enable-sysfs=true,probe_interval=5000"
        ]
        ++ optionals (builtins.hasAttr "gui-vm" config.ghaf.hardware.passthrough.qemuExtraArgs) config.ghaf.hardware.passthrough.qemuExtraArgs.gui-vm;
    };
    ghaf.qemu.audiovm = optionalAttrs (config.ghaf.type == "host") {
      microvm.qemu.extraArgs =
        optionals (builtins.hasAttr "audio-vm" config.ghaf.hardware.passthrough.qemuExtraArgs) config.ghaf.hardware.passthrough.qemuExtraArgs.audio-vm
        ++ optionals (config.ghaf.hardware.definition.type == "laptop") [
          "-device"
          "battery,use-qmp=false,enable-sysfs=true,probe_interval=20000"
          "-device"
          "acad,use-qmp=false,enable-sysfs=true,probe_interval=5000"
        ]
        ++ optionals (config.ghaf.hardware.definition.audio.acpiPath != null) [
          "-acpitable"
          "file=${config.ghaf.hardware.definition.audio.acpiPath}"
        ];
    };
    ghaf.qemu.netvm = optionalAttrs (config.ghaf.type == "host") {
      microvm.qemu.extraArgs = optionals (builtins.hasAttr "net-vm" config.ghaf.hardware.passthrough.qemuExtraArgs) config.ghaf.hardware.passthrough.qemuExtraArgs.net-vm;
    };
  };
}
