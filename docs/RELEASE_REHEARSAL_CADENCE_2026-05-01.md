# Release Rehearsal Cadence

This note defines the practical release-rehearsal rhythm for the current Duress workspace.

## Purpose

Use this cadence so the team keeps catching integration drift before a release day crunch.

## Daily Or Frequent Change Work

When changing one repo in a meaningful way:

1. run the repo-local unit and integration suites
2. rerun the most relevant focused regression suite
3. update the repo docs if the operator workflow changed
4. update `TEST_COVERAGE_TRACKER.md` if the proof surface changed

Examples:

- `DuressCloud`: web tests, integration tests, `verify-duress-cloud.ps1`
- `DuressServer2025`: repo-local executable harness, plus the linked Cloud regression when telemetry or claim/check-in changed
- `Duress2025`: client unit/runtime checks plus the focused workflow suites that touch install or policy behavior

## Before An Alpha Or Internal Checkpoint

Run:

1. repo-local product suites for each changed repo
2. `exercise-linked-cloud-regression-suite.ps1`
3. any focused suites affected by the change:
   - policy
   - rollout
   - reporting
   - onboarding
   - pricing/commercial
4. `verify-release.ps1` for the products in scope

## Before A Wider Release Rehearsal

Run:

1. `exercise-full-regression-pack.ps1`
2. `exercise-e2e-proof-pack.ps1` when the cycle needs deeper combined proof
3. Mac rollout proof when Mac is in scope
4. mixed Windows + Mac rollout proof when cross-client policy compatibility changed

## Environment Discipline

Before shared harnesses:

- make sure Cloud is started through the scripted path
- make sure foreign listeners are not occupying `8001` or `8002`
- prefer a clean workstation profile with fewer unrelated background dev services

The shared harness now includes a dedicated isolated-suite port preflight so policy and rollout regressions fail clearly when a foreign listener owns those ports.

## Current Release Gate Shape

For a practical release-grade pass, aim for:

- repo-local unit/integration suites green
- focused workflow regressions green
- linked Cloud/server regression green
- full regression pack green when the environment is clean
- release verification green

## Still Manual Or Limited Areas

These areas still need intentional human review or constrained hardware:

- broader Mac hardware/version coverage
- screenshot refreshes for new admin IA
- live desktop-session proof where the workflow depends on actual foreground UI behavior

