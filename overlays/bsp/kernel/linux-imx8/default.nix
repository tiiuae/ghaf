{ pkgs, ... } @ args:

with pkgs;

buildLinux (args // rec {
  version = "5.15.71";
  nxp_ref = "refs/tags/lf-5.15.71-2.2.0";

  # modDirVersion needs to be x.y.z, will automatically add .0 if needed
  modDirVersion = version;

  defconfig = "imx_v8_defconfig";

  kernelPatches = [
  ];

  autoModules = false;

  extraConfig = ''
    CRYPTO_TLS m
    TLS y
    MD_RAID0 m
    MD_RAID1 m
    MD_RAID10 m
    MD_RAID456 m
    DM_VERITY m
    LOGO y
    FRAMEBUFFER_CONSOLE_DEFERRED_TAKEOVER n
    FB_EFI n
    EFI_STUB y
    EFI y
    VIRTIO y
    VIRTIO_PCI y
    VIRTIO_BLK y
    DRM_VIRTIO_GPU y
    EXT4_FS y
    USBIP_CORE m
    USBIP_VHCI_HCD m
    USBIP_HOST m
    USBIP_VUDC m
  '';

  src = builtins.fetchGit {
    url = "https://github.com/nxp-imx/linux-imx";
    ref = nxp_ref;
  };
} // (args.argsOverride or { }))
