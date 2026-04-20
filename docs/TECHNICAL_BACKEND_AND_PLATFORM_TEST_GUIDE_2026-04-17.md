# Technical Backend And Platform Test Guide

Last updated: `2026-04-19`

This guide is the technical companion to the plain-English end-to-end staff test guide.

Use this document for technical validation done by:

- engineers
- implementation technicians
- deployment/support technicians
- release testers
- anyone validating backend, platform, infrastructure, security, or system-behavior details

This guide is intentionally broader than user-facing testing.

It includes areas that ordinary staff may never see directly but which still need proof before a release can be trusted.

## Relationship to the user-focused guide

This guide does not replace the user-focused test guide.

Use the two guides together:

- [PLAIN_ENGLISH_END_TO_END_TEST_GUIDE_2026-04-17.md](/D:/Duress/DuressReleaseOps/docs/PLAIN_ENGLISH_END_TO_END_TEST_GUIDE_2026-04-17.md)
  - customer journeys
  - staff workflows
  - portal/admin/business scenarios
- this technical backend/platform guide
  - auth and security controls
  - tenancy boundaries
  - backend correctness
  - cloud/licensing integrity
  - operational resilience
  - deployment/runtime/environment behavior
  - integration behavior
  - failure and recovery behavior
- [QUALITY_AND_REGRESSION_STRATEGY.md](/D:/Duress/DuressCloud/docs/QUALITY_AND_REGRESSION_STRATEGY.md)
  - positive vs negative coverage expectations
  - unit/integration/regression-gate layering
  - current quality gaps and release-gate expectations

## Main purpose

This guide answers:

- does the backend behave correctly
- are auth and security controls really enforced
- do cloud, licensing, and integrations remain trustworthy under error conditions
- does the platform behave correctly across installs, upgrades, cutovers, and failures

## Core model testers must keep separate

Technical testers should treat these as separate layers:

- `Product`: commercial catalog definition
- `Subscription`: commercial lifecycle state
- `License`: technical entitlement issued to a server or installation

Do not collapse these concepts in test design.

Use this boundary:

- test `Product` for catalog, country, currency, pricing, billing plans, and versioning
- test `Subscription` for activation, renewal, cancellation, grace, commitment, and lifecycle automation
- test `License` for signing, claim, delivery, check-in, expiry, revocation, feature entitlement, and server enforcement

Most defects around commercial/licensing logic happen in the handoff points between these layers, so regression coverage should explicitly test the transitions as well as the layers themselves.

## Suggested execution order

Run this guide in the following order:

1. auth, session, and permission boundaries
2. tenancy and data-isolation boundaries
3. licensing, claim, and check-in integrity
4. signup, legal acceptance, and tenant bootstrap integrity
5. payments, subscriptions, and fulfillment integrity
6. integrations and secret handling
7. deployment, environment, and runtime behavior
8. failure, recovery, and tamper-style behavior

## Evidence expectations

For every technical scenario, record:

- environment
- build/version
- tester
- accounts/customer/system used
- logs or screenshots
- exact observed result
- whether the result is acceptable, not just whether it "worked"

## Positive and negative backend expectation

Technical testing must prove both:

- the backend does the right thing when given valid state
- the backend refuses or contains the wrong thing when given invalid, stale, unauthorized, duplicate, or drifted state

Examples:

- valid renewal extends by the sold term
- expired quote does not create a payment
- approved commercial offer drives pricing
- draft or unapproved commercial offer does not
- preserve-current-terms migration keeps source pricing
- target-current-offer migration only reprices when that rule is selected

## Status labels

Use:

- `Pass`
- `Pass with note`
- `Fail`
- `Blocked`
- `Not applicable in this environment`

## Section 1. Authentication and session controls

### Scenario 1. Staff login succeeds only with valid credentials

Purpose:

- prove the management login boundary is real

Validate:

- valid login works
- wrong password fails
- disabled or unauthorized staff user cannot log in
- error behavior is safe and not overly revealing

Expected result:

- only valid staff credentials gain access
- failed login responses do not leak sensitive detail

### Scenario 2. Customer portal login is isolated from staff login

Purpose:

- prove portal and management identity flows stay distinct

Validate:

- staff credentials do not accidentally behave like portal credentials
- portal credentials do not grant management access
- URLs and redirects stay in the correct domain/context

Expected result:

