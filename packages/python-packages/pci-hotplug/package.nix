# Copyright 2022-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildPythonApplication,
  qemuqmp,
  systemd,
  setuptools,
}:
buildPythonApplication {
  pname = "pci-hotplug";
  version = "0.1";

  src = ./pci-hotplug;

  propagatedBuildInputs = [
    qemuqmp
    systemd
  ];
  doCheck = false;

  pyproject = true;
  build-system = [ setuptools ];

  meta = {
    description = "Qemu PCI hotplug helper";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
