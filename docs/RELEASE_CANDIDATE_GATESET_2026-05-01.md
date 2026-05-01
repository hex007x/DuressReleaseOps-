# Release Candidate Gate Set

Date: 2026-05-01

## Purpose

This is the stricter proof bar to use before calling a build a release candidate instead of an alpha checkpoint.

## Required Repo-Local Proof

- Windows client hardened release build completes without ad hoc version bump drift.
- Windows client unit suite passes.
- Windows server hardened release build completes.
- Windows server MSI build completes from the solution path.
- Windows server unit suite passes.
- Cloud unit suite passes.
- Cloud integration suite passes.
- Cloud setup/start/verify passes on the current local hosted workflow.

## Required Shared Proof

- `exercise-linked-cloud-regression-suite.ps1`
- `exercise-local-server-mixed-client-rollout-regression.ps1`
- `verify-release.ps1`

## Required Live/Product Proof

- the current published client MSI is present in the Cloud installer library
- the current published server MSI is present in the Cloud installer library
- the Cloud-hosted downloads surface is reachable
- the mixed rollout proof confirms:
  - server-exported Windows provisioning
  - server-exported Mac provisioning
  - server-hosted Mac rollout artifact staging
  - Windows client signed policy proof
  - Mac client signed policy proof
  - alert screenshots on both platforms

## Strongly Preferred Before RC

- `exercise-server-deployment-ui-smoke-suite.ps1` completes cleanly
- real-service protocol / incident / licensing suites are green in a clean environment
- no known local port-collision or stale-shell harness issue is being waived

## Alpha vs RC Rule

Use `Alpha` when:

- core product proof is green
- release notes are honest
- one or more non-core harnesses or environment-specific proofs are still being waived

Use `Release Candidate` only when:

- every required repo-local proof is green
- every required shared proof is green
- no known release-environment waiver is still open
- any skipped or flaky harness has been either fixed or explicitly removed from the gate set
