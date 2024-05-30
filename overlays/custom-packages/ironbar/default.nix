# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{prev}:
prev.ironbar.overrideAttrs (old: rec {
  pname = "ironbar";
  version = "audio-launcher-fix";
  src = prev.fetchFromGitHub {
    owner = "JakeStanger";
    repo = "ironbar";
    rev = "0694f98012c8e4a10282aeb855961c8aee6efa0f";
    hash = "sha256-iKpvAMPpttLG2gYmBxVFOr2ipmquwrRE+J0zqo9FD7M=";
  };
  cargoDeps = old.cargoDeps.overrideAttrs (_: {
    name = "${pname}-vendor.tar.gz";
    inherit src;
    outputHash = "sha256-ogPTmSnOruUEHlHY7SvJdySGs0vRJ8NvxPnvnRXqGSw=";
  });
  patches = [
    ./0001-Ghaf-Use-audio-vm-for-volume.patch
  ];
  cargoHash = "";
  cargoSha256 = "";
})
