# Ghaf Framework Development Instructions

**Ghaf Framework** is a Nix-based open-source security framework for enhancing security through compartmentalization on edge devices. It creates secure images for various hardware platforms (x86, ARM, RISC-V) using NixOS.

**CRITICAL: Always reference these instructions first and fallback to search or bash commands only when you encounter unexpected information that does not match the info here.**

## Code Quality Standards

### **ALWAYS Strip Trailing Whitespace**
- **Automatically remove trailing whitespace** from any files you create or modify
- **Use sed command**: `sed -i 's/[[:space:]]*$//' filename` to clean files
- **Verify cleanup**: Ensure no trailing whitespace remains before staging changes
- **Project-wide consistency**: Maintain clean, professional code formatting standards

### **File Formatting Requirements**
- **All commits must be properly formatted** using treefmt before making a PR
- **Run formatting**: `nix fmt` or `nix fmt -- --fail-on-change`
- **License headers**: Always add proper SPDX license headers to new files
- **No trailing whitespace**: Clean, professional code standards

## Working Effectively

### Prerequisites and Setup
- Install Nix package manager: `curl -L https://nixos.org/nix/install | sh`
- Enable flakes in Nix configuration: `echo "experimental-features = nix-command flakes" >> ~/.config/nix/nix.conf`
- **CRITICAL**: For cross-compilation, set up an AArch64 remote builder: https://nixos.org/manual/nix/stable/advanced-topics/distributed-builds.html

### Essential Build Commands
- View all available targets: `nix flake show` -- takes 30-60 seconds
- Build documentation: `nix build .#doc` -- takes 5-10 minutes. NEVER CANCEL. Set timeout to 15+ minutes.
- Build VM for testing: `nix run .#packages.x86_64-linux.vm-debug` -- takes 45-90 minutes. NEVER CANCEL. Set timeout to 120+ minutes.
- Build generic x86 image: `nix build .#generic-x86_64-debug` -- takes 60-120 minutes. NEVER CANCEL. Set timeout to 180+ minutes.
- Build Lenovo X1 image: `nix build .#lenovo-x1-carbon-gen11-debug` -- takes 60-120 minutes. NEVER CANCEL. Set timeout to 180+ minutes.

### Key Hardware Targets and Build Times
- **CRITICAL BUILD TIME WARNING**: All builds take 45+ minutes, some up to 3+ hours. NEVER CANCEL builds.

| Target | Command | Architecture | Build Time | Timeout |
|--------|---------|-------------|------------|---------|
| VM Debug | `nix run .#packages.x86_64-linux.vm-debug` | x86_64 | 45-90 min | 120+ min |
| Generic x86 | `nix build .#generic-x86_64-debug` | x86_64 | 60-120 min | 180+ min |
| Lenovo X1 | `nix build .#lenovo-x1-carbon-gen11-debug` | x86_64 | 60-120 min | 180+ min |
| NVIDIA Jetson AGX | `nix build .#nvidia-jetson-orin-agx-debug` | aarch64 | 90-180 min | 240+ min |
| NVIDIA Jetson NX | `nix build .#nvidia-jetson-orin-nx-debug` | aarch64 | 90-180 min | 240+ min |
| i.MX 8MP-EVK | `nix build .#packages.aarch64-linux.imx8mp-evk-release` | aarch64 | 90-180 min | 240+ min |
| Microchip Icicle | `nix build .#packages.riscv64-linux.microchip-icicle-kit-debug` | riscv64 | 120-240 min | 300+ min |

### Installer Images
- Build Lenovo X1 installer: `nix build .#lenovo-x1-carbon-gen11-debug-installer` -- takes 90-120 minutes. NEVER CANCEL. Set timeout to 180+ minutes.
- **Installer usage**: Boot from installer media, run `sudo ghaf-install.sh`
- **Requirement**: Minimum 4GB storage device for installer

### Flashing and Installation
- Flash script location: `./packages/pkgs-by-name/flash-script/flash.sh`
- Flash to USB/SD: `sudo ./packages/pkgs-by-name/flash-script/flash.sh -d /dev/<DEVICE> -i result/<IMAGE_NAME>`
- **ALWAYS run as root** for flashing operations
- **ALWAYS verify device path** before flashing to avoid data loss

## Validation and Testing

### Hardware Testing Scenarios
- **NVIDIA Jetson**: Connect via USB-C and Micro-USB for serial console, flash in recovery mode
- **i.MX 8MP**: Test SD card boot and USB media functionality
- **Microchip Icicle**: Verify HSS version 0.99.35-v2023.02 in eNVM before testing
- **x86 hardware**: Test USB boot and basic hardware recognition

### VM Testing (Primary Validation Method)
- Run VM: `nix run .#packages.x86_64-linux.vm-debug`
- **NEVER CANCEL**: VM build takes 45-90 minutes
- Creates `ghaf-host.qcow2` overlay in current directory
- Clean shutdown: QEMU Menu → Machine → Power Down
- Clean up: Remove `ghaf-host.qcow2` if errors occur

### Post-Build Validation Steps
1. **ALWAYS verify build completed successfully** before proceeding
2. **Test VM boot and basic functionality** - check desktop loads, applications start
3. **Test hardware functionality** if building for specific device
4. **Run treefmt format check**: `nix fmt -- --fail-on-change`
5. **Run license check**: `nix develop --command reuse lint`