- staff and customer auth boundaries remain separate

### Scenario 3. MFA setup, challenge, and repeat login behavior

Purpose:

- prove MFA is genuinely part of the auth model

Validate:

- initial MFA enrollment
- login challenge after MFA setup
- failed MFA code handling
- repeat login from a new browser/session
- MFA reset flow for staff and customer users

Expected result:

- MFA is consistently required where expected
- failure handling is safe and recoverable

### Scenario 4. Session timeout and forced session invalidation

Purpose:

- prove session policy is enforced

Validate:

- timeout after idle period
- behavior near timeout boundary
- session invalidation after sign-out-all-sessions
- old browser tabs after session invalidation

Expected result:

- expired sessions cannot keep operating silently
- sign-out-all-sessions really removes access

### Scenario 5. Sensitive-action reauthentication window

Purpose:

- prove high-risk actions require fresh identity proof

Validate:

- blocked access to sensitive actions before unlock
- successful unlock
- action execution within unlock window
- unlock expiry
- reauthentication requirement after expiry

Actions to test:

- mark paid
- trial extension
- Xero-sensitive actions
- signing-key actions
- server transfer/replacement actions

Expected result:

- sensitive actions cannot be performed casually from a stale session

### Scenario 6. Lockout and brute-force resistance behavior

Purpose:

- prove repeated failures trigger the expected controls

Validate:

- repeated failed logins
- lockout duration
- post-lockout recovery
- support/admin recovery path for test accounts

Expected result:

- repeated failures trigger protection without creating unrecoverable states

## Section 2. Authorization, role boundaries, and tenant isolation

### Scenario 7. Staff role permissions behave as intended

Purpose:

- prove internal roles do not overreach

Validate each role:

- platform admin
- licensing admin
- support admin
- billing admin
- read-only admin

Check:

- visible navigation
- accessible actions
- blocked actions
- blocked direct URL access attempts

Expected result:

- each role sees and does only what its function should allow

### Scenario 7A. Session-revocation boundaries for customer and staff users

Purpose:

- prove the new session-invalidation controls respect the expected governance boundaries

Validate:

- customer user can revoke their own sessions from portal security
- customer admin can revoke sessions for other users in the same tenant
- customer admin cannot revoke sessions across tenants
- management user can revoke sessions for external/customer users
- management user can revoke sessions for staff users
- current-user self-session handling still goes through the intended security page rather than bypassing controls through the user grid

Expected result:

- each revoke path works only inside its intended authority boundary

### Scenario 8. Customer roles behave as intended

Purpose:

- prove customer users stay within their intended portal scope

Validate:

- customer admin
- billing
- read-only

Check:

- view-only vs manage-user actions
- payment/license/quote visibility
- invite/deactivate/MFA-reset controls

Expected result:

- customer role boundaries are real, not cosmetic

### Scenario 9. Tenant isolation between customers

Purpose:

- prove one customer cannot see another customer’s data

Validate:

- direct URL attempts across tenants
- list filtering
- detail pages
- downloads
- license documents

## Section 3. Product, subscription, and license integrity

### Scenario 10. Product selection creates the correct commercial state

Purpose:

- prove the selected product drives the correct quote/payment/commercial state

Validate:

- standard product selection
- flexible product selection
- negotiated quote path
- pricing snapshot or equivalent sold-state capture

Expected result:

- the commercial record reflects the intended product and sold commercial terms

### Scenario 11. Subscription activation follows commercial payment correctly

Purpose:

- prove paid commercial records activate or renew the correct subscription state

Validate:

- new activation
- renewal
- grandfathered or protected sold pricing where applicable
- no unintended drift from later catalog edits

Expected result:

- subscription state changes correctly without mutating historical commercial truth

### Scenario 12. License issuance reflects the intended technical entitlement

Purpose:

- prove the issued license is the technical output of the commercial state

Validate:

- seat/user entitlement
- expiry
- linked system or installation
- active vs blocked vs revoked behavior
- signed payload contents where appropriate

Expected result:

- the license reflects the intended entitlement and can be validated independently of the live catalog

### Scenario 13. Product-to-subscription-to-license handoff remains coherent

Purpose:

- prove the boundaries between commercial and technical layers are preserved

Validate:

- product can change without silently rewriting old subscription truth
- subscription renewal does not corrupt historical license records
- license refresh reflects the correct current entitlement
- support/admin views stay explainable

