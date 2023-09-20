{jetpack-nixos}: (
  {
    pkgs,
    config,
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
    pcks11Ta = stdenv.mkDerivation {
      pname = "pkcs11";
      version = l4tVersion;
      src = pkgs.fetchgit {
        url = "https://nv-tegra.nvidia.com/r/tegra/optee-src/nv-optee";
        rev = "jetson_${l4tVersion}";
        sha256 = "sha256-44RBXFNUlqZoq3OY/OFwhiU4Qxi4xQNmetFmlrr6jzY=";
      };
      nativeBuildInputs = [(pkgs.buildPackages.python3.withPackages (p: [p.cryptography]))];
      makeFlags = [
        "-C optee/optee_os/ta/pkcs11"
        "CROSS_COMPILE=${stdenv.cc.targetPrefix}"
        "TA_DEV_KIT_DIR=${taDevKit}/export-ta_arm64"
        "CFG_PKCS11_TA_TOKEN_COUNT=3"
        "CFG_PKCS11_TA_HEAP_SIZE=32768"
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
  in {
    hardware.nvidia-jetpack.firmware.optee.clientLoadPath = pkgs.linkFarm "optee-load-path" [
      {
        # By default, tee_supplicant expects to find the TAs under
        # optee_armtz
        name = "optee_armtz/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta";
        path = "${pcks11Ta}/fd02c9da-306c-48c7-a49c-bbd827ae86ee.ta";
      }
    ];
  }
)
