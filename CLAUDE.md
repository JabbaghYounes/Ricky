# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Rick is a **drop-in AI swarm toolkit**. Copy the `rick/` folder into any project to get PRD-driven autonomous development — multiple specialized AI agents go from a Product Requirements Document to implemented features with pull requests.

## Structure

All rick files live inside the `rick/` directory:

- `rick/rick.conf` — Project-specific config (test command, base branch, retries, design agents)
- `rick/agents/` — Agent prompt definitions (one `.md` file per role)
- `rick/pipelines/` — Pipeline stage documentation in YAML
- `rick/prd/prd.md` — PRD input (user edits this)
- `rick/prd/features/` — Auto-generated individual feature files
- `rick/prd/specs/` — Auto-generated design specs (architecture, DB schema, API, UX)
- `rick/scripts/` — Orchestrator shell scripts

## Architecture

```
PRD → Product Manager → Feature Extraction → Design Phase (once) → Per-Feature Swarms → PRs
```

Each feature swarm runs:
```
Architect → Backend + Frontend (parallel) → Tester → Debugger (retry loop) → Commit + PR
```

Scripts resolve paths via `RICK_DIR` (relative to script location) and run git/build commands from the project root (`RICK_DIR/..`). All scripts source `rick.conf` for project-specific settings.

## Scripts

- **`rick/scripts/run-product.sh`** — Full end-to-end pipeline: extract features, design phase, all feature swarms
- **`rick/scripts/swarm.sh "<task>"`** — Single feature swarm (use `--skip-design` to skip design phase)
- **`rick/scripts/prd-extract.sh`** — Extract features from PRD into individual files using `---FEATURE---` delimiter
- **`rick/scripts/prd-swarm.sh`** — Loop all feature files and run `swarm.sh --skip-design` for each

## Agent Roles

**Planning:** product-manager, system-architect, feature-planner, roadmap
**Design:** db-designer, api-designer, ux-designer
**Engineering:** architect (feature-level), backend, frontend, tester, debugger, versioncontroller

All agents reference the project's CLAUDE.md and specs in `rick/prd/specs/`.

## Conventions

- Feature branches: `ai-feature-<timestamp>` from `$BASE_BRANCH`
- PRs created automatically via `gh pr create`
- Design specs written to `rick/prd/specs/` by design agents, read by engineering agents
- Feature extraction uses `---FEATURE---` delimiter for splitting
- Debug retry loop respects `$MAX_RETRIES` from config
- `feature.yaml` documents the pipeline stages; scripts are the source of truth for execution