Expected result:

- each layer keeps its own responsibility and the handoffs remain traceable

### Scenario 14. Future feature-module entitlement can be represented cleanly

Purpose:

- prepare for a base product plus paid feature/module model

Validate:

- commercial records can represent a base product plus a priced module
- pricing snapshot can capture the sold combination
- technical entitlement can represent the resulting enabled features

Expected result:

- the system is able to distinguish:
  - what was sold commercially
  - what was activated as a subscription
  - what was enabled technically in the license
- payment and quote details
- communications history

Expected result:

- tenant data is fully isolated

### Scenario 10. Ownership transfer and user membership changes do not leak access

Purpose:

- prove identity and membership changes are safe

Validate:

- user invite accepted after role change
- deactivated user loses access
- reactivated user regains appropriate access only
- ownership/admin changes do not leave stale elevated access

Expected result:

- access follows current membership and role state only

## Section 3. Secret handling, key management, and secure configuration

### Scenario 11. Secrets entered through management UI are not exposed back to operators

Purpose:

- prove secret masking/storage behavior is acceptable

Validate:

- SMTP secrets
- public API secrets
- Xero credentials
- Stripe/webhook-related secrets
- any other integration secrets configured in management

Check:

- masked display
- edit/update behavior
- save-without-reveal behavior
- no accidental echo in normal UI flows

Expected result:

- secrets are not trivially retrievable through the UI

### Scenario 12. Signing-key lifecycle controls work safely

Purpose:

- prove key management is operationally safe

Validate:

- create standby key
- activate key
- retire key
- mark compromised key
- approval flow where present

Expected result:

- key-state transitions are controlled, auditable, and do not silently break licensing

### Scenario 13. Generated URLs use the configured platform base URLs

Purpose:

- prove email and portal links are environment-correct

Validate:

- password reset links
- invite links
- payment links
- trial/lifecycle emails
- portal handoff links

Expected result:

- generated links use the configured platform URLs, not stray dev ports or wrong hosts

## Section 4. Customer, system, and onboarding backend integrity

### Scenario 14. Customer creation prevents unsafe duplication or ambiguous linkage

Purpose:

- prove customer identity handling is safe

Validate:

- exact duplicate customer details
- overlapping emails
- ambiguous public onboarding matches
- manual resolution flow

Expected result:

- duplicate or ambiguous state becomes reviewable rather than silently wrong

### Scenario 15. System records remain correctly bound to customer and claim state

Purpose:

- prove systems remain trustworthy units of licensing and lifecycle

Validate:

- system create/edit
- claim token generation/rotation
- claim status changes
- unhealthy-system visibility

Expected result:

- system identity remains clear and operationally usable

### Scenario 16. Public signup bootstrap creates the correct customer and first user

Purpose:

- prove the self-service signup flow creates the right records and links them correctly

Validate:

- new customer creation
- first portal user creation
- invite/setup email generation
- customer/user linkage
- duplicate-user and duplicate-company handling

Expected result:

- a clean new customer and first user are created once
- the success state is explicit and email-driven
- duplicate matches are routed into recovery or review rather than creating bad records

### Scenario 17. Address lookup and manual fallback save stable customer data

Purpose:

- prove the signup address flow saves usable organisation and billing data even when lookup is imperfect

Validate:

- address lookup selection populates line 1/line 2/locality/state/postcode/country correctly
- manual fallback path still saves valid address data
- `same as organisation address` sync behaves correctly
- `billing entity same as organisation` behaves correctly

Expected result:

- customer profile data is complete enough for Stripe, Xero, and support use
- the backend does not keep half-populated or contradictory billing data

### Scenario 18. Legal terms versioning and acceptance enforcement

Purpose:

- prove current product and trial terms are enforced, versioned, and recorded correctly

Validate:

- current product terms requirement on purchase
- current product + trial terms requirement on trial start
- acceptance record creation
- accepted-by user, email, IP, user agent, and timestamp capture
- email-copy generation
- re-acceptance requirement when versions change
- management/customer visibility of the acceptance history

Expected result:

- customers cannot bypass current legal acceptance
- the backend can prove exactly which version was accepted and by whom

## Section 5. Licensing trust, claim, and check-in integrity

### Scenario 16. Initial cloud claim binds the correct server fingerprint

