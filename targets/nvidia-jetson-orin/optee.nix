# SPDX-FileCopyrightText: 2022-2023 TII (SSRC) and the Ghaf contributors
#
# SPDX-License-Identifier: Apache-2.0
{jetpack-nixos}: (
  {
    pkgs,
    config,
    lib,
    ...
  }: let
    # TODO: Refactor this later, if this gets proper implementation on the
    # 	    jetpack-nixos
    stdenv = pkgs.gcc9Stdenv;
    inherit (jetpack-nixos.legacyPackages.${config.nixpkgs.buildPlatform.system}) bspSrc l4tVersion;
    inherit
      (pkgs.callPackages (jetpack-nixos + "/pkgs/optee") {
        inherit bspSrc l4tVersion stdenv;
      })
      opteeClient
      ;
    inherit (config.hardware.nvidia-jetpack.devicePkgs) taDevKit teeSupplicant;

    opteeSource = pkgs.fetchgit {
      url = "https://nv-tegra.nvidia.com/r/tegra/optee-src/nv-optee";
      rev = "jetson_${l4tVersion}";
      sha256 = "sha256-44RBXFNUlqZoq3OY/OFwhiU4Qxi4xQNmetFmlrr6jzY=";
    };

    opteeXtest = stdenv.mkDerivation {
      pname = "optee_xtest";
      version = l4tVersion;
      src = opteeSource;
      nativeBuildInputs = [(pkgs.buildPackages.python3.withPackages (p: [p.cryptography]))];
      postPatch = ''
        patchShebangs --build $(find optee/optee_test -type d -name scripts -printf '%p ')
      '';
      makeFlags = [
        "-C optee/optee_test"
        "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
        "OPTEE_CLIENT_EXPORT=${opteeClient}"
        "TA_DEV_KIT_DIR=${taDevKit}/export-ta_arm64"
        "O=$(PWD)/out"
      ];
      installPhase = ''
        runHook preInstall
        install -Dm 755 ./out/xtest/xtest $out/bin/xtest
        mkdir $out/ta
        find ./out -name "*.ta" -exec cp {} $out/ta/ \;
        runHook postInstall
      '';
    };
    pcks11Ta = stdenv.mkDerivation {
      pname = "pkcs11";
      version = l4tVersion;
      src = opteeSource;
      nativeBuildInputs = [(pkgs.buildPackages.python3.withPackages (p: [p.cryptography]))];
      makeFlags = [
        "-C optee/optee_os/ta/pkcs11"
        "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
        "TA_DEV_KIT_DIR=${taDevKit}/export-ta_arm64"
        "CFG_PKCS11_TA_TOKEN_COUNT=${builtins.toString config.ghaf.hardware.nvidia.orin.optee.pkcs11.tokenCount}"
        "CFG_PKCS11_TA_HEAP_SIZE=${builtins.toString config.ghaf.hardware.nvidia.orin.optee.pkcs11.heapSize}"
        "CFG_PKCS11_TA_AUTH_TEE_IDENTITY=y"
        "CFG_PKCS11_TA_ALLOW_DIGEST_KEY=y"
        "OPTEE_CLIENT_EXPORT=${opteeClient}"
        "O=$(PWD)/out"
      ];
      installPhase = ''
        runHook preInstall
        install -Dm755 -t $out out/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta
        runHook postInstall
      '';
    };
    pkcs11-tool-optee = pkgs.writeShellScriptBin "pkcs11-tool-optee" ''
      exec "${pkgs.opensc}/bin/pkcs11-tool" --module "${teeSupplicant}/lib/libckteec.so" $@
    '';
  in {
    hardware.nvidia-jetpack.firmware.optee.clientLoadPath =
      pkgs.linkFarm "optee-load-path"
      (
        (
          if config.ghaf.hardware.nvidia.orin.optee.xtest
          then
            (
              let
                xTestTaDir = "${opteeXtest}/ta";
              in
                builtins.map (
                  ta: {
                    name = "optee_armtz" + "/" + ta;
                    path = xTestTaDir + "/" + ta;
                  }
                ) (builtins.attrNames (builtins.readDir xTestTaDir))
            )
          else []
        )
        ++ (
          if config.ghaf.hardware.nvidia.orin.optee.pkcs11.enable
          then [
            {
              name = "optee_armtz/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta";
              path = "${pcks11Ta}/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta";
            }
          ]
          else []
        )
      );

    environment.systemPackages =
      []
      ++ (lib.optional config.ghaf.hardware.nvidia.orin.optee.pkcs11-tool pkcs11-tool-optee)
      ++ (lib.optional config.ghaf.hardware.nvidia.orin.optee.xtest opteeXtest);
  }
)
