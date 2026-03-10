<div align="center">
<pre>
 ██▀███   ██▓ ▄████▄   ██ ▄█▀
▓██ ▒ ██▒▓██▒▒██▀ ▀█   ██▄█▒
▓██ ░▄█ ▒▒██▒▒▓█    ▄ ▓███▄░
▒██▀▀█▄  ░██░▒▓▓▄ ▄██▒▓██ █▄
░██▓ ▒██▒░██░▒ ▓███▀ ░▒██▒ █▄
░ ▒▓ ░▒▓░░▓  ░ ░▒ ▒  ░▒ ▒▒ ▓▒
  ░▒ ░ ▒░ ▒ ░  ░  ▒   ░ ░▒ ▒░
  ░░   ░  ▒ ░░        ░ ░░ ░
   ░      ░  ░ ░      ░  ░
             ░
</pre>
</div>

[![Shell](https://img.shields.io/badge/Shell-Bash-green?logo=gnu-bash&logoColor=white)](https://www.gnu.org/software/bash/)
[![Claude Code](https://img.shields.io/badge/Powered%20by-Claude%20Code-blueviolet?logo=anthropic&logoColor=white)](https://claude.ai/code)
[![GitHub CLI](https://img.shields.io/badge/Uses-GitHub%20CLI-blue?logo=github&logoColor=white)](https://cli.github.com/)
[![PRs Welcome](https://img.shields.io/badge/PRs-welcome-brightgreen.svg)](https://github.com/JabbaghYounes/Rick/pulls)
[![GitHub stars](https://img.shields.io/github/stars/JabbaghYounes/Rick?style=social)](https://github.com/JabbaghYounes/Rick)

A drop-in AI swarm toolkit for autonomous development. Copy the `rick/` folder into any project and go from a PRD to implemented features with pull requests.

## Quick Start

```bash
# 1. Copy rick/ into your project
cp -r rick/ /path/to/your-project/rick/

# 2. Configure for your project
vim rick/rick.conf

# 3. Write your PRD
vim rick/prd/prd.md

# 4. Run the full pipeline
rick/scripts/run-product.sh
```

## How It Works

Rick orchestrates specialized AI agents through a staged pipeline:

```
PRD
 → Product Manager (extract features)
 → Design Phase (architecture, DB, API, UX specs)
 → Per-Feature Swarms
    → Architect → Backend + Frontend (parallel) → Tester → Debugger (retry loop)
 → Git PR per feature
```

The design phase runs once for the whole product. Each feature then gets its own branch (`ai-feature-<timestamp>`) and pull request.

## Structure

```
rick/
  rick.conf        # Project-specific settings (test cmd, base branch, etc.)
  agents/           # Agent prompt definitions (one .md per role)
  pipelines/        # Pipeline stage documentation (YAML)
  prd/
    prd.md          # Your product requirements (edit this)
    features/       # Auto-generated feature files (one per feature)
    specs/          # Auto-generated design specs (architecture, DB, API, UX)
    status.json     # Feature progress tracking
  scripts/
    run-product.sh  # Full pipeline: PRD → design → features → PRs
    swarm.sh        # Run a single feature swarm
    prd-extract.sh  # Extract features from PRD
    prd-swarm.sh    # Run swarm for all extracted features
```

## Configuration

Edit `rick/rick.conf` to match your project:

```bash
# Command to run tests (default: npm test)
TEST_CMD="npm test"

# Base branch for feature branches (default: main)
BASE_BRANCH="main"

# Max debug retries before aborting (default: 3)
MAX_RETRIES=3

# Design agents to run (space-separated, or "none" to skip)
DESIGN_AGENTS="system-architect db-designer api-designer ux-designer"
```

## Scripts

| Script | What it does |
|---|---|
| `run-product.sh` | Full pipeline: extract features, run design phase, run all feature swarms |
| `swarm.sh "<task>"` | Single feature swarm: design → architect → build → test → debug → PR |
| `swarm.sh --skip-design "<task>"` | Single feature swarm without design phase (used by run-product.sh) |
| `prd-extract.sh` | Extract features from PRD into individual files |
| `prd-swarm.sh` | Run swarm for each extracted feature file |

## Agents

| Agent | Role |
|---|---|
| product-manager | Analyzes PRD, extracts feature list |
| system-architect | Designs system-level architecture from PRD |
| architect | Designs feature-level implementation |
| feature-planner | Converts features into engineering tasks |
| roadmap | Breaks PRD into milestones |
| db-designer | Generates database schema |
| api-designer | Defines REST/GraphQL API spec |
| ux-designer | Defines UI flows and components |
| backend | Implements server-side logic |
| frontend | Implements UI and API integration |
| tester | Writes and runs tests |
| debugger | Fixes failing tests (up to MAX_RETRIES) |
| versioncontroller | Manages git commits and PRs |

All agents read the project's `CLAUDE.md` for conventions and the generated specs in `rick/prd/specs/` for architectural context.

## Prerequisites

- [Claude Code](https://claude.ai/code) CLI (`claude`)
- [GitHub CLI](https://cli.github.com/) (`gh`) — for automatic PR creation
- Git
