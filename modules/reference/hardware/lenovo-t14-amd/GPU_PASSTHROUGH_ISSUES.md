<!--
    SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
    SPDX-License-Identifier: CC-BY-SA-4.0
-->
# AMD iGPU Passthrough Issues

## Hardware

- CPU: AMD Ryzen 7 PRO 8840U (Hawk Point)
- iGPU: AMD Radeon 780M Graphics (Phoenix3, device ID 1002:1900)
- PCI Address: 0000:c4:00.0 (GPU), 0000:c4:00.1 (GPU Audio)

## Problem

AMD Phoenix3/HawkPoint integrated GPU passthrough to QEMU/KVM guest VMs fails with register timeout errors. The amdgpu driver cannot initialize the GPU hardware in the virtualized environment.

## Debugging History

### Without VBIOS

```
amdgpu 0000:06:00.0: amdgpu: Unable to locate a BIOS ROM
amdgpu 0000:06:00.0: amdgpu: Fatal error during GPU init
```

iGPUs don't have ROM chips - VBIOS is stored in ACPI VFCT table.

### With VBIOS, No UEFI

Extracted VBIOS from `/sys/firmware/acpi/tables/VFCT` using standard extraction tool. Added `romfile=${./vbios_1002_1900.bin}` to QEMU config.

Result: VM hung completely with max CPU usage. No kernel messages, network dead.

### With VBIOS + OVMF

Added OVMF UEFI firmware. VM now boots but driver fails:

```
[4.668985] amdgpu 0000:06:00.0: amdgpu: Timeout waiting for VM flush ACK!
[5.604179] ring mes_kiq_3.1.0 test failed (-110)
[5.606775] hw_init of IP block <gfx_v11_0> failed -110
[10.389066] amdgpu 0000:06:00.0: probe with driver amdgpu failed with error -110
```

KIQ (Kernel Interface Queue) ring test fails. GPU registers not responding to writes.

### Multi-Function Device

Moved GPU audio (0000:c4:00.1) from audiovm to guivm to keep multi-function device together. No change in behavior.

### Host Driver Contamination

Host was loading amdgpu driver before VFIO:

```
[7.009428] [drm] Initialized amdgpu 3.64.0 for 0000:c4:00.0
[7.102166] amdgpu 0000:c4:00.0: finishing device
[7.174536] vfio-pci 0000:c4:00.0: vgaarb: deactivate vga
```

Added `module_blacklist=amdgpu,snd_hda_intel` to host kernel parameters.

Result: VFIO now binds cleanly. TianoCore UEFI logo displays on physical screen (GOP driver working). But amdgpu still fails in guest with same timeout errors.

### Bus Mastering

PCI COMMAND register showed `0x0003` (bus mastering disabled). Manually enabled with `setpci -s 06:00.0 COMMAND=0x0007`, reloaded driver - same timeouts. Bus mastering gets disabled when probe fails.

## Root Cause

GPU registers are non-responsive in the VM. The hardware appears to be in a non-functional state. Looking at `drivers/gpu/drm/amd/amdgpu/gmc_v11_0.c:298`, the driver writes to registers to flush TLB and never receives acknowledgment.

AMD iGPUs require platform-specific BIOS/AGESA initialization that doesn't happen in VMs:
- PSP (Platform Security Processor) needs early init
- Power management coupled with CPU P-states/C-states
- Memory controller shared with CPU
- No independent reset capability

UEFI GOP can initialize basic display but not full GPU hardware.

## Working Configuration

SimpleDRM framebuffer takes over GOP-initialized display without GPU driver:

```nix
# Host: prevent driver from touching GPU
host.kernelConfig.kernelParams = [
  "module_blacklist=amdgpu,snd_hda_intel"
];

# Guest: OVMF firmware + SimpleDRM
microvm.qemu.extraArgs = [
  "-drive" "file=${pkgs.OVMF.fd}/FV/OVMF_CODE.fd,if=pflash,unit=0,readonly=true"
  "-drive" "file=${pkgs.OVMF.fd}/FV/OVMF_VARS.fd,if=pflash,unit=1,readonly=true"
];

ghaf.graphics.boot.renderer = lib.mkForce "simpledrm";

# Pass both GPU functions together
gpu.pciDevices = [
  { path = "0000:c4:00.0"; ... }  # GPU
  { path = "0000:c4:00.1"; ... }  # GPU Audio
];
```

Provides functional display via CPU rendering (llvmpipe). No GPU acceleration.

## Extracting VBIOS

Compile extraction tool:

```bash
musl-gcc -static -o extract_vbios extract_vbios.c
```

Run on host:

```bash
./extract_vbios
# Creates vbios_1002_1900.bin
```

Verify:

```bash
hexdump -C vbios_1002_1900.bin | head -1
# Should show: 55 aa ... (ROM signature)
```

Tool available at: https://github.com/isc30/ryzen-gpu-passthrough-proxmox

## References

- Passthrough guide: https://github.com/isc30/ryzen-gpu-passthrough-proxmox
- Kernel timeout location: `drivers/gpu/drm/amd/amdgpu/gmc_v11_0.c:298`
- KIQ ring test: `drivers/gpu/drm/amd/amdgpu/amdgpu_ring.c`
