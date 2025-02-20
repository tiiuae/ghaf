# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  python3Packages,
  fetchFromGitHub,
  qemuqmp,
}:
python3Packages.buildPythonApplication {
  pname = "vhotplug";
  version = "0.1";

  propagatedBuildInputs = [
    python3Packages.pyudev
    python3Packages.psutil
    python3Packages.inotify-simple
    qemuqmp
  ];

  doCheck = false;

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "vhotplug";
    rev = "dc91f43d90da24782bd32cfc5a79afc9fe74d9e6";
    hash = "sha256-qyLEUNoXHzj5BjUV0i7YjWA9U206J/BGwgvLkni0kIs=";
  };

  meta = {
    description = "Virtio Hotplug";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
