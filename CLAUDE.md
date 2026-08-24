# CLAUDE.md — standing instructions

## ⛔ FIRST TODO ON EVERY TASK — RECONCILE BEFORE YOU BUILD (non-negotiable)
Before starting ANY task — before writing code, before spawning a single agent — the FIRST step is a RECONCILIATION: check what already exists so we NEVER duplicate work. Working things are often on a branch/worktree/cloud, NOT on main. Concretely, for the task at hand:
1. Search the **doc index** (`~/anthropic_data_dump/`) + **`~/cyan-docs/`** for an existing spec/status/plan.
2. Check the **deployed state** (`~/cyan-iac-cloud/` + `~/.ssh/config` hosts) — much is ALREADY LIVE on AWS.
3. Enumerate **non-merged branches + worktrees across ALL repos** (`git branch`/`git worktree list` per repo) — the thing may already be built, unmerged.
4. THEN reconcile against source. Only after this: decide what is genuinely NEEDED vs already-DONE vs REDUNDANT, and build ONLY the gap, with depth.
Skipping this is what caused rebuilding an already-deployed super-peer and duplicating DCC/plugin work (2026-08-21). The reconciliation is cheap; the redundant build is not. See `~/cyan-docs/WORK_RECONCILIATION_2026-08-21.md` + `MASTER_STATE_2026-08-21.md` for the current map.

## FACT-CHECK ORDER (mandatory — before asserting ANY fact about Cyan's state, architecture, deployment, or cloud)
Check IN THIS ORDER, do NOT skip to source-in-isolation:
1. **`~/anthropic_data_dump/`** — the AUTHORITATIVE doc corpus (its filenames ARE the index). Cloud/deploy/architecture truth lives here: `CLOUD_BRINGUP_CONTRACT.md`, `ARCHITECTURE_PRIMER.md`, `ARCH_AGENT_MAP.md`, `AUTOPILOT_SPEC*`, the `STATUS_*` / `SPEC_*` docs, `cloud_status.sh`.
2. **`~/cyan-docs/`** — the working design/handoff repo (MASTER_STATUS, HANDOFF_*, design docs).
3. **`~/cyan-iac-cloud/`** — the LIVE AWS infrastructure (Terraform dev/qa/prod, `STATUS_SP_IAC.md`, `STATUS_IAC_LENS_DEPLOY.md`, `STATUS_IAC_LIVETEST.md`, `cyan_infrastructure_playbook.md`, `RUNBOOK.md`). AWS account 852605610984, us-west-2. SSH hosts in `~/.ssh/config` (cyan-dev-bootstrap/relay/lens, bastion, cyan-gpu).
4. **THEN reconcile against source code** — and ONLY the facts still uncertain after 1-3.

**Why:** the cloud (lens + vLLM + the real `cyan_node` super-peer/EmbeddedReplica + relay + bootstrap + rendezvous config) is ALREADY DEPLOYED AND RUNNING on AWS. Reading a repo's `main` in isolation gives WRONG conclusions (e.g. "the super-peer needs deploying" or "it has an unstable-NodeID gap" — both false; the deployment solves discovery via a self-published signed rendezvous.json on S3/CloudFront). Do NOT re-derive deployed state from source; read the docs above first. This avoids token waste and wrong conclusions.

## Memory + auto-memory
Also see `~/.claude/projects/-Users-anirudhvyas-cyan-flutter/memory/MEMORY.md` (the auto-loaded index) and its linked files.