Purpose:

- prove first claim establishes the right trust relationship

Validate:

- claim with valid token
- claim with blank token
- claim with wrong token
- repeat claim attempt after successful claim

Expected result:

- valid claim succeeds once and binds the correct server
- invalid claim attempts fail safely

### Scenario 17. Cloud check-in updates runtime state without corrupting entitlement

Purpose:

- prove ordinary cloud-linked operation is stable

Validate:

- healthy periodic check-in
- telemetry visibility
- current-state response
- renewed-license response
- invalid/blocked response

Expected result:

- check-in updates state correctly and safely

### Scenario 18. Signed license validation rejects bad or mismatched input

Purpose:

- prove licensing trust is enforced, not only present

Validate:

- valid signed license
- invalid signature
- expired license
- wrong server fingerprint
- revoked/blocked state where applicable
- rotated-key license without trusted key bundle
- rotated-key license with trusted key bundle

Expected result:

- only acceptable license states validate

### Scenario 19. Manual signed-license import behaves safely

Purpose:

- prove manual support fallback does not bypass integrity checks

Validate:

- import valid signed license
- import malformed XML
- import wrong-fingerprint license
- import invalid-signature license

Expected result:

- manual import remains a controlled support path, not a bypass

### Scenario 20. Replacement / DR flow leaves a readable and safe state

Purpose:

- prove server transfer logic protects entitlement and helps support understand what happened

Validate:

- prepare replacement
- claim replacement server
- old server state after cutover
- cutover completion
- cancellation flow
- previous-server retirement

Expected result:

- replacement is controlled
- mismatch states are operator-readable
- the previous server does not stay quietly valid

### Scenario 20A. Legacy registration followed by cloud claim recovers cleanly

Purpose:

- prove a mistaken legacy/manual registration does not permanently break later cloud-claim onboarding

Validate:

- legacy/manual registration state exists first
- later claim-token path still succeeds
- stale local legacy-license files do not block activation
- claim only reports success if a valid active signed/cloud license is actually present locally

Expected result:

- the server ends in a real signed/cloud-managed state
- support is not left with a fake “claim succeeded” but still-invalid server

## Section 6. Subscription, billing, and fulfillment backend correctness

### Scenario 21. Product and pricing snapshots remain stable through quote and payment conversion

Purpose:

- prove later edits do not silently rewrite historical commercial intent

Validate:

- create quote/payment from product
- apply negotiated pricing override
- change catalog later
- review existing quote/payment/subscription snapshot

Expected result:

- historic records preserve the expected pricing context

### Scenario 21A. Product catalog controls the default self-service trial duration

Purpose:

- prove self-service trial duration is product-configured rather than hard-coded

Validate:

- product catalog item stores a default self-service trial length
- portal trial page reads the configured value
- trial start writes `TrialEndUtc` from configured product days
- management product editing changes the live default

Expected result:

- the website offer and product backend can stay aligned
- trial duration changes do not require code edits

### Scenario 22. Paid-state handling does not over-fulfill or double-fulfill

Purpose:

- prove payment fulfillment is idempotent and operationally safe

Validate:

- first paid apply
- repeated sync/apply attempts
- payment without system assignment
- later system assignment
- ready-for-fulfillment transition

Expected result:

- the same payment does not create duplicate entitlements or conflicting outcomes

### Scenario 23. Trial, subscription, and renewal states progress correctly over time

Purpose:

- prove lifecycle state logic is internally consistent

Validate:

- active trial
- extended trial
- expired trial
- active subscription
- grace-period behavior
- cancellation
- reactivation
- renewal extension on payment

Expected result:

- lifecycle states are coherent across customer, subscription, payment, and license views

## Section 7. Integration behavior

### Scenario 24. Xero contact match and invoice flow behaves safely

Purpose:

- prove accounting integration does not create wrong-customer outcomes

Validate:

- existing-contact match
- ambiguous match
- new-contact create
- draft or authorised invoice create according to configuration
- invoice update
- sync back into Duress
- paid-state import
- suppression of Xero reminder emails for Duress-created contacts where intended

Expected result:

- Xero actions target the correct contact and maintain traceable state

### Scenario 24A. Stripe customer identity is modeled correctly against the Duress customer

Purpose:

- prove Stripe is not just receiving an email address but a usable cross-system customer identity

Validate:

