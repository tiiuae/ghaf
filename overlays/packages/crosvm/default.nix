{ crosvm, lib, stdenv, wayland-protocols, ... }:

  crosvm.overrideAttrs ({ ... }: {
    prePatch = lib.optionalString stdenv.isAarch64 ''
      substituteInPlace .cargo/config.toml \
        --replace "[target.aarch64-unknown-linux-gnu]" "" \
        --replace "linker = \"aarch64-linux-gnu-gcc\"" ""

      substituteInPlace gpu_display/build.rs \
        --replace "/usr/share/wayland-protocols" \
          "${wayland-protocols}/share/wayland-protocols"
  '';
})
