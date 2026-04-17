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

The scripts resolve the workspace from the parent folder of this repo.

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
