# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  buildPythonApplication,
  fetchFromGitHub,
  qemuqmp,
  pyudev,
  psutil,
  inotify-simple,
}:
buildPythonApplication {
  pname = "vhotplug";
  version = "0.1";

  propagatedBuildInputs = [
    pyudev
    psutil
    inotify-simple
    qemuqmp
  ];

  doCheck = false;

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "vhotplug";
    rev = "6fa43f4e64ab130632a3f88eaf3d53108a0cc3b5";
    hash = "sha256-B0VQ+sJhmU77UOf87SWu2rVrKJq8kweXYkBd0A21Ipo=";
  };

  meta = {
    description = "Virtio Hotplug";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
