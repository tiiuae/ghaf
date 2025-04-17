#!/usr/bin/env bash

set -euo pipefail

[[ ! -d linux ]] && git clone https://github.com/torvalds/linux.git --branch v6.4 --depth 1

pushd linux
  git reset --hard 6995e2de6891c724bfeb2db33d7b87775f913ad1
  git clean -xdf

  cp -Rv ../drivers/char/ivshmem ./drivers/char
  cp -v ../drivers/char/Kconfig ./drivers/char
  cat ../drivers/char/Makefile >> drivers/char/Makefile

  git add .
  git commit -m "ivshmem driver"
  git format-patch -k -1 -o ..
popd
