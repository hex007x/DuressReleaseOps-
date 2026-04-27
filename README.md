# DuressReleaseOps

Cross-project release, regression, and proof orchestration for the Duress platform.

## Scope

- end-to-end regression across `DuressCloud`, `Duress2025`, and `DuressServer2025`
- linked-cloud licensing and claim rehearsals
- release proof packs and evidence capture
- local dev/test release operations

## Workspace layout

This repo is intended to sit inside the shared workspace beside the product repos:

- `DuressReleaseOps`
- `DuressCloud`
- `Duress2025`
- `_external/DuressServer2025`
- `_external/duress-mac`

The scripts resolve the workspace from the parent folder of this repo.

## Documentation layout

Shared cross-project guides live in this repo under `docs/`.

Use this split:

- `DuressReleaseOps`
  - cross-project test guides
  - release-gate guidance
  - evidence/proof-pack tracking
- `DuressCloud`
  - cloud, portal, billing, licensing-control, and commercial-model docs
- `_external/DuressServer2025`
  - server/runtime and licensing-consumer docs
- `Duress2025`
  - Windows client runtime/install docs
- `_external/duress-mac`
  - Mac client runtime/install docs

Shared guides:

- `docs/PLAIN_ENGLISH_END_TO_END_TEST_GUIDE_2026-04-17.md`
- `docs/TECHNICAL_BACKEND_AND_PLATFORM_TEST_GUIDE_2026-04-17.md`
- `docs/REPO_TESTING_AND_DOCUMENTATION_MAP.md`
- `docs/AI_WORKSPACE_RESTART_HANDBOOK.md`

## Current focus

The migrated harness includes the broader regression additions:

- linked-cloud claim
- linked-cloud check-in
- replacement / DR claim
- trusted-key rotation
- combined linked-cloud lifecycle rehearsal

## Entry points

- `test-env/exercise-full-regression-pack.ps1`
- `test-env/exercise-e2e-proof-pack.ps1`
- `test-env/exercise-linked-cloud-regression-suite.ps1`

## Tracking

- `TEST_COVERAGE_TRACKER.md` keeps the running checklist for new work so we record unit, integration, and regression protection as features and fixes land.
