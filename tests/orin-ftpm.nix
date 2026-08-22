# SPDX-FileCopyrightText: 2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  self,
  lib,
  runCommand,
}:
let
  agx = self.nixosConfigurations."nvidia-jetson-orin-agx-debug".config;
  nx = self.nixosConfigurations."nvidia-jetson-orin-nx-debug".config;
  secureAgx = self.nixosConfigurations."nvidia-jetson-orin-agx-verity-debug".config;
  assertions = [
    {
      name = "Orin firmware embeds fTPM and enables the upstream driver";
      ok =
        agx.hardware.nvidia-jetpack.firmware.optee.ftpm.enable
        && nx.hardware.nvidia-jetpack.firmware.optee.ftpm.enable
        && builtins.hasAttr "ftpm-driver" agx.systemd.services
        && builtins.hasAttr "ftpm-driver" nx.systemd.services
        && !builtins.hasAttr "ghaf-load-ftpm-module" agx.systemd.services
        && !builtins.hasAttr "ghaf-load-ftpm-module" nx.systemd.services;
    }
    {
      name = "development EPS injection is disabled for secure boot";
      ok =
        agx.hardware.nvidia-jetpack.firmware.optee.ftpm.unsecureInjectEPS.enable
        && nx.hardware.nvidia-jetpack.firmware.optee.ftpm.unsecureInjectEPS.enable
        && !secureAgx.hardware.nvidia-jetpack.firmware.optee.ftpm.unsecureInjectEPS.enable;
    }
    {
      name = "upstream Linux uses the NVIDIA OP-TEE notification timeout";
      ok =
        builtins.any (patch: patch.name == "optee-notification-wait-timeout") agx.boot.kernelPatches
        && builtins.any (patch: patch.name == "optee-notification-wait-timeout") nx.boot.kernelPatches;
    }
    {
      name = "EK provisioning waits for the upstream fTPM driver";
      ok =
        lib.elem "ftpm-driver.service" agx.systemd.services.ghaf-provision-ek-certs.requires
        && lib.elem "ftpm-driver.service" nx.systemd.services.ghaf-provision-ek-certs.requires;
    }
  ];
  failed = map (assertion: assertion.name) (lib.filter (assertion: !assertion.ok) assertions);
in
assert lib.assertMsg (failed == [ ]) "Orin fTPM checks failed: ${lib.concatStringsSep "; " failed}";
runCommand "orin-ftpm" { } ''touch "$out"''