### Documentation Validation
- Build docs: `nix build .#doc` -- takes 5-10 minutes
- **NEVER CANCEL** documentation builds
- Docs use Astro Starlight framework
- Source files in `docs/src/content/docs/`
- Always update documentation when adding new features

## Development Workflow

### Code Formatting and Quality Checks

**CRITICAL: All commits must be properly formatted using treefmt before making a PR**

- **ALWAYS format code before committing**: `nix fmt` or `nix fmt -- --fail-on-change`
- **ALWAYS run license check**: `nix develop --command reuse lint`
- Check flake validity: `nix flake show --all-systems`
- **These checks must pass** or CI will fail

The project uses treefmt for consistent code formatting across multiple languages:
- Nix files: nixfmt-rfc-style (RFC 166 standard)
- Python files: ruff formatter and linter
- Shell scripts: shellcheck linting
- JavaScript/TypeScript: prettier formatting

Use `nix fmt -- --fail-on-change` to check if formatting is needed without making changes.

### File Structure and Conventions
- Nix modules: `modules/` (common, hardware, desktop, etc.)
- Packages: `packages/pkgs-by-name/` (follow Nixpkgs standards)
- Hardware targets: `targets/` (vm, generic-x86_64, nvidia-jetson-orin, etc.)
- Documentation: `docs/src/content/docs/ghaf/`

### Adding New Hardware Support
- Create target in `targets/<new-hardware>/`
- Add modules in `modules/hardware/<new-hardware>/`
- Update `flake.nix` with new target
- Add documentation in `docs/src/content/docs/ghaf/dev/ref/`
- **ALWAYS test build and validation** on actual hardware

## Common Troubleshooting

### Build Issues
- **Out of disk space**: Builds require 20+ GB free space
- **Network timeouts**: Use `--option connect-timeout 60` for Nix commands
- **Permission errors**: Ensure proper permissions for `/nix/store`
- **Flake errors**: Run `nix flake update` if lock file issues

### VM Issues
- **VM won't start**: Remove `ghaf-host.qcow2` and rebuild
- **Black screen**: Wait 5-10 minutes, VM boot can be slow
- **Networking issues**: Check firewall settings in VM

### Hardware Flashing Issues
- **Device not found**: Check device path with `lsblk`
- **Permission denied**: Run flash script as root with `sudo`
- **Invalid format**: Ensure image is `.img`, `.iso`, or `.zst`

## Important Files and Locations

### Key Configuration Files
- Main flake: `flake.nix` (build definitions)
- Shell environment: `shell.nix` (development dependencies)
- Library functions: `lib.nix` (shared utilities)
- Licensing: `REUSE.toml` (license configuration)

### Performance and Audio Testing
- Performance benchmarks: `modules/development/scripts/sysbench_test.nix`
- File I/O testing: `modules/development/scripts/sysbench_fileio_test.nix`
- Icicle kit performance: `modules/development/scripts/perf_test_icicle_kit.nix`
- Audio testing: `modules/development/audio_test/` (includes test files)

### Development Tools
- Debug tools: `modules/development/debug-tools.nix`
- SSH configuration: `modules/development/ssh.nix`
- USB serial: `modules/development/usb-serial.nix`
- Audio testing: `modules/development/audio_test/`

### CI/CD Understanding
- **Build timeout**: 360 minutes (6 hours) in CI
- **Matrix builds**: Multiple architectures build in parallel
- **Remote builders**: Uses dedicated build machines for ARM/RISC-V
- **Security scanning**: Automated vulnerability scanning enabled

### Cross-Compilation Notes
- **Current limitation**: Cross-compilation support is under development
- **AArch64 builds**: Require remote builder setup
- **RISC-V builds**: Require remote builder setup
- **Build times**: Cross-platform builds take 2-4x longer than native

## Security and Compliance

### License Requirements
- **ALWAYS add license headers** to new files:
  ```nix
  # SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
  # SPDX-License-Identifier: Apache-2.0
  ```
- Run `reuse lint` before committing
- Follow Apache-2.0 for code, CC-BY-SA-4.0 for documentation

### Security Practices
- **Never commit secrets** or credentials
- **Always validate inputs** in shell scripts
- **Use secure defaults** in configurations
- **Report vulnerabilities** via GitHub Security Advisories

### Supply Chain Security
- Project aims for SLSA Level 3 compliance
- SBOM generation: Use `sbomnix` tool
- Vulnerability scanning: Automated via `ghafscan`
- Security fixes: Follow coordinated disclosure process

## Final Validation Checklist

Before submitting any changes:
- [ ] Build succeeds with appropriate timeout (60+ minutes for major targets)
- [ ] Code properly formatted with treefmt: `nix fmt -- --fail-on-change` passes
- [ ] `nix develop --command reuse lint` passes
- [ ] VM boots and basic functionality works (if applicable)
- [ ] Documentation updated (if adding features)
- [ ] Security implications considered
- [ ] No secrets or credentials committed

**Remember: Build processes are time-intensive. Plan for 1-3 hours for full validation cycles. NEVER CANCEL long-running builds.**
