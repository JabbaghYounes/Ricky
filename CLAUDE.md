# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

Rick is a **drop-in AI swarm toolkit**. Copy the `rick/` folder into any project to get PRD-driven autonomous development — multiple specialized AI agents go from a Product Requirements Document to implemented features with pull requests.

## Prerequisites

- `claude` CLI (Claude Code)
- `gh` CLI (GitHub CLI) — for automatic PR creation
- `git`

## Commands

```bash
# Full pipeline: PRD → design → feature extraction → per-feature swarms → PRs
rick/scripts/run-product.sh

# Single feature swarm (includes design phase)
rick/scripts/swarm.sh "implement user authentication"

# Single feature swarm, skip design (used internally by prd-swarm.sh)
rick/scripts/swarm.sh --skip-design "implement user authentication"

# Extract features from PRD into individual files
rick/scripts/prd-extract.sh

# Run swarm for each extracted feature file
rick/scripts/prd-swarm.sh
```

## Architecture

```
PRD → Product Manager → Feature Extraction → Design Phase (once) → Per-Feature Swarms → PRs
```

Each feature swarm runs:
```
Architect → Backend + Frontend (parallel) → Tester → Debugger (retry loop) → Commit + PR
```

### Agent invocation

All agents are invoked via `claude --system-prompt "$(cat agents/<role>.md)" --print "<prompt>"`. The `run_agent` function in `swarm.sh` wraps this pattern. Backend and frontend agents run in parallel (backgrounded with `&` + `wait`).

### Path resolution

Scripts resolve `RICK_DIR` relative to their own location (`$(dirname "$0")/..`) and derive `PROJECT_ROOT` as `RICK_DIR/..`. All git/build commands execute from `PROJECT_ROOT`. All scripts source `rick.conf` for project-specific settings.

### Feature extraction format

The product-manager agent outputs features separated by `---FEATURE---` lines. The first line after each delimiter is a **kebab-case slug** (e.g., `user-auth`), used as the filename in `rick/prd/features/<slug>.md`. The `prd-extract.sh` script splits this output via `awk`.

## Structure

All rick files live inside the `rick/` directory:

- `rick/rick.conf` — Project config: `TEST_CMD`, `BASE_BRANCH`, `MAX_RETRIES`, `DESIGN_AGENTS`
- `rick/agents/` — Agent system prompts (one `.md` per role)
- `rick/pipelines/feature.yaml` — Pipeline stage documentation (scripts are source of truth)
- `rick/prd/prd.md` — PRD input (user edits this)
- `rick/prd/features/` — Auto-generated individual feature files (one per extracted feature)
- `rick/prd/specs/` — Auto-generated design specs (architecture, DB schema, API, UX)
- `rick/prd/status.json` — Feature progress tracking

## Agent Roles

**Planning:** product-manager, system-architect, feature-planner, roadmap
**Design:** db-designer, api-designer, ux-designer
**Engineering:** architect (feature-level), backend, frontend, tester, debugger, versioncontroller

All agents read the target project's `CLAUDE.md` for conventions and the generated specs in `rick/prd/specs/` for architectural context. The versioncontroller agent explicitly excludes `rick/prd/` and `rick/agents/` from commits.

## Conventions

- Feature branches: `ai-feature-<timestamp>` from `$BASE_BRANCH`
- PRs created automatically via `gh pr create`
- Design phase runs once per product pipeline; individual feature swarms skip it via `--skip-design`
- Debug retry loop runs `$TEST_CMD` and invokes the debugger agent up to `$MAX_RETRIES` times
- `feature.yaml` documents the pipeline stages; scripts are the source of truth for execution
