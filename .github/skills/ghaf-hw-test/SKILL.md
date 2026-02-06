<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: Apache-2.0
-->
---
name: ghaf-hw-test
description: Run hardware tests on Ghaf devices (darter-pro, jetson-agx) with automatic fix proposals. Use this skill to flash devices, run Robot Framework tests, analyze failures, and generate code fixes.
license: Apache-2.0 (SPDX-FileCopyrightText 2022-2026 TII (SSRC) and the Ghaf contributors)
---

# Ghaf Hardware Test Automation Skill

This skill automates the hardware testing workflow for Ghaf Framework devices using the ci-test-automation Robot Framework test suite. It supports running tests on locally connected devices, flashing images, analyzing test failures, and proposing code fixes.

## When to Use This Skill

Use this skill when the user wants to:
- Run hardware tests on a connected Ghaf device (darter-pro, jetson-agx, lenovo-x1, etc.)
- Flash a new Ghaf image to a device
- Analyze test failures and identify root causes
- Generate fix proposals for failing tests
- Run a test-fix loop until all tests pass

## Supported Devices

| Device | Architecture | Ghaf Target | Test Device Name |
|--------|-------------|-------------|------------------|
| System76 Darter Pro | x86_64 | system76-darp11-b-debug | darter-pro |
| NVIDIA Jetson AGX Orin | aarch64 | nvidia-jetson-orin-agx-debug | Orin-AGX |
| NVIDIA Jetson Orin NX | aarch64 | nvidia-jetson-orin-nx-debug | Orin-NX |
| Lenovo ThinkPad X1 | x86_64 | lenovo-x1-carbon-gen11-debug | Lenovo-X1 |
| Dell Latitude 7330 | x86_64 | dell-latitude-7330-debug | dell-7330 |
| Intel NUC | x86_64 | generic-x86_64-debug | NUC |

## Available Commands

Run these commands from the Ghaf repository root:

```bash
# Check device connectivity and readiness
.github/skills/ghaf-hw-test/ghaf-hw-test status --device darter-pro --ip 192.168.1.100

# Run tests on a device
.github/skills/ghaf-hw-test/ghaf-hw-test test --device darter-pro --ip 192.168.1.100
.github/skills/ghaf-hw-test/ghaf-hw-test test --device Orin-AGX --ip 192.168.1.101 --tag boot
.github/skills/ghaf-hw-test/ghaf-hw-test test --device darter-pro --ip 192.168.1.100 --tag pre-merge

# Flash a device with a new image
.github/skills/ghaf-hw-test/ghaf-hw-test flash --device darter-pro --drive /dev/sda
.github/skills/ghaf-hw-test/ghaf-hw-test flash --device Orin-AGX --recovery

# Analyze test results and propose fixes
.github/skills/ghaf-hw-test/ghaf-hw-test analyze
.github/skills/ghaf-hw-test/ghaf-hw-test analyze --results /tmp/test_results
.github/skills/ghaf-hw-test/ghaf-hw-test analyze --propose-fixes

# Full workflow: test → analyze → fix → repeat
.github/skills/ghaf-hw-test/ghaf-hw-test run --device darter-pro --ip 192.168.1.100 --fix-loop
```

## Typical Workflow

### 1. Check Device Connectivity

Before running tests, verify the device is reachable:

```bash
.github/skills/ghaf-hw-test/ghaf-hw-test status --device darter-pro --ip 192.168.1.100
```

This checks SSH connectivity and reports device readiness.

### 2. Run Tests

Run the pre-merge test suite (default):

```bash
.github/skills/ghaf-hw-test/ghaf-hw-test test --device darter-pro --ip 192.168.1.100
```

Or run specific test tags:

```bash
# Boot tests only
.github/skills/ghaf-hw-test/ghaf-hw-test test --device darter-pro --ip 192.168.1.100 --tag boot

# Performance tests
.github/skills/ghaf-hw-test/ghaf-hw-test test --device darter-pro --ip 192.168.1.100 --tag performance
```

