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
- `exercise-cloud-hostname-tls-rehearsal.ps1`
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
- `verify-published-cloud-installers.ps1 -Version <version>` passes for the exact published release
- real-service protocol / incident / licensing suites are green in a clean environment
- no known local port-collision or stale-shell harness issue is being waived

## Additional Rule For Future Regional Runtime Rollout

If the release scope includes a jurisdiction-specific runtime deployment, add these proof requirements before calling it an RC:

- verify the affected `runtime-<region>` host directly rather than only through compatibility shims
- verify the affected `downloads-<region>` host directly when installer delivery is in scope
- verify the affected `worker-<region>` host directly when regional reporting or escalation delivery is in scope
- rerun linked Cloud/server proof against the intended regional runtime host
- explicitly confirm that residency-bound runtime and operational evidence stayed in-region while global billing and commercial proof still passed

Until a real regional deployment exists, keep the current RC gate set on the single local split and avoid adding fake multi-region ceremony to normal local release rehearsals.

## Recommended Combined Entry Point

Use:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Duress\DuressReleaseOps\test-env\exercise-release-candidate-gates.ps1 -Version <version>
```

That wrapper now combines:

- the full regression pack with real-service requirement
- the Cloud hostname/TLS rehearsal
- the published cloud installer sanity check when the release version is supplied

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