- Stripe customer creation/update
- billing email, billing entity, phone, address, and ABN sync
- Stripe customer id persisted in Duress
- Xero contact id/contact number added into Stripe metadata once known

Expected result:

- Stripe, Duress, and Xero can be reconciled against the same customer identity

### Scenario 24B. Stripe-first payment flow updates backend state without waiting on Xero timing

Purpose:

- prove card payments now use Stripe as the customer-facing critical path

Validate:

- Stripe payment-link generation
- payment/session identifiers stored in Duress
- paid status sync from Stripe
- portal/admin refresh of payment status in dev/test without webhooks
- immediate activation/fulfillment path after Stripe-paid confirmation
- downstream Xero accounting sync after payment

Expected result:

- customer activation is not blocked by Xero send/sync timing
- accounting still lands afterward in Xero cleanly

### Scenario 24C. Stripe receipt and payment-status data flow back into the portal correctly

Purpose:

- prove the customer can see a trustworthy paid state and receipt path after Stripe payment

Validate:

- open payments render as `Pending` rather than confusing `Draft` language on the customer side
- refresh-status path updates from Stripe
- receipt number / session / identifying details are surfaced
- receipt download URL is exposed when Stripe provides it

Expected result:

- the customer portal reflects Stripe-paid state accurately and supportably

### Scenario 25. Scheduled Xero sync does not hide what automation changed

Purpose:

- prove automation remains supportable

Validate:

- scheduled sync enabled
- one or more sync cycles
- audit/history of automation actions
- staff visibility into next required manual action

Expected result:

- automated accounting sync is visible and understandable

### Scenario 26. Outbound email infrastructure behaves correctly

Purpose:

- prove the platform can actually send what it promises to send

Validate:

- manual communication send
- password reset email
- invite email
- renewal reminder
- unhealthy-system alert

Check:

- correct recipients
- correct links
- template rendering
- failure visibility if send fails

Expected result:

- outbound mail is reliable and diagnosable

### Scenario 27. Public onboarding/webhook endpoints reject bad requests safely

Purpose:

- prove public-facing ingress is controlled

Validate:

- valid signed webhook request
- invalid signature
- malformed payload
- duplicate event
- disabled endpoint/config scenario

Expected result:

- only valid requests are accepted
- bad requests fail safely and visibly

## Section 8. Portal and admin backend behavior under direct access attempts

### Scenario 28. Direct URL access cannot bypass navigation restrictions

Purpose:

- prove server-side authorization is real

Validate:

- direct navigation to restricted pages
- direct navigation to another tenant’s records
- direct action URLs after session expiry

Expected result:

- the backend rejects unauthorized access regardless of UI visibility

### Scenario 28A. Download entitlement gating is enforced server-side

Purpose:

- prove customers cannot access installers just because they know the URL

Validate:

- direct URL access without active trial
- direct URL access without active license/subscription
- active trial access
- active paid entitlement access

Expected result:

- downloads are hidden and blocked until the customer is genuinely entitled

### Scenario 29. Stale browser actions fail safely after auth/session state changes

Purpose:

- prove old tabs/forms do not perform unintended actions

Validate:

- stale tab after logout
- stale tab after sign-out-all-sessions
- stale sensitive-action page after unlock expiry

Expected result:

- stale pages cannot silently commit protected actions

## Section 9. Windows server and service behavior

### Scenario 30. Service install, restart, and recovery policy behave correctly

Purpose:

- prove service-level operation is production-capable

Validate:

- service installation
- startup
- stop
- restart
- failure recovery
- behavior when launched as UI vs service

Expected result:

- the server behaves correctly as a real Windows service

### Scenario 31. Firewall and bind behavior match expected deployment shape

Purpose:

- prove network/runtime settings do what support expects

Validate:

- fresh install bind default
- all-interfaces binding
- loopback-only binding
- detected LAN IP handling
- firewall repair path

Expected result:

- networking behavior matches the chosen deployment mode

### Scenario 32. Logging and audit behavior remains useful under error conditions

Purpose:

- prove backend diagnostics remain supportable

Validate:

- startup/shutdown logging
- client connect/disconnect
- malformed input
- licensing failures
- claim/check-in failures
- admin actions
- log rotation behavior

Expected result:

- operators can reconstruct what happened without guesswork

## Section 10. Windows client technical/runtime behavior

