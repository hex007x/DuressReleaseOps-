# Test Coverage Tracker

This is the running checklist for new work so we keep proving:

- the feature works
- the fix is protected by tests
- the wider regression gates still cover the common paths

## How To Use

For each meaningful change, record:

- what changed
- whether a unit or functional test was added
- whether an integration test was added
- whether a regression gate was added or rerun
- where the proof lives

Use these status values:

- `Done`
- `Partial`
- `Not yet`

## Current Tracker

| Date | Change Area | Unit / Functional | Integration | Regression Gate | Proof / Notes |
|---|---|---|---|---|---|
| 2026-04-18 | Stripe-first payment link generation | Done | Partial | Done | `PaymentLinkGeneratorTests.cs`; cloud integration suite passed; cloud regression passed |
| 2026-04-18 | Payment workflow routing for Stripe vs Xero vs manual | Done | Partial | Done | Added payment workflow model/config/UI coverage; cloud regression passed |
| 2026-04-18 | Xero auto-created contact email suppression | Done | Partial | Done | `XeroAutoCreatedContactFactoryTests.cs`; `XeroConnectionSettingsProviderTests.cs`; cloud regression passed |
| 2026-04-18 | Xero default sales account for Duress | Done | Partial | Done | Default now falls back to `210`; covered through provider/config tests and cloud regression |
| 2026-04-18 | Self-service signup for new customer and first user | Done | Partial | Done | signup tests added in `DuressCloud.Web.Tests`; cloud regression passed |
| 2026-04-18 | Self-service portal onboarding and purchase | Done | Partial | Done | portal onboarding and purchase tests added; cloud regression passed |
| 2026-04-18 | Guided trial install handoff | Done | Partial | Done | setup script/output tests added; cloud regression passed |
| 2026-04-17 | Claim token repair and legacy-then-claim recovery | Done | Partial | Done | server tests added for legacy-first claim and failed local activation; full regression and licensing proof passed |
| 2026-04-17 | Known issue regressions for recent admin and installer fixes | Done | Partial | Done | known-issue suite added in `DuressReleaseOps`; full proof pack passed |
| 2026-04-17 | Authenticated cloud release smoke | Partial | Done | Done | seeded login/MFA smoke added in `DuressReleaseOps`; downloads/installers proof included |

## Gaps To Keep Closing

- Add more true browser-driven end-to-end tests for purchase, payment, and onboarding flows.
- Add Stripe webhook end-to-end proof once Stripe becomes the primary paid trigger.
- Add Xero invoice creation and sync proof for the EFT/manual invoice path.
- Add upgrade-path regressions for client/server MSI installs as standard release gates.
- Add more visual/layout assertions for key admin and portal pages.
