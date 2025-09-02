# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildPythonApplication,
  qemu-qmp,
  systemd,
  setuptools,
}:
buildPythonApplication {
  pname = "hotplug";
  version = "0.1";

  src = ./hotplug;

  propagatedBuildInputs = [
    qemu-qmp
    systemd
  ];
  doCheck = false;

  pyproject = true;
  build-system = [ setuptools ];

  meta = {
    description = "Qemu hotplug helper for PCI and USB devices";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
