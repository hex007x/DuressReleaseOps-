# Repo Testing And Documentation Map

Last updated: `2026-04-29`

## Purpose

This note explains where documentation and testing guidance should live across the five Duress git repositories.

It exists to stop shared guides drifting into the workspace root and to keep repo-specific docs close to the code they describe.

## The five repos

1. `DuressReleaseOps`
2. `DuressCloud`
3. `Duress2025`
4. `_external/DuressServer2025`
5. `_external/duress-mac`

## Ownership split

### `DuressReleaseOps`

Use for:

- cross-project release orchestration
- regression and proof-pack harnesses
- shared testing guides
- test coverage tracking
- cross-repo release-readiness evidence

Current shared guides:

- [PLAIN_ENGLISH_END_TO_END_TEST_GUIDE_2026-04-17.md](/D:/Duress/DuressReleaseOps/docs/PLAIN_ENGLISH_END_TO_END_TEST_GUIDE_2026-04-17.md)
- [TECHNICAL_BACKEND_AND_PLATFORM_TEST_GUIDE_2026-04-17.md](/D:/Duress/DuressReleaseOps/docs/TECHNICAL_BACKEND_AND_PLATFORM_TEST_GUIDE_2026-04-17.md)
- [AI_WORKSPACE_RESTART_HANDBOOK.md](/D:/Duress/DuressReleaseOps/docs/AI_WORKSPACE_RESTART_HANDBOOK.md)
- [RELEASE_REHEARSAL_CADENCE_2026-05-01.md](/D:/Duress/DuressReleaseOps/docs/RELEASE_REHEARSAL_CADENCE_2026-05-01.md)
- [TEST_COVERAGE_TRACKER.md](/D:/Duress/DuressReleaseOps/TEST_COVERAGE_TRACKER.md)

### `DuressCloud`

Use for:

- cloud architecture
- portal/admin user guides
- customer, payment, licensing-control, and commercial-model docs
- quality strategy for cloud-driven flows
- requirements/design/implementation notes for pricing, billing, portal, and lifecycle workflows

Important docs:

- [QUALITY_AND_REGRESSION_STRATEGY.md](/D:/Duress/DuressCloud/docs/QUALITY_AND_REGRESSION_STRATEGY.md)
- [END_TO_END_LICENSE_AND_CUSTOMER_GUIDE.md](/D:/Duress/DuressCloud/docs/END_TO_END_LICENSE_AND_CUSTOMER_GUIDE.md)
- [MANAGEMENT_SCREENSHOT_REFRESH_RUNBOOK_2026-05-01.md](/D:/Duress/DuressCloud/docs/MANAGEMENT_SCREENSHOT_REFRESH_RUNBOOK_2026-05-01.md)
- [REPORTING_INTERPRETATION_RUNBOOK_2026-05-01.md](/D:/Duress/DuressCloud/docs/REPORTING_INTERPRETATION_RUNBOOK_2026-05-01.md)
- [PRICING_AND_COMMERCIAL_MODEL_EVOLUTION_PLAN.md](/D:/Duress/DuressCloud/docs/PRICING_AND_COMMERCIAL_MODEL_EVOLUTION_PLAN.md)

### `_external/DuressServer2025`

Use for:

- Windows server/service install and runtime docs
- claim/check-in/runtime/licensing-consumer behavior notes
- server-specific technical testing notes

Primary repo-local guide:

- [SERVER_TECHNICAL_TEST_GUIDE.md](/D:/Duress/_external/DuressServer2025/docs/SERVER_TECHNICAL_TEST_GUIDE.md)
- [SERVER_OPERATOR_OBSERVABILITY_RUNBOOK_2026-05-01.md](/D:/Duress/_external/DuressServer2025/docs/SERVER_OPERATOR_OBSERVABILITY_RUNBOOK_2026-05-01.md)

### `Duress2025`

Use for:

- Windows client install/runtime docs
- MSI parameter docs
- workstation and terminal-services behavior notes
- client-specific technical testing notes

Primary repo-local guide:

- [WINDOWS_CLIENT_TECHNICAL_TEST_GUIDE.md](/D:/Duress/Duress2025/docs/WINDOWS_CLIENT_TECHNICAL_TEST_GUIDE.md)

### `_external/duress-mac`

Use for:

- Mac client runtime docs
- build/run notes
- parity/non-parity notes
- Mac-specific smoke and technical test notes

Primary repo-local guide:

- [MAC_CLIENT_TECHNICAL_TEST_GUIDE.md](/D:/Duress/_external/duress-mac/docs/MAC_CLIENT_TECHNICAL_TEST_GUIDE.md)
- [MAC_SUPPORT_ENABLEMENT_RUNBOOK.md](/D:/Duress/_external/duress-mac/docs/MAC_SUPPORT_ENABLEMENT_RUNBOOK.md)
- [MAC_POLICY_FIXTURE_PACK.md](/D:/Duress/_external/duress-mac/docs/MAC_POLICY_FIXTURE_PACK.md)
- [MAC_WEBHOOK_FIXTURE_HARNESS.md](/D:/Duress/_external/duress-mac/docs/MAC_WEBHOOK_FIXTURE_HARNESS.md)
- [MAC_LIVE_VALIDATION_CHECKLIST_2026-04-29.md](/D:/Duress/_external/duress-mac/docs/MAC_LIVE_VALIDATION_CHECKLIST_2026-04-29.md)

Shared entry point from `DuressReleaseOps`:

- [exercise-mac-client-regression-suite.ps1](/D:/Duress/DuressReleaseOps/test-env/exercise-mac-client-regression-suite.ps1)
  - prepares local Mac policy fixtures
  - can collect an SSH-side Mac snapshot
  - can stage generated fixtures onto the Mac desktop before the live session
- [exercise-local-server-mac-rollout-regression.ps1](/D:/Duress/DuressReleaseOps/test-env/exercise-local-server-mac-rollout-regression.ps1)
  - exports a fresh provisioning bundle from the local Windows server install
  - packages the current Mac app with provisioning
  - copies and installs the rollout pack onto the real Mac over SSH/SCP
  - verifies both Mac-side policy state and Windows server runtime policy status
- [exercise-local-server-mixed-client-rollout-regression.ps1](/D:/Duress/DuressReleaseOps/test-env/exercise-local-server-mixed-client-rollout-regression.ps1)
  - exports separate Mac and Windows provisioning bundles from the same local Windows server install
  - installs the Mac rollout pack on the real Mac and the Windows MSI locally
  - mutates server policy live, re-verifies both clients against new signed fingerprints, and captures screenshot evidence on both platforms plus the server monitor

## Working rule

If a document is mainly about one repo’s code or runtime, keep it in that repo.

If a document describes:

- the platform as a whole
- cross-repo release testing
- cross-repo regression strategy
- end-to-end customer journeys spanning Cloud, Server, Client, and billing

then it belongs in `DuressReleaseOps`.
