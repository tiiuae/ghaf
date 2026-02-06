# SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
# SPDX-License-Identifier: Apache-2.0

# Ghaf Hardware Test Automation Skill

A CLI skill for running Robot Framework hardware tests on Ghaf devices with automatic fix proposals.

## Quick Start

```bash
# Check device connectivity
.github/skills/ghaf-hw-test/ghaf-hw-test status --device darter-pro --ip <IP>

# Run tests
.github/skills/ghaf-hw-test/ghaf-hw-test test --device darter-pro --ip <IP>

# Analyze failures
.github/skills/ghaf-hw-test/ghaf-hw-test analyze --propose-fixes

# Full test-fix loop with auto build+flash
.github/skills/ghaf-hw-test/ghaf-hw-test run --device darter-pro --ip <IP> --fix-loop --drive /dev/sda

# Non-interactive mode (for AI agents)
.github/skills/ghaf-hw-test/ghaf-hw-test -y run --device darter-pro --ip <IP> --fix-loop --drive /dev/sda
```

## Supported Devices

- `darter-pro` - System76 Darter Pro (x86_64)
- `Orin-AGX` - NVIDIA Jetson AGX Orin (aarch64)
- `Orin-NX` - NVIDIA Jetson Orin NX (aarch64)
- `Lenovo-X1` - Lenovo ThinkPad X1 (x86_64)
- `dell-7330` - Dell Latitude 7330 (x86_64)
- `NUC` - Intel NUC (x86_64)

## Commands

| Command | Description |
|---------|-------------|
| `status` | Check device connectivity |
| `test` | Run Robot Framework tests |
| `flash` | Flash Ghaf image to device |
| `analyze` | Parse results, propose fixes |
| `run` | Full test-fix loop |

## Copilot CLI Integration

This skill is designed to be used with GitHub Copilot CLI. It appears in `/skills list` and can be invoked to guide automated testing workflows.

See [SKILL.md](SKILL.md) for full documentation.

## Files

```
.github/skills/ghaf-hw-test/
├── SKILL.md           # Skill definition (AI instructions)
├── README.md          # This file
├── config.yaml        # Device profiles
├── ghaf-hw-test       # CLI executable
├── shell.nix          # Nix environment
└── lib/
    └── result_parser.py  # Output parser & analyzer
```
