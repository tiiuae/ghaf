{pkgs, ...}: {
  hardware.nvidia-jetpack = {
    enable = true;
    som = "orin-agx";
    carrierBoard = "devkit";
    modesetting.enable = true;
  };

  boot.kernelPatches = [
    # TODO: Remove when this patch gets merged to mainline.
    #       Patch to devicetree for getting rust-vmm based VMMs to work on
    #       NVIDIA Jetson Orin.
    {
      name = "gicv3-patch";
      patch = pkgs.fetchpatch {
        url = "https://github.com/OE4T/linux-tegra-5.10/commit/9ca6e31d17782e0cf5249eb59f71dcd7d8903303.patch";
	sha256 = "sha256-PzEQO6Jh/kkoGu329LCYdhdR8mNmo6KGKKVKOeMRZrI=";
      };
    }
  ];
}
