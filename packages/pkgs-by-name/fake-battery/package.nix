# Copyright 2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

{ lib, stdenv }:

stdenv.mkDerivation {
  pname = "fake-battery";
  version = "1.0";
  dontUnpack = true;

  installPhase = ''
    mkdir -p $out/fake_battery
    echo "Battery" > $out/fake_battery/type
    echo "Charging" > $out/fake_battery/status
    echo "50" > $out/fake_battery/capacity
    echo "1500000" > $out/fake_battery/energy_now
    echo "3000000" > $out/fake_battery/energy_full
    echo "500000" > $out/fake_battery/power_now
  '';

  meta = {
    description = "A fake battery sysfs directory for testing QEMU battery device";
    license = lib.licenses.asl20;
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