### Scenario 33. MSI deployment properties land correctly in runtime configuration

Purpose:

- prove deployment automation is trustworthy

Validate:

- default install
- silent install with overrides
- webhook configuration
- terminal-services install mode
- startup/tray settings

Expected result:

- the installed client reflects the intended deployment configuration

### Scenario 34. Client reconnect, identity refresh, and policy reporting remain consistent

Purpose:

- prove runtime state stays coherent from a technical support perspective

Validate:

- reconnect after server restart
- rename/save refresh
- policy status reporting
- mismatch detection
- pending sync state

Expected result:

- the server monitor shows the real current technical state

### Scenario 35. Client/server incident path and external notifications stay decoupled

Purpose:

- prove incident traffic is not blocked by side integrations

Validate:

- alert flow with healthy providers
- alert flow with failing providers
- response/reset behavior under provider failure

Expected result:

- live incident workflow still succeeds even when integrations are degraded

## Section 11. Topology, environment, and deployment variations

### Scenario 36. Standard local clinic/site deployment behaves correctly

Purpose:

- prove the main supported topology is solid

Validate:

- local clients
- local Windows server
- cloud-linked licensing/admin

Expected result:

- standard site deployment works cleanly end to end

### Scenario 37. Terminal Services / RDS behavior matches the current support position

Purpose:

- prove the client’s technical design for shared-user environments actually holds up

Validate:

- multiple users
- config-root behavior
- first-run behavior
- naming behavior
- alert usability in shared-user conditions

Expected result:

- the product behaves in line with its current support statement for RDS-style use

### Scenario 38. Multi-site control-plane behavior works even if subgroup routing is limited

Purpose:

- prove the commercial/admin model for multi-site customers is sound

Validate:

- one customer
- multiple systems/sites
- per-system claim/licensing state
- multi-site commercial records

Expected result:

- multi-site customer representation is operationally sound

## Section 12. Failure, resilience, and recovery scenarios

### Scenario 39. Cloud outage does not stop a currently valid local server from operating

Purpose:

- prove local runtime continuity claims

Validate:

- valid local license already present
- cloud unavailable
- local incident workflow continues
- cloud admin/lifecycle actions unavailable as expected

Expected result:

- local runtime continues while cloud-dependent admin/lifecycle work pauses

### Scenario 40. Broken or partial integration state fails visibly and recoverably

Purpose:

- prove the system degrades safely

Validate:

- broken SMTP
- broken Xero credentials
- bad webhook secret
- wrong platform base URL
- missing trusted-key bundle during rotation

Expected result:

- failures are visible, understandable, and recoverable

### Scenario 41. Duplicate or repeated operations do not create corrupt business state

Purpose:

- prove retry/replay behavior is safe

Validate:

- repeated claim attempts
- repeated payment sync/apply
- repeated installer publish flow
- repeated user invite actions where applicable
- repeated manual refresh operations

Expected result:

- repeated actions do not create duplicated or contradictory state

## Section 13. Mac-client technical smoke coverage

### Scenario 42. Mac client basic technical runtime validation

Purpose:

- prove the Mac client meets a minimum technical bar when in scope

Validate:

- app startup
- connect/disconnect
- message parsing
- settings persistence
- login-item behavior
- log collection

Expected result:

- the Mac client behaves consistently enough to support its intended scope

## Section 14. Technical release-candidate minimum pack

Before calling a build technically trustworthy, the team should have at least one passing run covering:

- public signup bootstrap and duplicate-match handling
- product-configured self-service trial duration
- current legal terms enforcement and acceptance history
- staff auth and MFA
- customer auth and MFA
- session timeout and sign-out-all-sessions
- sensitive-action unlock and expiry
- staff role boundaries
- customer tenant isolation
- secret masking/handling
- claim/bootstrap
- linked check-in
- renewal replacement of signed license
- invalid/wrong-fingerprint license rejection
- replacement / DR cutover
- trusted-key rotation
- quote/payment/subscription integrity
- Stripe customer linkage and Stripe-paid state sync
- Xero contact and invoice sync behavior
- download entitlement gating
- email and link generation
- service install/start/recovery
- client reconnect and policy-state reporting
- local runtime continuity during cloud outage

## Final note

This guide should be treated as the technical trust checklist for the platform.

The user-focused guide proves people can use the product.

This guide proves the backend and platform deserve that trust.
