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

Shared test-guidance ownership:

- cross-project test guides live in `DuressReleaseOps/docs`
- cloud/commercial design and quality strategy docs live in `DuressCloud/docs`

Use these status values:

- `Done`
- `Partial`
- `Not yet`

## Current Tracker

| Date | Change Area | Unit / Functional | Integration | Regression Gate | Proof / Notes |
|---|---|---|---|---|---|
| 2026-04-18 | Stripe-first payment link generation | Done | Partial | Done | `PaymentLinkGeneratorTests.cs`; cloud integration suite passed; cloud regression passed |
| 2026-04-18 | Stripe webhook tracking and primary paid activation | Done | Partial | Done | `StripeWebhookProcessorTests.cs`; cloud integration suite passed; cloud regression passed |
| 2026-04-18 | Stripe-paid accounting sync into Xero after activation | Done | Partial | Done | `PaymentAccountingSyncServiceTests.cs`; `PaymentActivationServiceTests.cs`; `XeroConnectionSettingsProviderTests.cs`; cloud regression passed |
| 2026-04-18 | Manual Stripe status sync for dev and test without webhooks | Done | Partial | Done | `StripePaymentSyncServiceTests.cs`; admin payment workflow updated; cloud regression passed |
| 2026-04-18 | Stripe customer linkage and billing identity sync | Done | Partial | Done | `StripeCustomerServiceTests.cs`; `PaymentLinkGeneratorTests.cs`; full cloud unit + integration suites passed |
| 2026-04-18 | Xero-after-payment customer reconciliation back into Stripe | Done | Partial | Done | `PaymentAccountingSyncServiceTests.cs`; `XeroAutoCreatedContactFactoryTests.cs`; full cloud unit + integration suites passed |
| 2026-04-18 | Payment workflow routing for Stripe vs Xero vs manual | Done | Partial | Done | Added payment workflow model/config/UI coverage; cloud regression passed |
| 2026-04-18 | Xero auto-created contact email suppression | Done | Partial | Done | `XeroAutoCreatedContactFactoryTests.cs`; `XeroConnectionSettingsProviderTests.cs`; cloud regression passed |
| 2026-04-18 | Xero default sales account for Duress | Done | Partial | Done | Default now falls back to `210`; covered through provider/config tests and cloud regression |
| 2026-04-18 | Self-service signup for new customer and first user | Done | Partial | Done | signup tests added in `DuressCloud.Web.Tests`; cloud regression passed |
| 2026-04-18 | Signup address capture, same-as billing controls, and invite-email success state | Done | Partial | Done | `SelfServiceSignupTests.cs`; `MarkupRegressionTests.cs`; focused signup regression pass completed |
| 2026-04-18 | Google Places address lookup on signup and configuration-managed API key | Done | Partial | Done | `ConfigurationIndexModelTests.cs`; `MarkupRegressionTests.cs`; full cloud unit + integration suites passed; cloud regression passed |
| 2026-04-18 | Signup optional-field fix and live success-state walkthrough proof | Done | Partial | Done | `SelfServiceSignupTests.cs`; `MarkupRegressionTests.cs`; live signup walkthrough created customer + user in dev DB; full cloud unit + integration suites passed; cloud regression passed |
| 2026-04-18 | Reset-password character guidance and clearer unsupported-character handling | Done | Partial | Done | `ResetPasswordModelTests.cs`; `MarkupRegressionTests.cs`; focused reset-password coverage added |
| 2026-04-18 | Portal download entitlement gating and clearer license vs subscription messaging | Done | Done | Done | `PortalDownloadAccessTests.cs`; `MarkupRegressionTests.cs`; full cloud unit + integration suites passed |
| 2026-04-18 | Versioned product and trial terms acceptance before self-service trial | Done | Done | Done | `PortalLegalTermsServiceTests.cs`; `PortalSelfServiceOnboardingTests.cs`; `MarkupRegressionTests.cs`; full cloud unit + integration suites passed |
| 2026-04-18 | Product terms gate on purchase flow and management legal document editor | Done | Done | Done | `PortalLegalTermsServiceTests.cs`; `MarkupRegressionTests.cs`; full cloud unit + integration suites passed |
| 2026-04-18 | Product-configured self-service trial length and admin product editing | Done | Done | Done | `PortalSelfServiceOnboardingTests.cs`; `AdminProductTrialConfigurationTests.cs`; `MarkupRegressionTests.cs`; cloud integration suite passed; DB migration applied |
| 2026-04-18 | Self-service portal onboarding and purchase | Done | Partial | Done | portal onboarding and purchase tests added; cloud regression passed |
| 2026-04-18 | Guided trial install handoff | Done | Partial | Done | setup script/output tests added; cloud regression passed |
| 2026-04-19 | Customer onboarding journey from signup through trial/purchase gating | Done | Partial | Done | New `exercise-customer-onboarding-regression-suite.ps1` proves signup, invite/password setup, MFA, legal acceptance, trial download unlock, and self-service purchase creation; wired into cloud/full/e2e release gates |
| 2026-04-19 | Pricing foundation entities, billing-plan seed, and product family/version/offer backfill | Done | Partial | Done | `PricingFoundationInitializerTests.cs`; dedicated pricing regression suite added and cloud regression suite passed with pricing gate included |
| 2026-04-19 | Quote pricing snapshots, expired-quote protection, and quote-prefill repricing protection | Done | Partial | Done | `AdminQuoteCreatePricingSnapshotTests.cs`; `AdminPaymentCreateTests.cs`; dedicated pricing regression suite added and passing; quote-based payment creation now blocks expired quotes and prefers snapshot values over drifted commercial fields |
| 2026-04-19 | Subscription snapshot carry-through, renewal snapshot reuse, renewal-pricing policy behavior, sold renewal-term carry-through, renewal-prefill repricing protection, and admin commercial snapshot visibility | Done | Partial | Done | `SubscriptionLifecycleServiceTests.cs`; `AdminPaymentCreateTests.cs`; `MarkupRegressionTests.cs`; dedicated pricing regression suite added and passing; renewals now carry an explicit pricing policy and sold renewal term so standard locked renewals stay protected, current-offer renewals can intentionally reprice, and multi-year renewals extend by the purchased term |
| 2026-04-19 | Admin commercial-offer management and catalog-sync protection for term-based renewal pricing | Done | Done | Done | `AdminProductOfferManagementTests.cs`; `PricingFoundationInitializerTests.cs`; `MarkupRegressionTests.cs`; integration route coverage added; local DB migration applied; pricing and cloud regression suites passed with the new offer-management slice in place |
| 2026-04-19 | Governance reasons and immutable audit coverage for negotiated discounts and commercial-offer changes | Done | Done | Done | `AdminProductOverrideGovernanceTests.cs`; `AdminProductOfferManagementTests.cs`; `MarkupRegressionTests.cs`; cloud unit + integration suites passed; pricing regression passed; cloud regression passed after clearing stale build daemons so the local app and Release build could coexist cleanly |
| 2026-04-19 | Named commercial offers with approval-state control so only approved offers drive live pricing and renewal repricing | Done | Done | Done | `AdminProductOfferManagementTests.cs`; `AdminPaymentCreateTests.cs`; `PricingFoundationInitializerTests.cs`; `MarkupRegressionTests.cs`; migration `20260419063305_AddProductVersionOfferApprovalWorkflow`; full cloud unit + integration suites passed; pricing regression passed; cloud regression passed |
| 2026-04-19 | Product migration rule foundation with governed admin management for tier upgrades and legacy replacement paths | Done | Done | Done | `AdminProductMigrationRuleTests.cs`; `MarkupRegressionTests.cs`; migration `20260419070359_AddProductMigrationRuleFoundation`; full cloud unit + integration suites passed; pricing regression passed; cloud regression passed |
| 2026-04-19 | Migration-aware quote and payment snapshots so commercial records preserve the selected product migration rule and pricing reason | Done | Done | Done | `AdminQuoteCreatePricingSnapshotTests.cs`; `AdminPaymentCreateTests.cs`; `MarkupRegressionTests.cs`; migration `20260419072453_AddMigrationRuleCommercialLinkage`; full cloud unit + integration suites passed; pricing regression passed; cloud regression passed |
| 2026-04-19 | Migration context carried into subscriptions and surfaced across admin quote, payment, and subscription detail pages | Done | Done | Done | `SubscriptionLifecycleServiceTests.cs`; `MarkupRegressionTests.cs`; migration `20260419074909_CarryMigrationRuleIntoSubscriptions`; full cloud unit + integration suites passed; pricing regression passed; cloud regression passed |
| 2026-04-19 | Migration pricing strategy enforcement for quote-first and preserve-current-terms workflows | Done | Done | Done | `AdminPaymentCreateTests.cs`; `MarkupRegressionTests.cs`; full cloud unit + integration suites passed; pricing regression passed; cloud regression passed; direct payment creation now blocks `CustomQuoteRequired` migrations, and `PreserveCurrentTermsUntilRenewal` keeps source commercial values instead of repricing onto the target offer |
| 2026-04-19 | Subscription-originated migration quotes with preserved commercial terms and clearer admin migration guidance | Done | Done | Done | `AdminQuoteCreatePricingSnapshotTests.cs`; `MarkupRegressionTests.cs`; full cloud unit + integration suites passed; pricing regression passed; cloud regression passed; subscription detail now starts governed migration quotes and preserve-current-terms strategy carries the source subscription commercial values into the quote snapshot |
| 2026-04-19 | Extra negative-path protection for onboarding, governance, and route boundaries | Done | Done | Done | `PortalSelfServiceOnboardingTests.cs`; `AdminProductOfferManagementTests.cs`; `AdminProductMigrationRuleTests.cs`; `PortalEntryTests.cs`; cloud unit suite `188/188`; cloud integration suite `35/35`; governance reasons, legal refusal paths, quote-only product refusal, and anonymous route challenges all re-proved |
| 2026-04-19 | Cloud browser-backed positive and negative visual proof for signup, onboarding, downloads, payments, and management pages | Partial | Partial | Done | `exercise-cloud-browser-visual-suite.ps1` and `cloud-browser-visual-proof.py`; real browser screenshots now capture signup, invite/password/MFA, blocked downloads before entitlement, trial/purchase disabled before terms, duplicate-signup refusal, anonymous management redirect, portal home/trial/purchase/downloads, pending payment creation, pending payment list/detail behavior without premature receipts, seeded Xero/EFT portal-state proof, seeded paid payment portal-state proof, and management legal/product pages; wired into cloud regression |
| 2026-04-20 | MFA reauthentication preserves bound form state instead of resetting to defaults on sensitive-action screens | Done | Done | Done | `AdminLicenseCreateMfaStateTests.cs`; `ManagementSecurityMfaStateTests.cs`; `CustomerTrialExtensionRegressionTests.cs`; shared `ReauthDraftState` helper added; cloud unit suite `194/194`; cloud integration suite `35/35`; cloud regression suite passed after live/browser rerun |
| 2026-04-20 | Customer billing preference workflow for Stripe vs EFT / Xero invoice request and approval routing | Done | Done | Done | `PortalSelfServiceOnboardingTests.cs`; `AdminCustomerBillingPreferenceTests.cs`; customer purchase path now routes EFT customers to `XeroInvoice` workflow without generating a Stripe link; admin customer detail now supports direct-set, approve, and decline actions with MFA gating; cloud unit suite `199/199`; cloud integration suite `35/35`; cloud regression passed |
| 2026-04-20 | EFT / Xero invoice preparation at first commercial use with Duress-owned invoice communications | Done | Done | Done | `EftInvoiceWorkflowServiceTests.cs`; `PortalSelfServiceOnboardingTests.cs`; EFT customers now link/create Xero contact on first commercial use, prepare Xero invoice immediately, show invoice link in portal when available, and log/send invoice communications from Duress; cloud unit suite `201/201`; cloud integration suite `35/35`; cloud regression passed |
| 2026-04-20 | Portal support ticketing, entitlement gating, attachment handling, and staff ticket workflow | Done | Done | Done | `SupportTicketEntitlementEvaluatorTests.cs`; `SupportTicketServiceTests.cs`; `MarkupRegressionTests.cs`; portal home now exposes ticketing, portal ticket create/reply is gated to active trial or active paid customers, and admin queue/detail supports assignment, internal notes, and customer-visible replies; cloud unit suite `218/218`; cloud integration suite `35/35`; cloud regression passed |
| 2026-04-20 | License invalidation workflow with MFA-protected draft-state preservation | Done | Partial | Done | `AdminLicenseDetailsMfaStateTests.cs`; `MarkupRegressionTests.cs`; admin license detail now supports explicit invalidation with reason and audit trail, invalidated licenses return an invalid/support message at check-in, and reauthentication preserves the invalidation reason draft; cloud unit suite `218/218`; cloud regression passed |
| 2026-04-20 | Trial and renewal lifecycle email cadence automation | Done | Partial | Done | `CommunicationAutomationWorker.cs`; trial welcome/value/expiry cadence and explicit 8/4/2/1 week renewal reminders are now automated and log through `CommunicationLogs`; full cloud unit + integration suites passed and cloud regression passed |
| 2026-04-21 | HTML templated communications management, one-off customer compose, and communication history/detail filtering | Done | Done | Done | `CommunicationTemplateRendererTests.cs`; `ManagementCommunicationsIndexTests.cs`; `AdminCommunicationsIndexTests.cs`; `AdminCommunicationCreateTests.cs`; `AdminCommunicationDetailsTests.cs`; `PortalCommunicationsIndexTests.cs`; anonymous route coverage now includes management/admin communications surfaces; browser visual suite now captures management communications settings and admin communications history pages; cloud unit + integration suites passed and cloud regression/browser suite rerun |
| 2026-04-20 | Server UI defects: notification webhook text boxes prefilled with leading spaces and client-policy monitor/status mismatch still unresolved | Done | n/a | Server harness passed | Fixed in `_external/DuressServer2025`: persisted notification/provider values are trimmed on load/save, backup-folder creation is hardened during settings save, and monitor policy state now distinguishes `Pending Sync` from `Unverified`. Regression coverage added in `DuressServer2025.Tests` for webhook setting trimming and policy-state text reconciliation. |
| 2026-04-19 | Repo-local executable proof refresh for Server and Windows client | Done | Partial | Partial | Server harness built with Visual Studio MSBuild and passed via `DuressServer2025.Tests.exe`; Windows client harness built with Visual Studio MSBuild and passed via `Duress2025.Tests.exe`; shared ReleaseOps suites remain the cross-repo regression layer |
| 2026-04-17 | Claim token repair and legacy-then-claim recovery | Done | Partial | Done | server tests added for legacy-first claim and failed local activation; full regression and licensing proof passed |
| 2026-04-17 | Known issue regressions for recent admin and installer fixes | Done | Partial | Done | known-issue suite added in `DuressReleaseOps`; full proof pack passed |
| 2026-04-17 | Authenticated cloud release smoke | Partial | Done | Done | seeded login/MFA smoke added in `DuressReleaseOps`; downloads/installers proof included |

## Gaps To Keep Closing

- Add more true browser-driven and screenshot-backed end-to-end tests for purchase, payment, and onboarding flows beyond the current browser-backed cloud visual suite.
- Add Stripe webhook end-to-end proof once Stripe becomes the primary paid trigger.
- Add Xero invoice creation and sync proof for the EFT/manual invoice path.
- Add upgrade-path regressions for client/server MSI installs as standard release gates.
- Add more visual/layout assertions for key admin and portal pages.
- Expand pricing-model regression gates further for quote expiry edge cases, migration pricing, and separate renewal-policy administration once the next commercial slices are in place.
- Add a real executable automated test layer for `_external/duress-mac`; it is still the weakest repo from a runnable-proof perspective.
