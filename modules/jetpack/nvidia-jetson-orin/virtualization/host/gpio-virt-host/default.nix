# Copyright 2022-2023 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0
{
  lib,
  pkgs,
  config,
  ...
}: let
  cfg = config.ghaf.hardware.nvidia.virtualization.host.gpio;
in {
  options.ghaf.hardware.nvidia.virtualization.host.gpio.enable = lib.mkOption {
    type = lib.types.bool;
    default = false;
    description = ''
      Enable virtualization host support for NVIDIA Orin

      This option is an implementation level detail and is toggled automatically
      by modules that need it. Manually enabling this option is not recommended in
      release builds.
    '';
  };

  config = lib.mkIf cfg.enable {
    ghaf.hardware.nvidia.virtualization.enable = true;

    # in practice this configures both host and guest kernel becaue we use only one kernel in the whole system
    boot.kernelPatches = builtins.trace "guest kernel .config for GPIO" [
      {
        name = "GPIO virtualization host kernel configuration";
        patch = null;
        extraStructuredConfig = {
          VFIO_PLATFORM = lib.kernel.yes;
          TEGRA_GPIO_HOST_PROXY = lib.kernel.yes;
          TEGRA_GPIO_GUEST_PROXY = lib.kernel.yes;
          
          # EFI = lib.kernel.yes;
          # EFI_STUB = lib.kernel.yes;
          # debug options below this line
          LOG_BUF_SHIFT = lib.kernel.freeform ''20'';

          HW_BREAKPOINT = lib.kernel.yes;
          HAVE_HW_BREAKPOINT = lib.kernel.yes;
          GDB_HW_BREAKPOINT = lib.kernel.yes;
          DEBUG_KERNEL = lib.kernel.yes;
          DEBUG_INFO = lib.kernel.yes;
          DEBUG_INFO_SPLIT = lib.kernel.no;
          DEBUG_INFO_DWARF4 = lib.kernel.no;
          DEBUG_INFO_BTF = lib.kernel.yes;
          DEBUG_FS = lib.kernel.yes;
          DEBUG_PAGEALLOC = lib.kernel.yes;
          DEBUG_VIRTUAL = lib.kernel.yes;
          DEBUG_RODATA = lib.kernel.yes;
          DEBUG_MISC = lib.mkDefault lib.kernel.yes;
          DEBUG_VM = lib.mkDefault lib.kernel.yes;
          DEBUG_VM_PGTABLE = lib.mkDefault lib.kernel.yes;
          DEBUG_SHIRQ = lib.mkDefault lib.kernel.yes;

          DEBUG_DRIVER = lib.mkDefault lib.kernel.yes;
          DEBUG_DEVRES = lib.mkDefault lib.kernel.yes;
          DEBUG_PINCTRL = lib.mkDefault lib.kernel.yes;
          DEBUG_GPIO = lib.mkDefault lib.kernel.yes;

          # DEBUG_TIMEKEEPING = lib.mkDefault lib.kernel.yes;
          # DEBUG_LOCKDEP = lib.mkDefault lib.kernel.yes;
          # LOCK_DEBUGGING_SUPPORT = lib.mkDefault lib.kernel.yes;
          # PROVE_LOCKING = lib.mkDefault lib.kernel.yes;
          # LOCK_STAT = lib.mkDefault lib.kernel.yes;
          # DEBUG_RT_MUTEXES = lib.mkDefault lib.kernel.yes;
          # DEBUG_SPINLOCK = lib.mkDefault lib.kernel.yes;
          # DEBUG_MUTEXES = lib.mkDefault lib.kernel.yes;
          # DEBUG_WW_MUTEX_SLOWPATH = lib.mkDefault lib.kernel.yes;
          # DEBUG_RWSEMS = lib.mkDefault lib.kernel.yes;
          # DEBUG_LOCK_ALLOC = lib.mkDefault lib.kernel.yes;
          # DEBUG_ATOMIC_SLEEP = lib.mkDefault lib.kernel.yes;
          # DEBUG_LOCKING_API_SELFTESTS = lib.mkDefault lib.kernel.yes;
          # PREEMPTIRQ_DELAY_TEST = lib.mkDefault lib.kernel.yes;
          # BOOTTIME_TRACING = lib.mkDefault lib.kernel.yes;
          # DYNAMIC_FTRACE = lib.mkDefault lib.kernel.yes;
          # IRQSOFF_TRACER = lib.mkDefault lib.kernel.yes;
          # HWLAT_TRACER = lib.mkDefault lib.kernel.yes;
          # TRACER_SNAPSHOT_PER_CPU_SWAP = lib.mkDefault lib.kernel.yes;
          # PROFILE_ANNOTATED_BRANCHES = lib.mkDefault lib.kernel.yes;
          # BLK_DEV_IO_TRACE = lib.mkDefault lib.kernel.yes;
          SBPF_KPROBE_OVERRIDE = lib.mkDefault lib.kernel.yes;
          SYNTH_EVENTS = lib.mkDefault lib.kernel.yes;
          HIST_TRIGGERS = lib.mkDefault lib.kernel.yes;
          # TRACE_EVENT_INJECT = lib.mkDefault lib.kernel.yes;
          # TRACEPOINT_BENCHMARK = lib.mkDefault lib.kernel.yes;
          # RING_BUFFER_BENCHMARK = lib.mkDefault lib.kernel.yes;
          # TRACE_EVAL_MAP_FILE = lib.mkDefault lib.kernel.yes;
          # FTRACE_STARTUP_TEST = lib.mkDefault lib.kernel.yes;
          # RING_BUFFER_STARTUP_TEST = lib.mkDefault lib.kernel.yes;
          KPROBE_EVENT_GEN_TEST = lib.mkDefault lib.kernel.yes;
          # SAMPLES = lib.mkDefault lib.kernel.yes;
          DEBUG_PERF_USE_VMALLOC = lib.kernel.yes;
          # ARM64_PSEUDO_NMI = lib.kernel.yes;
          READABLE_ASM = lib.kernel.yes;
          DEBUG_MEMORY_INIT = lib.kernel.yes;
          DEBUG_KOBJECT = lib.kernel.no;
          STRICT_KERNEL_RWX = lib.mkForce lib.kernel.yes;
          STRICT_MODULE_RWX = lib.mkForce lib.kernel.yes;
          DRM_GEM_SHMEM_HELPER = lib.kernel.yes;
          DRM_VIRTIO_GPU = lib.kernel.yes;
          BOOT_CONFIG = lib.kernel.yes;
          MAGIC_SYSRQ = lib.kernel.yes;
          KGDB = lib.kernel.yes;
          KGDB_KDB = lib.kernel.yes;
          KGDB_SERIAL_CONSOLE = lib.kernel.yes;
          KGDB_HONOUR_BLOCKLIST = lib.kernel.yes;
          FORTIFY_SOURCE = lib.kernel.yes;
          ARCH_HAS_FORTIFY_SOURCE = lib.kernel.yes;
          KPROBES = lib.kernel.yes;
          HAVE_KPROBES = lib.kernel.yes;
          PREEMPT_NONE = lib.kernel.yes;
          FRAME_POINTER = lib.kernel.yes;
          GDB_SCRIPTS = lib.kernel.yes;
          STATIC_KEYS_SELFTEST = lib.kernel.yes;
          RELOCATABLE = lib.mkForce lib.kernel.yes;
          RANDOMIZE_BASE = lib.mkForce lib.kernel.no;
          RANDOMIZE_MODULE_REGION_FULL = lib.mkForce lib.kernel.no;
          UNINLINE_SPIN_UNLOCK = lib.kernel.no;
          GENERIC_IRQ_TRACE = lib.kernel.yes;
          GENERIC_IRQ_DEBUG = lib.kernel.yes;
          GENERIC_IRQ_INJECTION = lib.kernel.yes;
          GENERIC_IRQ_DEBUGFS = lib.kernel.yes;
          KERNEL_OFFSET = lib.kernel.yes;
          GENERIC_TRACER = lib.kernel.yes;
          PREEMPTIRQ_TRACEPOINTS = lib.kernel.yes;
          SCHED_TRACER = lib.kernel.yes;
          CONTEXT_SWITCH_TRACER = lib.kernel.yes;
          RCU_TRACE = lib.kernel.yes;
          STACKTRACE = lib.kernel.yes;

          #
          # Debug Oops, Lockups and Hangs
          #
          PANIC_ON_OOPS = lib.mkDefault lib.kernel.no;
          PANIC_ON_OOPS_VALUE = lib.kernel.freeform ''60'';
          PANIC_TIMEOUT = lib.kernel.freeform ''60'';
          LOCKUP_DETECTOR = lib.mkDefault lib.kernel.no;
          LOCKUP_DETECTOR_PANIC = lib.mkDefault lib.kernel.no;
          SOFTLOCKUP_DETECTOR = lib.mkDefault lib.kernel.no;
          SOFTLOCKUP_DETECTOR_PANIC = lib.mkDefault lib.kernel.no;
          SOFTLOCKUP_DETECTOR_IGNORE_BOOT = lib.mkDefault lib.kernel.yes;
          BOOTPARAM_SOFTLOCKUP_PANIC = lib.mkDefault lib.kernel.no;
          BOOTPARAM_SOFTLOCKUP_PANIC_VALUE = lib.kernel.freeform ''60'';
          WQ_WATCHDOG = lib.kernel.no;

          COMPAT_BRK = lib.kernel.yes;
          VIRTIO_VSOCKETS = lib.kernel.yes;
          VIRTIO_INPUT = lib.kernel.yes;
          VIRTIO_DMA_SHARED_BUFFER = lib.kernel.yes;
          FUSE_FS = lib.kernel.yes;
          CUSE = lib.kernel.yes;
          VIRTIO_FS = lib.kernel.yes;
          OVERLAY_FS = lib.kernel.yes;
          EFI_VARS_PSTORE = lib.kernel.yes;
          PNP_DEBUG_MESSAGES = lib.kernel.yes;
          # PATA_TIMINGS = lib.kernel.yes;
          # ATA_ACPI = lib.kernel.yes;
          HW_RANDOM = lib.kernel.yes;
          HW_RANDOM_HISI_V2 = lib.kernel.yes;
          HW_RANDOM_TPM = lib.kernel.yes;

          # disable Xen
          XEN_DOM0 = lib.mkForce lib.kernel.no;
          XEN = lib.mkForce lib.kernel.no;
          XEN_BLKDEV_FRONTEND = lib.mkForce lib.kernel.no;
          XEN_NETDEV_FRONTEND = lib.mkForce lib.kernel.no;
          INPUT_XEN_KBDDEV_FRONTEND = lib.mkForce lib.kernel.no;
          HVC_XEN = lib.mkForce lib.kernel.no;
          HVC_XEN_FRONTEND = lib.mkForce lib.kernel.no;
          XEN_FBDEV_FRONTEND = lib.mkForce lib.kernel.no;
          XEN_BALLOON = lib.mkForce lib.kernel.no;
          XEN_BALLOON_MEMORY_HOTPLUG = lib.mkForce lib.kernel.no;
          XEN_SCRUB_PAGES_DEFAULT = lib.mkForce lib.kernel.no;
          XEN_DEV_EVTCHN = lib.mkForce lib.kernel.no;
          XEN_BACKEND = lib.mkForce lib.kernel.no;
          XEN_SYS_HYPERVISOR = lib.mkForce lib.kernel.no;
          XEN_XENBUS_FRONTEND = lib.mkForce lib.kernel.no;
          SWIOTLB_XEN = lib.mkForce lib.kernel.no;
          XEN_PRIVCMD = lib.mkForce lib.kernel.no;
          XEN_EFI = lib.mkForce lib.kernel.no;
          XEN_AUTO_XLATE = lib.mkForce lib.kernel.no;
        };
      }
    ];

    hardware.deviceTree = {
      # Enable hardware.deviceTree for handle host dtb overlays
      enable = true;
      name = builtins.trace "Debug dtb name (gpio-virt-host): tegra234-p3701-0000-p3737-0000.dtb" "tegra234-p3701-0000-p3737-0000.dtb";
      # name = builtins.trace "Debug dtb name (gpio-virt-host): tegra234-p3701-host-passthrough.dtb" "tegra234-p3701-host-passthrough.dtb";
      # name = "tegra234-p3701-host-passthrough.dtb";

      # using overlay file:
      overlays = [
        {
          name = "gpio_pt_host_overlay";
          dtsFile = ./gpio_pt_host_overlay.dtso;

          # Apply overlay only to host passthrough device tree
          filter = "tegra234-p3701-0000-p3737-0000.dtb";
          # filter = "tegra234-p3701-host-passthrough.dtb";
          # filter = "tegra234-p3701-host-passthrough.dtb";
        }
      ];
    };
  };
}
