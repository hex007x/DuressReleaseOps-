# Test Estate Review And Gaps

Last updated: `2026-04-21`

## Purpose

This document reviews the current Duress test estate by layer and by intent.

It is meant to answer:

- what currently proves the product works as intended
- what currently proves the product refuses the wrong thing
- where the remaining gaps are

## Layer review

### 1. Unit and functional tests

Current strongest area:

- `DuressCloud`

Evidence:

- large service/page-model test estate under `DuressCloud.Web.Tests`
- current cloud unit suite passed: `188 / 188`
- strong coverage for:
  - signup and password flows
  - legal acceptance
  - portal gating
  - Stripe/Xero services
  - pricing snapshots
  - renewal policy
  - multi-year renewal terms
  - governance reasons and audit
  - migration rules and strategies

What these currently prove well:

- intended local business rules
- refusal of bad or stale local states
- repricing protection
- quote expiry protection
- migration policy enforcement

### 2. Integration tests

Current strongest area:

- `DuressCloud`

Evidence:

- `DuressCloud.Web.IntegrationTests`
- current cloud integration suite passed: `35 / 35`
- current route/access smoke plus integration coverage recorded in the tracker

What these currently prove well:

- route protection
- basic page accessibility
- some auth and portal-entry behavior

Main limitation:

- integration coverage is still lighter than the unit/functional estate

### 3. Regression gates

Current strongest area:

- `DuressReleaseOps`

Evidence:

- customer onboarding regression suite
- pricing regression suite
- cloud regression suite
- linked-cloud regression suite
- known-issue regression suite
- authenticated cloud smoke
- broader full/e2e proof packs

What these currently prove well:

- major cross-feature flows still work release to release
- recent known defects stay fixed
- pricing/migration/commercial drift is being caught much earlier than before
- communications template/configuration and lifecycle email cadence now have a named focused regression gate as well

### 4. Repo-local runtime tests

Current state:

- Server and Windows client have repo-local test projects and runtime guides
- Server executable harness build and run passed on `2026-04-19`
- Windows client executable harness build and run passed on `2026-04-19`
- Mac client is still smoke-first and much lighter

What this proves:

- server and Windows client have meaningful local test anchors
- Mac still needs deeper executable coverage later

## Repo-by-repo executable review

### `DuressCloud`

Automated shape today:

- `DuressCloud.Web.Tests`
- `DuressCloud.Web.IntegrationTests`
- shared regression suites in `DuressReleaseOps`

Strong positive proof today:

- signup and onboarding
- legal acceptance
- payments, receipts, and portal payment status refresh
- communications template rendering, one-off compose, and customer/staff history visibility
- download entitlement gating
- pricing snapshot creation and carry-through
- renewal policy and multi-year term carry-through
- governance reasons and audit-backed commercial changes
- migration rule and strategy behavior

Strong negative proof today:

- duplicate signup protection
- unsupported password handling
- anonymous challenge coverage on management/admin/portal communications routes
- manual one-off send path without a template still logs the exact payload sent
- missing terms acceptance
- missing governance-reason rejection for commercial-offer changes
- missing governance-reason rejection for migration-rule creation
- self-service trial refusal without current legal acceptance
- self-service purchase refusal without current product-terms acceptance
- self-service purchase refusal for products that require quoting
- expired quote blocking
- draft/unapproved offer exclusion from live pricing
- repricing drift protection
- migration strategy refusal paths
- anonymous-route challenge coverage

Main gap:

- richer browser-driven and visual end-to-end proof beyond the new screenshot-backed cloud visual suite, especially drilling deeper into communications detail views and multi-step lifecycle email verification

### `_external/DuressServer2025`

Automated shape today:

- custom repo-local test harness in `DuressServer2025.Tests`
- shared ReleaseOps linked-cloud and broader regression proof

Current executable proof:

- built with Visual Studio MSBuild
- repo-local executable harness passed on `2026-04-19`

Strong positive proof today:

- notification-provider behavior
- license parsing and refresh branches
- claim/check-in helpers
- trusted-key rotation acceptance
- provisioning bundle and policy behaviors
- compatibility handling

Strong negative proof today:

- malformed/invalid message rejection
- invalid updated license rejection
- no-license/fail-closed claim paths
- unknown rotated-key rejection without trusted bundle
- fingerprint mismatch guidance
- notification failure/retry behavior

Main gaps:

- lighter formal integration-test shape than cloud
- browser/UI proof is naturally limited because the server is not web-first
- newly observed manual defects still need executable protection:
  - fixed on 2026-04-20:
    - notification-provider text boxes now trim persisted values on load/save
    - client-policy monitor no longer collapses reported-but-unverified clients into `Pending Sync`
  - remaining policy risk is now combinatorial depth, not the specific observed textbox/status defects

### `Duress2025`

Automated shape today:

- custom repo-local test harness in `Duress2025.Tests`
- shared ReleaseOps regression proof for installer/download path and broader platform flows

