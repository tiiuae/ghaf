{ buildArmTrustedFirmware, fetchgit }:

{
  armTrustedFirmwareiMX8QM = buildArmTrustedFirmware rec {
    src = fetchgit {
      url = "https://source.codeaurora.org/external/imx/imx-atf";
      # tag: "lf_v2.6"
      rev = "c6a19b1a351308cc73443283f6aa56b2eff791b8";
      sha256 = "sha256-C046MrZBDFuzBdnjuPC2fAGtXzZjTWRrO8nYTf1rjeg=";
    };
    platform = "imx8qm";
    enableParallelBuilding = true;
    # To build with tee.bin use extraMakeFlags = [ "bl31 SPD=opteed" ];
    extraMakeFlags = [ "PIE_LDFLAGS=--no-warn-rwx-segments LDFLAGS=--no-warn-rwx-segments" "bl31" ];
    extraMeta.platforms = ["aarch64-linux"];
    filesToInstall = ["build/${platform}/release/bl31.bin"];
  };
}
