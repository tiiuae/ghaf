# Copyright 2024-2025 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  config,
  lib,
  pkgs,
  ...
}: let
  cfg = config.ghaf.security;
in {
  options.ghaf.security = {
    users = {
      strong-password = {
        enable = lib.mkOption {
          description = ''
            Enforce Strong password for each user.
          '';
          type = lib.types.bool;
          default = false;
        };

        min-passwd-len = lib.mkOption {
          description = ''
            Minimum password length.
          '';
          type = lib.types.int;
          default = 8;
        };
      };

      encrypt_home.enable = lib.mkOption {
        description = ''
          Enable encryption of user's data stored in 'Home' directory.
        '';
        type = lib.types.bool;
        default = false;
      };

      root.enable = lib.mkOption {
        description = ''
          Disable root login.
        '';
        type = lib.types.bool;
        default = true;
      };

      sudo = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = true;
          description = ''
            Whether to enable the {command}`sudo` command, which
            allows non-root users to execute commands as root.
          '';
        };

        extraConfig = lib.mkOption {
          type = lib.types.lines;
          default = "";
          description = ''
            Extra configuration text appended to {file}`sudoers`.
          '';
        };
      };
    };

    system-security = {
      enable = lib.mkOption {
        description = ''
          Enables basic linux security mechanism.
        '';
        type = lib.types.bool;
        default = false;
      };
      lock-kernel-modules = lib.mkOption {
        description = ''
          Lock dynamic kernel modules.
        '';
        type = lib.types.bool;
        default = true;
      };
      memory-allocator = lib.mkOption {
        description = ''
          Memory allocator.
          Options: "libc", "graphene-hardened", "jemalloc", "mimalloc", "scudo"
        '';
        type = lib.types.enum ["libc" "graphene-hardened" "jemalloc" "mimalloc" "scudo"];
        default = "libc";
      };
      misc = {
        enable-all = lib.mkOption {
          description = ''
            Enable additional security features, which may affect performance. Specific options can be
            activated individually to achieve a balance between performance and security.
          '';
          type = lib.types.bool;
          default = false;
        };
        disableHyperthreading = lib.mkOption {
          description = ''
            Disable hyperthreading. Disabling hyperthreading means that only physical
            CPU cores will be usable at runtime, potentially at significant performance cost.
          '';
          type = lib.types.bool;
          default = false;
        };
        vm-flushL1DCache = lib.mkOption {
          description = ''
            Flush L1 data cache every time the hypervisor enters the guest. It provides security
            May incur significant performance cost.
          '';
          type = lib.types.bool;
          default = false;
        };
        isolatePageTables = lib.mkOption {
          description = ''
            Isolate kernel and userspace page tables. This separation
            helps prevent user-space applications from accessing
            kernel space memory, which is crucial for maintaining
            system stability and security.
            Performance impact on system call, context switch.
          '';
          type = lib.types.bool;
          default = false;
        };
        enableASLR = lib.mkOption {
          description = ''
            Randomize user virtual address space. It disrupts the
            predictability of memory layouts and makes it harder for
            attackers to exploit memory related vulnerabilities.
            May slightly impact performance, may increase boot time.
          '';
          type = lib.types.bool;
          default = false;
        };
        randomizePageFreeList = lib.mkOption {
          description = ''
            Randomize free memory pages managed by the page allocator.
            This randomization lowers risk against certain lib.types of attacks
            that exploit predictable memory allocation patterns.
            May slightly impact performance, may increase boot time.
          '';
          type = lib.types.bool;
          default = false;
        };
        randomizeKStackOffset = lib.mkOption {
          description = ''
            Randomizes the offset of the kernel stack to enhance security
            against certain lib.types of attacks, such as stack-based buffer
            overflows or exploits that rely on knowing the exact layout of
            the kernel stack.
            May slightly impact performance.
          '';
          type = lib.types.bool;
          default = false;
        };
      };
    };
  };
  config = lib.mkMerge [
    ## User account security
    {
      # root account
      nix = {
        settings.allowed-users = ["root"];
      };

      # There is no possible string to hash to just “!”
      users.users.root = lib.mkIf (!cfg.users.root.enable) {
        hashedPassword = lib.mkForce "!";
      };

      # Enforce strong password
      security.pam = {
        services = let
          minlen = config.ghaf.security.users.strong-password.min-passwd-len;
        in {
          passwd = lib.mkIf cfg.users.strong-password.enable {
            text = ''
              auth       required   pam_unix.so shadow nullok
              auth       required   pam_faillock.so authfail audit deny=3 unlock_time=900
              account    required   pam_unix.so
              account    sufficient pam_localuser.so
              password   requisite  ${pkgs.libpwquality.lib}/lib/security/pam_pwquality.so retry=3 minlen=${toString minlen} dcredit=-1 ucredit=-1 ocredit=-1 lcredit=-1 enforce_for_root=true
              password   required   pam_unix.so use_authtok shadow
              session    required   pam_unix.so
            '';
          };
        };

        # Encrypt user's data stored in 'Home' directory
        enableFscrypt = cfg.users.encrypt_home.enable;
      };

      ## sudo administartion
      security.sudo = {
        inherit (cfg.users.sudo) enable;
        inherit (cfg.users.sudo) extraConfig;
      };
    }

    ## Linux security
    (lib.mkIf cfg.system-security.enable {
      services.openssh = {
        extraConfig = lib.optionalString config.ghaf.profiles.release.enable ''
          AllowTcpForwarding yes
          X11Forwarding no
          AllowAgentForwarding no
          AllowStreamLocalForwarding no
          AuthenticationMethods publickey
        '';
      };

      # Disable loading and execution of new kernel
      security.protectKernelImage = lib.mkDefault config.ghaf.profiles.release.enable;

      # Disable user namespace cloning for unprivileged users
      security.unprivilegedUsernsClone = lib.mkDefault false;

      # Disable Hyperthreading (To reduce risk of side channel attack)
      security.allowSimultaneousMultithreading = lib.mkDefault (!(cfg.system-security.misc.disableHyperthreading || cfg.system-security.misc.enable-all));

      # Flush L1 Data cache before entering guest vm
      security.virtualisation.flushL1DataCache = lib.mkIf (cfg.system-security.misc.vm-flushL1DCache || cfg.system-security.misc.enable-all) (lib.mkDefault "always");

      # Enforce page table isolation
      security.forcePageTableIsolation = lib.mkDefault (cfg.system-security.misc.isolatePageTables || cfg.system-security.misc.enable-all);

      # Disable dynamic kernel modules
      security.lockKernelModules = lib.mkDefault cfg.system-security.lock-kernel-modules;

      environment.memoryAllocator.provider = cfg.system-security.memory-allocator;
      environment.variables = lib.mkIf (cfg.system-security.memory-allocator == "scudo") {
        SCUDO_OPTIONS = lib.mkDefault "ZeroContents=1";
      };

      boot.tmp.useTmpfs = lib.mkForce true;

      boot.kernel.sysctl = {
        # Disable loading of new kernel
        "kernel.kexec_load_disabled" = lib.mkForce config.ghaf.profiles.release.enable;

        # Disable ptrace
        "kernel.yama.ptrace_scope" = lib.mkForce 3;

        # Completely hide kernel pointers
        "kernel.kptr_restrict" = lib.mkForce 2;

        # Disable ftrace
        "kernel.ftrace_enabled" = lib.mkDefault false;

        # Randomize address space including heap
        "kernel.randomize_va_space" = lib.mkIf (cfg.system-security.misc.enableASLR || cfg.system-security.misc.enable-all) (lib.mkForce 2);

        # Restrict core dump
        "fs.suid_dumpable" = lib.mkForce 0;

        # Restrict kernel log
        "kernel.dmesg_restrict" = lib.mkIf config.ghaf.profiles.release.enable (lib.mkForce 1);

        # Disable user space page fault handling
        "vm.unprivileged_userfaultfd" = lib.mkForce 0;

        # Disable SysRq key
        "kernel.sysrq" = lib.mkForce 0;

        # Disable loading of line descipline kernel module of TTY device
        # The line descipline module provides an interface between the low-level driver handling a TTY device
        # and user terminal application
        "dev.tty.ldisc_autoload" = lib.mkForce 0;

        # This will avoid unintentional writes to an attacker-controlled FIFO/Regular file.
        # Extend the restriction to group sticky directories
        "fs.protected_fifos" = lib.mkForce 0;
        "fs.protected_regular" = lib.mkForce 2;

        # Allow only root to access perf events
        "kernel.perf_event_paranoid" = lib.mkForce 3;
      };

      boot.blacklistedKernelModules = [
        # Obscure network protocols
        "ax25"
        "netrom"
        "rose"

        # Old or rare or insufficiently audited filesystems
        "adfs"
        "affs"
        "bfs"
        "befs"
        "cramfs"
        "efs"
        "erofs"
        "exofs"
        "freevxfs"
        "f2fs"
        "hfs"
        "hpfs"
        "jfs"
        "minix"
        "nilfs2"
        "ntfs"
        "omfs"
        "qnx4"
        "qnx6"
        "sysv"
        "ufs"
      ];
      boot.kernelParams =
        [
          # Fill freed pages and heap objects with zeroes
          "init_memory=0"

          # Panic on any uncorrectable errors through the machine check exception system
          "mce=0"
        ]
        ++ lib.optionals (cfg.system-security.misc.randomizePageFreeList || cfg.system-security.misc.enable-all) [
          # Page allocation randomization
          "page_alloc.shuffle=1"
        ]
        ++ lib.optionals (cfg.system-security.misc.randomizeKStackOffset || cfg.system-security.misc.enable-all) [
          # Kernel stack offset randomization
          "randomize_kstack_offset=on"
        ]
        ++ lib.optionals config.ghaf.profiles.debug.enable [
          # To identify and fix potential vulnerability.
          "slub_debug=FZPU"
        ]
        ++ lib.optionals config.ghaf.security.network.ipsecurity.enable [
          # Disable IPv6 to reduce attack surface.
          "ipv6.disable=1"
        ];
    })
  ];
}
