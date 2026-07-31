# Ghaf — Copilot instructions

Read [`AGENTS.md`](../AGENTS.md) in the repository root first. It is the shared instruction
file for every agent working here: build and commit requirements, repository layout,
conventions, the everyday commands, and the mistakes that are easy to make.

Keep shared guidance in `AGENTS.md`. This file holds only what is specific to Copilot.

## Tool initialization

### Serena (code intelligence)

Activate the project before navigating code:

```
#serena activate project
```

The `#serena` prefix is required to reach the MCP tools. Serena gives semantic search and
symbol-level navigation (`find_symbol`, `get_symbols_overview`), which beats grepping a
tree this size.

### Context7 (documentation)

Use Context7 for current library documentation rather than recalling it. Useful IDs here:

- `/NixOS/nixos`, `/NixOS/nixpkgs`, `/NixOS/nix`
- `/nix-community/home-manager`
- `/Mic92/sops-nix`
- `/numtide/flake-utils`

Resolve library IDs first unless you already know the exact Context7-compatible ID.

## Skills

- `.github/skills/ghaf-hw-test/` — hardware test CLI (flash, run Robot tests, parse
  results, fix loop). Copilot CLI discovers skills in this directory, so it appears in
  `/skills list`.
- `.claude/skills/ghaf-*/SKILL.md` — build, deploy, connect, logs, test and the full
  development loop. These are written for Claude Code, which triggers them automatically.
  Copilot does not, so read the relevant `SKILL.md` as documentation when a task matches;
  the commands and reasoning in them are tool-neutral.
