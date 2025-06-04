# Copyright 2022-2024 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  stdenv,
  lib,
  kernel ? null,
  shmSlots ? null,
  memSize ? null,
  fetchFromGitHub,
  debug ? false,
  clientServiceWithID ? null,
  ...
}:
stdenv.mkDerivation {
  name = "sec_shm-driver-${kernel.version}";

  src = fetchFromGitHub {
    owner = "tiiuae";
    repo = "shmsockproxy";
    rev = "2c0a4bad482ec2e076aee9a1ce550b3d9891f05e";
    sha256 = "sha256-4cXNdG1k45/mF+yqBsfvfYkRK6N9kgsGeeqGB6mRSj4=";
  };
  /*
    Convert clientServiceWithID into C structure to be
    included into on-host driver's source code.
    The structure is put into the secshm_config.h and
    is used to generate the client table and service table
    for the driver.
  */
  patchPhase =
    let
      pow = base: exp: if exp == 0 then 1 else base * (pow base (exp - 1));

      clientNames = lib.unique (map (x: x.client) clientServiceWithID);
      serviceNames = lib.unique (map (x: x.service) clientServiceWithID);

      clientTable = builtins.concatStringsSep ",\n  " (
        map (
          client:
          let
            mask = builtins.foldl' (
              acc: x: if x.client == client then acc + (pow 2 x.id) else acc
            ) 0 clientServiceWithID;
          in
          "  { .name = \"${client}\", .bitmask = 0x${lib.toHexString mask}, .pid = 0 }"
        ) clientNames
      );

      serviceTable = builtins.concatStringsSep ",\n  " (
        map (
          service:
          let
            mask = builtins.foldl' (
              acc: x: if x.service == service then acc + (pow 2 x.id) else acc
            ) 0 clientServiceWithID;
          in
          "  { .name = \"${service}-vm\", .bitmask = 0x${lib.toHexString mask}, .pid = 0 }"
        ) serviceNames
      );
    in
    ''
        cat > secshm_config.h <<EOF
        #ifndef SECSHM_CONFIG_H
        #define SECSHM_CONFIG_H

        #define SHM_SLOTS ${builtins.toString shmSlots}
        #define SHM_SIZE ${builtins.toString memSize}

        struct client_entry {
          const char* name;
          const long long int bitmask;
          pid_t pid;
        };

        static struct client_entry client_table[] = {
          ${clientTable},
          ${serviceTable}
        };

        #define CLIENT_TABLE_SIZE ${
          builtins.toString (builtins.length clientNames + builtins.length serviceNames)
        }

        #endif // SECSHM_CONFIG_H
      EOF
    '';

  sourceRoot = "source/secure_shmem";
  hardeningDisable = [
    "pic"
    "format"
  ];
  nativeBuildInputs = kernel.moduleBuildDependencies;

  makeFlags =
    [
      "KDIR=${kernel.dev}/lib/modules/${kernel.modDirVersion}/build"
      "MODULEDIR=$(out)/lib/modules/${kernel.modDirVersion}/kernel/drivers/char"
      "ARCH=${stdenv.hostPlatform.linuxArch}"
      "INSTALL_MOD_PATH=${placeholder "out"}"
    ]
    ++ lib.optionals (stdenv.hostPlatform != stdenv.buildPlatform) [
      "CROSS_COMPILE=${stdenv.cc}/bin/${stdenv.cc.targetPrefix}"
    ]
    ++ lib.optionals debug [
      "EXTRA_CFLAGS=-DDEBUG_ON"
    ];

  CROSS_COMPILE = lib.optionalString (
    stdenv.hostPlatform != stdenv.buildPlatform
  ) "${stdenv.cc}/bin/${stdenv.cc.targetPrefix}";

  meta = with lib; {
    description = "Secured shared memory on host Linux kernel module";
    platforms = [
      "x86_64-linux"
      "aarch64-linux"
    ];
  };
}
