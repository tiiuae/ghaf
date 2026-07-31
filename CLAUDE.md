<!--
SPDX-FileCopyrightText: 2022-2026 TII (SSRC) and the Ghaf contributors
SPDX-License-Identifier: Apache-2.0
-->

# Ghaf

@AGENTS.md

The skills in `.claude/skills/` load on demand when a task matches their description:
`ghaf-target`, `ghaf-connect`, `ghaf-logs`, `ghaf-build`, `ghaf-deploy`, `ghaf-test`,
`ghaf-dev-loop`. The `ghaf-log-triage` agent in `.claude/agents/` reads a log snapshot in
its own context and returns ranked findings, which is the right way to handle journals from
a full fleet of VMs.
