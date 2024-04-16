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
    inherit (pkgs.nvidia-jetpack) l4tVersion opteeClient;
    inherit (config.hardware.nvidia-jetpack.devicePkgs) taDevKit;

    opteeSource = pkgs.fetchgit {
      url = "https://nv-tegra.nvidia.com/r/tegra/optee-src/nv-optee";
      rev = "jetson_${l4tVersion}";
      sha256 = "sha256-jJOMig2+9FlKA9gJUCH/dva7ZtAq1typZSNGKyM7tlg=";
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
      exec "${pkgs.opensc}/bin/pkcs11-tool" --module "${opteeClient}/lib/libckteec.so" $@
    '';
  in {
    hardware.nvidia-jetpack.firmware.optee.supplicant.trustedApplications = let
      xTestTaDir = "${opteeXtest}/ta";
      xTestTaPaths =
        builtins.map (ta: {
          name = ta;
          path = xTestTaDir + "/" + ta;
        }) [
          # List of OP-TEE's xtest required TA's
          #
          # A short guide about a ways of constructing xtest TA list
          #
          # A) Run xtest and based on errors add TAs to the list
          #   - Run xtest and you might see following error
          #       E/LD:  init_elf:453 sys_open_ta_bin(cb3e5ba0-adf1-11e0-998b-0002a5d5c51b)
          #       E/TC:?? 0 ldelf_init_with_ldelf:131 ldelf failed with res: 0xffff0008
          #     --> Add cb3e5ba0-adf1-11e0-998b-0002a5d5c51b.ta into list and repeat
          #
          # B) From OP-TEE's xtest sources https://github.com/OP-TEE/optee_test
          #    - Navigate into optee_test repo and run
          #    $ find ta -path ta/supp_plugin -prune -o -name Makefile -exec grep -oP 'BINARY = \K.*' {} \;
          #    --> Above comaand produces a list of TAs UUID
          #    --> It does not produce all UUID due some of them are hardcode into source files
          #    --> It produce more TA than needed
          #
          # C) At "find ./out -name "*.ta"" into opteeXtest derivation installPhase
          #    and uild package with "-L"-flag
          #     --> Scroll output until find TAs
          #         ./out/ta/crypt/cb3e5ba0-adf1-11e0-998b-0002a5d5c51b.ta
          #         ./out/ta/concurrent_large/5ce0c432-0ab0-40e5-a056-782ca0e6aba2.ta
          #
          # Below list used option C

          "cb3e5ba0-adf1-11e0-998b-0002a5d5c51b.ta"
          "5ce0c432-0ab0-40e5-a056-782ca0e6aba2.ta"
          "e626662e-c0e2-485c-b8c8-09fbce6edf3d.ta"
          "c3f6e2c0-3548-11e1-b86c-0800200c9a66.ta"
          "873bcd08-c2c3-11e6-a937-d0bf9c45c61c.ta"
          "b689f2a7-8adf-477a-9f99-32e90c0ad0a2.ta"
          "a4c04d50-f180-11e8-8eb2-f2801f1b9fd1.ta"
          "25497083-a58a-4fc5-8a72-1ad7b69b8562.ta"
          "731e279e-aafb-4575-a771-38caa6f0cca6.ta"
          "5b9e0e40-2636-11e1-ad9e-0002a5d5c51b.ta"
          "380231ac-fb99-47ad-a689-9e017eb6e78a.ta"
          "d17f73a0-36ef-11e1-984a-0002a5d5c51b.ta"
          "614789f2-39c0-4ebf-b235-92b32ac107ed.ta"
          "e6a33ed4-562b-463a-bb7e-ff5e15a493c8.ta"
          "e13010e0-2ae1-11e5-896a-0002a5d5c51b.ta"
          "528938ce-fc59-11e8-8eb2-f2801f1b9fd1.ta"
          "ffd2bded-ab7d-4988-95ee-e4962fff7154.ta"
          "b3091a65-9751-4784-abf7-0298a7cc35ba.ta"
          "f157cda0-550c-11e5-a6fa-0002a5d5c51b.ta"
          "5c206987-16a3-59cc-ab0f-64b9cfc9e758.ta"
          "a720ccbb-51da-417d-b82e-e5445d474a7a.ta"
        ];
      pkcs11TaPath = {
        name = "fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta";
        path = "${pcks11Ta}/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta";
      };
      paths =
        lib.optionals config.ghaf.hardware.nvidia.orin.optee.xtest xTestTaPaths
        ++ lib.optional config.ghaf.hardware.nvidia.orin.optee.pkcs11.enable pkcs11TaPath;
    in [(pkgs.linkFarm "optee-load-path" paths)];

    environment.systemPackages =
      (lib.optional config.ghaf.hardware.nvidia.orin.optee.pkcs11-tool pkcs11-tool-optee)
      ++ (lib.optional config.ghaf.hardware.nvidia.orin.optee.xtest opteeXtest);
  }
)
