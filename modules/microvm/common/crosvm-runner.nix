# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  microvmFlake,
}:
let
  microvmConfig = config.microvm // {
    inherit (config.networking) hostName;
    hypervisor = "crosvm";
  };
  upstreamConfig = microvmConfig // {
    devices = lib.filter ({ bus, ... }: bus != "platform") microvmConfig.devices;
  };
  upstreamRunner = microvmFlake.lib.buildRunner {
    inherit pkgs;
    microvmConfig = upstreamConfig;
    inherit (config.system.build) toplevel;
  };
  inherit (microvmConfig) hostName vmHostPackages;
  inherit (import "${microvmFlake}/lib/volumes.nix" { pkgs = vmHostPackages; }) createVolumesScript;
  hypervisorConfig = import ./crosvm-command.nix {
    inherit pkgs microvmConfig macvtapFds;
    linuxTarget = pkgs.linux.target or pkgs.stdenv.hostPlatform.linux-kernel.target;
  };
  inherit
    (microvmFlake.lib.makeMacvtap {
      inherit microvmConfig hypervisorConfig;
    })
    openMacvtapFds
    macvtapFds
    ;
  inherit (hypervisorConfig) command canShutdown shutdownCommand;
  preStart = hypervisorConfig.preStart or microvmConfig.preStart;
  execArg = lib.optionalString microvmConfig.prettyProcnames ''-a "microvm@${hostName}"'';
  runScript = vmHostPackages.writeShellScript "microvm-${hostName}-run" ''
    set -eou pipefail
    ${preStart}
    ${createVolumesScript microvmConfig.volumes}
    ${lib.optionalString (hypervisorConfig.requiresMacvtapAsFds or false) openMacvtapFds}
    runtime_args=${
      lib.optionalString (microvmConfig.extraArgsScript != null) ''
        $(${microvmConfig.extraArgsScript})
      ''
    }

    exec ${execArg} ${command} ''${runtime_args:-}
  '';
  shutdownScript =
    if canShutdown then
      vmHostPackages.writeShellScript "microvm-${hostName}-shutdown" shutdownCommand
    else
      null;
  platformDevices = lib.filter ({ bus, ... }: bus == "platform") microvmConfig.devices;
in
vmHostPackages.buildPackages.runCommand "microvm-crosvm-${hostName}"
  {
    inherit (upstreamRunner) meta;
    inherit (upstreamRunner) passthru;
  }
  ''
    mkdir -p "$out"
    cp -rs ${upstreamRunner}/* "$out/"
    chmod -R u+w "$out"
    rm "$out/bin/microvm-run"
    ln -s ${runScript} "$out/bin/microvm-run"
    ${lib.optionalString canShutdown ''
      rm "$out/bin/microvm-shutdown"
      ln -s ${shutdownScript} "$out/bin/microvm-shutdown"
    ''}
    ${lib.optionalString (platformDevices != [ ]) ''
      ${lib.concatMapStringsSep "\n" ({ path, ... }: ''
        echo ${lib.escapeShellArg path} >> "$out/share/microvm/platform-devices"
      '') platformDevices}
    ''}
  ''
