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
    owner = "gngram";
    repo = "vhotplug";
    rev = "be91564eeb44eec704ea5345f405fc60d26c3f07";
    sha256 = "sha256-FpiDe2jPEpL7ii7QPnTZt7GfT64OmJSWZmOgqkI2vGo=";
  };

  meta = {
    description = "Virtio Hotplug";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
