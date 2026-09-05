# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  buildLinux,
  structuredExtraConfig ? { },
  argsOverride ? { },
  fetchFromGitHub,
  ...
}@args:
buildLinux (
  args
  // {
    pname = "linux-pkvm-jetson";
    version = "6.18.0";
    extraMeta.branch = "pkvm-v6.18-dev";

    defconfig = "defconfig";

    src = fetchFromGitHub {
      owner = "tiiuae";
      repo = "linux-pkvm-jetson";
      rev = "37b706a21b55b3183faef75eb594dd249913826a"; # pkvm-v6.18-dev (29-06-2026)
      hash = "sha256-BWfA7B9piYX6Gq+92f1PPqPjc9onS5DI+3qDVqfHDWs=";
    };
    autoModules = false;
    ignoreConfigErrors = true;

    # TODO try without common config
    enableCommonConfig = true;

    features = { };

    kernelPatches = [
      {
        name = "usb: host: Export xhci_irq";
        patch = ./0001-usb-host-Export-xhci_irq.patch;
      }
      {
        name = "Hack-to-select-VIDEOBUF2_DMA_CONTIG";
        patch = ./0002-Hack-to-select-VIDEOBUF2_DMA_CONTIG.patch;
      }
    ]
    ++ args.kernelPatches or [ ];

    structuredExtraConfig =
      with lib.kernel;
      {
        # Override the default CMA_SIZE_MBYTES=32M setting in common-config.nix with the default from tegra_defconfig
        # Otherwise, nvidia's driver craps out
        CMA_SIZE_MBYTES = lib.mkForce (freeform "64");

        ### So nat.service and firewall work ###
        NF_TABLES = module; # This one should probably be in common-config.nix
        # this NFT_NAT is not actually being set. when build with enableCommonConfig = false;
        # and not ignoreConfigErrors = true; it will fail with error about unused option
        # unused means that it wanted to set it as a module, but make oldconfig didn't ask it about that option,
        # so it didn't get a chance to set it.
        NFT_NAT = module;
        NFT_MASQ = module;
        NFT_REJECT = module;
        NFT_COMPAT = module;
        NFT_LOG = module;
        NFT_COUNTER = module;

        # search for "ip46tables" in nixpkgs and find all the -m options.
        # Enable the corresponding Kconfigs
        # TODO: nixpkgs should turn these on themselves.
        NETFILTER_XT_MATCH_PKTTYPE = module;
        NETFILTER_XT_MATCH_COMMENT = module;
        NETFILTER_XT_MATCH_CONNTRACK = module;
        NETFILTER_XT_MATCH_LIMIT = module;
        NETFILTER_XT_MATCH_MARK = module;
        NETFILTER_XT_MATCH_MULTIPORT = module;

        IP_NF_MATCH_RPFILTER = module;

        # IPv6 is enabled by default and without some of these `firewall.service` will explode.
        IP6_NF_MATCH_AH = module;
        IP6_NF_MATCH_EUI64 = module;
        IP6_NF_MATCH_FRAG = module;
        IP6_NF_MATCH_OPTS = module;
        IP6_NF_MATCH_HL = module;
        IP6_NF_MATCH_IPV6HEADER = module;
        IP6_NF_MATCH_MH = module;
        IP6_NF_MATCH_RPFILTER = module;
        IP6_NF_MATCH_RT = module;
        IP6_NF_MATCH_SRH = module;

        # Needed since mdadm stuff is currently unconditionally included in the initrd
        # This will hopefully get changed, see: https://github.com/NixOS/nixpkgs/pull/183314
        MD_LINEAR = module;
        MD_RAID0 = module;
        MD_RAID1 = module;
        MD_RAID10 = module;
        MD_RAID456 = module;

        # Needed for booting from USB
        USB_UAS = module;

        FW_LOADER_COMPRESS_XZ = yes;
        FW_LOADER_COMPRESS_ZSTD = yes;

        # Restore default LSM from security/Kconfig. Undoes Nvidia downstream changes.
        LSM = freeform "landlock,lockdown,yama,loadpin,safesetid,integrity,selinux,smack,tomoyo,apparmor,bpf";

        # drivers/media/platform/tegra/camera/vi/channel.c from
        # linux-oot-modules has ifdefs for
        # CONFIG_VIDEOBUF2_DMA_CONTIG, but actually requires it to
        # function.
        # Otherwise it hits a WARN_ON() and outputs
        # > tegra-capture-vi: failed to initialize VB2 queue
        VIDEOBUF2_DMA_CONTIG = yes;
      }
      // structuredExtraConfig;
  }
  // argsOverride
)