### 3. Analyze Failures

If tests fail, analyze the results:

```bash
.github/skills/ghaf-hw-test/ghaf-hw-test analyze --propose-fixes
```

This parses `/tmp/test_results/output.xml` and:
- Identifies failing tests
- Maps failures to Ghaf module paths
- Generates actionable fix proposals

### 4. Apply Fixes and Re-run

Review the proposed fixes, apply them, then re-run tests:

```bash
# Edit the files suggested in the fix proposals
# Then re-run tests
.github/skills/ghaf-hw-test/ghaf-hw-test test --device darter-pro --ip 192.168.1.100
```

### 5. Fix Loop Mode (Automated)

For automated test-fix iterations:

```bash
.github/skills/ghaf-hw-test/ghaf-hw-test run --device darter-pro --ip 192.168.1.100 --fix-loop
```

This will:
1. Run tests
2. If failures occur, analyze and output fix proposals
3. Wait for fixes to be applied
4. Re-run tests
5. Repeat until all tests pass or max iterations reached

## Flashing Devices

### x86 Devices (darter-pro, lenovo-x1, dell-7330, nuc)

```bash
# Build the image first
nix build .#system76-darp11-b-debug

# Flash to USB/internal drive
.github/skills/ghaf-hw-test/ghaf-hw-test flash --device darter-pro --drive /dev/sda
```

### Jetson Devices (Orin-AGX, Orin-NX)

```bash
# Build the flash script
nix build .#nvidia-jetson-orin-agx-debug-flash-script

# Put device in recovery mode (hold recovery button while powering on)
# Then run guided flash
.github/skills/ghaf-hw-test/ghaf-hw-test flash --device Orin-AGX --recovery
```

## Test Tags Reference

| Tag | Description |
|-----|-------------|
| `pre-merge` | Quick validation tests (default) |
| `bat` | Basic Acceptance Tests |
| `boot` | Boot and connectivity tests |
| `functional` | VM, host, networking, apps |
| `gui` | Desktop/GUI functionality |
| `performance` | Benchmarks, boot time |
| `security` | Security validation |
| `suspension` | Suspend/resume cycles |
| `update` | OTA update verification |

## Configuration

Device profiles and defaults are stored in `.github/skills/ghaf-hw-test/config.yaml`.

You can override defaults via command-line arguments or by editing the config file.

## Output Files

Test results are stored in `/tmp/test_results/`:
- `output.xml` - Robot Framework results (parsed by `analyze`)
- `log.html` - Detailed test log
- `report.html` - Test summary report

## Integration with smoke-test Devshell

This skill wraps the existing `robot-test` command from the smoke-test devshell. You can also use the devshell directly:

```bash
nix develop .#smoke-test
robot-test -i 192.168.1.100 -d darter-pro -p ghaf
```

## Tips for AI Agents

When operating in fix-loop mode:

1. **Read the fix proposals** generated by `analyze --propose-fixes`
2. **Locate the relevant Ghaf modules** using the paths in the proposals
3. **Make minimal, targeted fixes** - change only what's needed
4. **Re-run the specific failing tests** first before running the full suite
5. **Check the test code** in ci-test-automation if the failure is unclear

### Common Failure Patterns

| Failure Type | Likely Cause | Where to Look |
|-------------|--------------|---------------|
| SSH connection timeout | Network/firewall | modules/common/networking/ |
| Service not running | systemd unit issue | modules/common/services/ |
| GUI test failure | Desktop/graphics | modules/desktop/ |
| VM communication failure | GIVC configuration | modules/givc/ |
| Performance regression | Config or hardware | modules/hardware/ |

## Prerequisites

- Ghaf repository cloned
- Device connected via network (SSH) or serial
- For flashing: physical access to device
- Nix with flakes enabled