Current executable proof:

- built with Visual Studio MSBuild
- repo-local executable harness passed on `2026-04-19`

Strong positive proof today:

- policy payload parsing
- emergency unlock behavior
- config-root resolution
- webhook config round-trip
- escalation timer lifecycle
- workstation/terminal config migration logic

Strong negative proof today:

- wrong-target emergency unlock rejection
- malformed trusted policy key handling
- malformed emergency unlock handling
- invalid config and mode-resolution edge handling
- legacy registration leak detection

Main gaps:

- limited formal integration-test shape
- runtime visual/UI proof still mostly outside the repo-local automated harness

### `_external/duress-mac`

Automated shape today:

- no executable automated test project currently present in the repo
- smoke-first documentation only

Positive proof today:

- documentation now defines the intended smoke pack

Negative proof today:

- documentation now defines the intended negative smoke observations

Main gaps:

- no real automated unit/integration/regression project yet
- Mac proof now includes local-server Mac-only and mixed Windows-plus-Mac rollout regressions, but it still depends on real Apple hardware and SSH reachability for meaningful runtime validation
- deeper Mac behavioral coverage is still narrower than the Windows client/server/cloud suites

## Positive-proof review

Current positive proof is strong for:

- public signup and first-user onboarding
- trial and purchase legal gating
- payment visibility and status refresh
- download entitlement gating
- quote/payment/subscription snapshot flow
- renewal policy and sold-term carry-through
- migration rule selection and commercial carry-through
- session revocation and boundary controls

## Negative-proof review

Current negative proof is strong for:

- duplicate user and duplicate-company signup handling
- unsupported password input handling
- missing terms acceptance
- expired quote conversion blocking
- unapproved commercial-offer exclusion from live pricing
- repricing drift protection
- `CustomQuoteRequired` migration enforcement
- preserve-current-terms migration protection
- blocked/revoked/invalid licensing behaviors in shared regression coverage

## Main gaps

### Browser and visual proof

Recently improved:

- screenshot-backed browser proof now exists for public signup, invite/password/MFA setup, portal onboarding pages, blocked downloads before entitlement, downloads unlock after entitlement, pending payment creation, pending payment list/detail rendering without premature receipt exposure, seeded Xero/EFT manual-invoice portal rendering, seeded paid portal-state rendering, duplicate-signup refusal, anonymous management redirects, and key management pages

Still weaker than the rest of the estate:

- deeper browser-driven negative-path proof
- broader screenshot-backed coverage for more admin and portal pages

### Stripe live webhook proof

Still environment-limited:

- manual dev/test sync path is covered
- live webhook-first end-to-end proof remains a gap until the environment supports it cleanly

### Xero manual/EFT path

Still needs deeper proof:

- stronger end-to-end accounting and manual-invoice regression

### Mac client depth

Still light:

- smoke-first only
- not yet comparable to Windows client or cloud coverage

## Current recommendation

The next highest-value testing work is:

1. browser-driven onboarding and payment proof
2. screenshot-backed visual regression on key pages
3. deeper Xero manual/EFT regression
4. live Stripe webhook proof when the environment allows it
5. deeper Mac runtime proof

## Current runnable commands

Cloud:

- `dotnet test D:\Duress\DuressCloud\tests\DuressCloud.Web.Tests\DuressCloud.Web.Tests.csproj --configuration Release --nologo`
- `dotnet test D:\Duress\DuressCloud\tests\DuressCloud.Web.IntegrationTests\DuressCloud.Web.IntegrationTests.csproj --configuration Release --nologo`

Server:

- `& 'C:\Program Files\Microsoft Visual Studio\2022\Professional\MSBuild\Current\Bin\MSBuild.exe' D:\Duress\_external\DuressServer2025\DuressServer2025.Tests\DuressServer2025.Tests.csproj /p:Configuration=Release /nologo`
- `& 'D:\Duress\_external\DuressServer2025\DuressServer2025.Tests\bin\Release\DuressServer2025.Tests.exe'`

Windows client:

- `& 'C:\Program Files (x86)\Microsoft Visual Studio\2022\BuildTools\MSBuild\Current\Bin\MSBuild.exe' D:\Duress\Duress2025\Duress2025.Tests\Duress2025.Tests.csproj /p:Configuration=Release /nologo`
- `& 'D:\Duress\Duress2025\Duress2025.Tests\bin\Release\Duress2025.Tests.exe'`

## Related documents

- [QUALITY_AND_REGRESSION_STRATEGY.md](/D:/Duress/DuressCloud/docs/QUALITY_AND_REGRESSION_STRATEGY.md)
- [TEST_COVERAGE_TRACKER.md](/D:/Duress/DuressReleaseOps/TEST_COVERAGE_TRACKER.md)
- [REPO_TESTING_AND_DOCUMENTATION_MAP.md](/D:/Duress/DuressReleaseOps/docs/REPO_TESTING_AND_DOCUMENTATION_MAP.md)
