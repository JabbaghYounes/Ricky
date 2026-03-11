# Ricky — Feature TODO

## High Impact
- [x] **1. Agent Output Logging** — Save all agent stdout/stderr to `ricky/prd/logs/` with per-run, per-feature, per-agent organization.
- [x] **2. Parallel Feature Swarms** — Run multiple feature swarms concurrently using git worktrees. `MAX_PARALLEL` config (default: 1 = sequential).
- [x] **3. Granular Resume** — Track stage-level progress per feature in `ricky/prd/status/<slug>.status`. Resume from failed stage.
- [x] **4. Cost/Token Tracking** — Log token usage per agent call to CSV. `cost-report.sh` generates reports by agent/feature with cost estimates.

## Medium Impact
- [ ] **5. PR Review Agent** — Self-review agent checks diff before PR creation. Catches security issues, broken patterns, incomplete implementations. Configurable via `ENABLE_REVIEW`.
- [ ] **6. Feature Dependency Ordering** — Product manager defines dependencies between features. `prd-swarm.sh` uses `tsort` for topological ordering. Critical for parallel execution.
- [ ] **7. Notifications** — Slack/Discord webhook notifications on pipeline complete/failure. Auto-detect provider from URL. Fire-and-forget via `curl`.
- [ ] **8. Incremental PRDs** — `--incremental` flag for `run-product.sh`. Extract only new features, skip design if specs exist, reuse existing status.json.

## Nice to Have
- [ ] **9. Custom Agent Support** — `resolve_agent()` function checks `CUSTOM_AGENTS_DIR` before `ricky/agents/`. Users can add/override agents without modifying toolkit.
- [ ] **10. Integration Test Pass** — After all feature PRs, merge branches and run cross-feature integration tests. New `integration-test.sh` script and `integration-tester` agent.
- [ ] **11. Live Progress TUI** — File-based progress tracking + ANSI terminal dashboard. Shows feature/stage/agent/elapsed in real-time. `run-product-tui.sh` wrapper.

## Agent Prompt Improvements (from agentic-coding-rulebook & agents.md)
- [x] **12. Reviewer agent structured checklist** — Created `reviewer.md` with security/performance/correctness/compliance checklist, severity ratings, and "fix critical/major directly, note minor" workflow.
- [x] **13. Tester agent: file-scoped tests + test pyramid** — Updated `tester.md` with test pyramid (60/30/10), determinism rules, behavior-based naming, and file-scoped test command guidance.
- [x] **14. Architect agent: phased implementation breakdown** — Updated `architect.md` with 3-phase output (core logic → error handling → polish) with explicit scope boundaries and phase rules.
- [x] **15. AGENTS.md compatibility** — Updated all 12 agent prompts to check for both `CLAUDE.md` and `AGENTS.md` in target projects.
