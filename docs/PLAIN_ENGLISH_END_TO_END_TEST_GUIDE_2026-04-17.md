# Plain English End-to-End Test Guide

Last updated: `2026-04-19`

This guide is written for staff and testers who need to validate the Duress product without reading code first.

It is deliberately plain English.

It focuses on business scenarios, customer journeys, operational workflows, and cross-product outcomes rather than only technical test cases.

## What this guide covers

This guide covers the current Duress v3 product shape across:

- Duress Cloud
- Windows Server
- Windows Client
- customer portal
- billing and licensing workflows
- installer publishing and download flows
- migrations and replacement scenarios
- support and operational edge cases
- known Mac-client smoke coverage expectations

It is intended to answer:

- what should we test
- why it matters
- what a pass looks like

For the full quality model, including how positive and negative regression should be balanced across unit, integration, and release-gate coverage, also use:

- [QUALITY_AND_REGRESSION_STRATEGY.md](/D:/Duress/DuressCloud/docs/QUALITY_AND_REGRESSION_STRATEGY.md)

## Key terms testers should use correctly

These words are related, but they do not mean the same thing:

- `Product`: the commercial plan or offer being sold
- `Subscription`: the ongoing commercial agreement that keeps the customer current
- `License`: the technical entitlement the customer server actually uses

Simple rule for testers:

- test `product` when you are checking catalog, pricing, quote, purchase, market, country, currency, or billing-plan behavior
- test `subscription` when you are checking active paid state, renewal, cancellation, grace, grandfathering, or monthly-vs-annual commercial commitments
- test `license` when you are checking claim, entitlement, feature enablement, signed XML, expiry, activation, block/revoke, or server runtime behavior

Normal lifecycle:

1. customer chooses a product
2. that becomes a quote or payment
3. payment activates or renews a subscription
4. the active state is translated into a technical license on the server

When logging defects, testers should say clearly which layer failed:

- product issue
- subscription issue
- license issue
- or a handoff issue between them

## How to use this guide

Use the guide in three layers:

1. run the business-critical scenarios first
2. run the role-based and edge-case scenarios next
3. run the environment, migration, and support scenarios after that

When recording evidence, always capture:

- date
- environment used
- tester name
- customer/system/test account used
- result
- screenshots or logs if something is unclear

## Suggested status labels

Use these labels when tracking execution:

- `Pass`
- `Pass with note`
- `Fail`
- `Blocked`
- `Not yet tested`

## Positive and negative test expectation

This guide is not only for happy-path checking.

For every major customer or staff workflow, testers should check both:

- the intended success path
- the refusal or protection path

Examples:

- signup should work for a brand-new customer, but duplicate users should be redirected to recovery
- trial and purchase should proceed when the current legal terms are accepted, but should stay blocked when they are not
- a valid payment should unlock the next step, but an unpaid or stale payment should not
- a migration should preserve or reprice terms only when the selected migration rule says so

## Test environment checklist

Before starting, confirm which environment you are using:

- local/dev cloud
- live-style cloud environment
- local Windows server install
- local Windows client install
- terminal-services / RDS style Windows client install
- test SMTP / webhook accounts
- test Stripe/Xero setup if the scenario needs them

Also confirm:

- which installer versions are being tested
- which cloud base URLs are active
- which customer records and portal users are safe to use for testing

## Priority order

If time is tight, test in this order:

1. new customer signup-to-terms-to-trial-or-purchase flow
2. existing customer renewal and keep-running flow
3. Stripe payment and fulfillment flow
4. replacement / DR and trusted-key rotation flow
5. client/server incident workflow
6. portal self-service workflows
7. role, security, and edge-case workflows

## Section 1. New customer acquisition and onboarding

### Scenario 1. New customer discovers Duress for the first time

Purpose:

- prove a brand-new prospect can become a valid Duress customer without staff needing undocumented manual fixes

Steps:

1. start from the public-facing website or intake path
2. submit the new-customer onboarding or trial request
3. confirm the cloud side creates or queues the right onboarding record
4. review the onboarding item in the staff/admin area
5. approve it as a legitimate new customer
6. create or confirm the customer record
7. create or confirm the first system record
8. provide the claim token and install/download guidance

Expected result:

- the customer appears once, not as duplicate tenants
- staff can clearly see whether the onboarding was automatic or needs review
- the customer gets a usable next step instead of an ambiguous dead end

### Scenario 1A. Brand-new customer uses the public signup page

Purpose:

- prove a new customer can self-create their organisation and first portal user without staff involvement

Steps:

1. open the public signup page
2. enter organisation, first-user, and billing details
3. use the address lookup path first
4. if needed, switch to manual address entry
5. complete signup with a clean new email/domain
6. confirm the success message says to check email
7. use the emailed invite/setup link
8. set password and complete first portal login

Expected result:

- the customer record is created once
- the first portal user is linked to the right customer
- the signup flow does not dump the user straight back to login without explanation
- the customer can continue from the emailed invite/setup path
- the address lookup path or manual address path both result in a valid saved address

### Scenario 1B. Existing-company and existing-user matches are handled safely during signup

Purpose:

- prove the self-service signup page prevents duplicate tenants and duplicate users

Steps:

1. try signup with an email address that already exists as a portal user
2. confirm the flow redirects the person to sign-in or reset-password rather than creating a duplicate user
3. try signup with a domain or ABN that matches an existing customer
4. confirm the flow shows the masked-email hint and review path
5. submit the review path if the user does not recognise the hinted email

Expected result:

- existing users are sent to recovery, not recreated
- likely-existing companies are not duplicated silently
- the review path is available when the customer genuinely needs help

### Scenario 1C. Signup negative-path and usability protections

Purpose:

- prove the signup flow rejects bad or risky inputs clearly without leaving the customer stranded

Steps:

1. try signup with a password containing unsupported characters during the setup stage
2. confirm the user gets a clear error and can correct it
3. try the address lookup path and then switch to manual entry
4. confirm the form still submits successfully
5. confirm downloads are still locked after signup until trial or paid entitlement is approved

Expected result:

- password errors are clear
- address entry does not trap the user
- signup completion does not unlock installer access too early

### Scenario 2. Ambiguous new-customer handoff is reviewed safely

Purpose:

- prove duplicate-customer risk is handled safely

Steps:

1. submit onboarding details that partially match an existing customer
2. confirm the request lands in `Onboarding Reviews`
3. verify staff can choose:
   - link to an existing customer
   - create a new customer
4. complete the resolution

Expected result:

- no silent wrong-tenant merge happens
- the decision is visible to staff
- the final customer record is correct

### Scenario 3. New customer starts as a trial

Purpose:

- prove the standard trial path works end to end

Steps:

1. create or receive a trial request
2. approve the trial in `Trial Requests`
3. confirm the trial dates update correctly
4. create or confirm the trial system
5. generate a claim token
6. direct the customer to portal downloads
7. claim the server
8. confirm the claimed server receives trial licensing correctly

Expected result:

- the trial is time-bounded and visible in cloud
- the trial is tied to the real claimed server
- the customer can install and operate under the trial state

Important note:

- the self-service trial length now comes from the configured product/catalog setup, not a hard-coded number
- current public base plans should be checked against the intended website offer before release

### Scenario 4. New customer goes straight to paid

Purpose:

- prove staff can onboard a customer without using the trial path

Steps:

1. create the customer
2. create the system
3. create the commercial record:
   - quote, payment request, or direct license path as appropriate
4. confirm payment or approved commercial state
5. claim the server
6. issue the production license
7. confirm the customer can download the correct installers

Expected result:

- the customer skips trial cleanly
- the paid state is visible in subscriptions/licensing
- the production license is active on the correct server

### Scenario 4B. Product, subscription, and license remain distinct after purchase

Purpose:

- prove the system keeps the commercial and technical records aligned without treating them as the same thing

Steps:

1. create or buy a product
2. complete payment
3. confirm a subscription or equivalent active commercial state is visible
4. confirm the target server receives the correct technical license
5. compare the product name, subscription plan details, and license details

Expected result:

- the sold product is visible commercially
- the active subscription reflects the ongoing agreement
- the issued license reflects the technical entitlement
- staff and customers are not forced to guess which record means what

### Scenario 4A. Customer chooses between trial and purchase from portal home

Purpose:

- prove a newly created customer admin can clearly see both onboarding paths

Steps:

1. log in as a brand-new customer admin
2. land on the portal home
3. confirm the dashboard clearly offers:
   - `Start free trial`
   - `Buy license now`
4. confirm the legal-acceptance summary is visible on the home page without being a separate menu item

Expected result:

- the starting choices are obvious
- legal status is visible from the main portal home
- the portal does not force the customer to guess where onboarding starts

## Section 2. Existing customer migration and upgrade scenarios

### Scenario 5. Existing customer moves from older Duress into the new platform

Purpose:

- prove an existing customer can be brought into the cloud-managed v3 model

Steps:

1. create or clean up the customer record in cloud

### Scenario 5A. Customer can move from one product level to another without losing control

Purpose:

- prove customers can move to a new license level or retired replacement product cleanly

Steps:

1. start with a customer on an older or smaller product
2. create the migration, upgrade, or replacement commercial path
3. confirm the target product is the new commercial state
4. confirm the old and new pricing/subscription state is still traceable
5. confirm the resulting technical license reflects the new entitlement

Expected result:

- product migration is visible commercially
- the customer does not lose license continuity
- support can still explain what changed and why
2. add the current site/server as a system
3. create or confirm the right subscription/licensing state
4. issue a claim token for the real server
5. update the server to the v3-capable build
6. configure cloud claim/check-in settings
7. claim the system
8. confirm the server now checks in to cloud
9. confirm the customer retains service continuity

Expected result:

- the old customer becomes a managed v3 customer
- licensing is bound to the real upgraded server
- the customer does not get stranded between old and new paths

### Scenario 6. Existing customer renews without reinstalling everything

Purpose:

- prove renewal is smooth for a linked production customer

Steps:

1. start with a linked customer/server with an existing signed license
2. renew in cloud
3. wait for or trigger cloud check-in
4. confirm the server receives the renewed signed license
5. confirm the client/server service remains operational

Expected result:

- the renewed license replaces the old one cleanly
- no manual import is required in the standard linked path
- the server keeps running with the new entitlement

### Scenario 7. Existing customer adds another site or server

Purpose:

- prove expansion within one customer is handled correctly

Steps:

1. create or review the lifecycle request for another site/server
2. approve it
3. create the new system
4. issue the new claim token
5. claim the second server
6. verify the right trial or paid state is applied to that second system

Expected result:

- the second system is under the same customer where appropriate
- licensing/subscription state reflects the expansion correctly
- staff can distinguish systems clearly

## Section 3. Trial extension and lifecycle decision scenarios

### Scenario 8. Customer had a pre-existing trial and needs an extension

Purpose:

- prove trial extension is controlled, auditable, and customer-visible

Steps:

1. start with a customer whose trial is near expiry or expired
2. request or receive the extension request
3. approve the trial extension
4. if needed, unlock sensitive actions with 2FA first
5. record the reason
6. confirm the new trial end date
7. confirm the customer/server state reflects the extension

Expected result:

- the extension is recorded with who, why, and how many days
- the customer can continue operating for the approved period
- the extension does not silently create a permanent paid state

### Scenario 9. Trial is expiring while payment is already underway

Purpose:

- prove staff can keep a good-faith customer working while billing completes

Steps:

1. create or identify an in-flight payment
2. extend the trial with a documented reason
3. confirm the operational state remains valid
4. later complete payment and conversion to paid

Expected result:

- the customer does not fall into unnecessary downtime
- the commercial and operational trail is clear

### Scenario 10. Trial converts to paid

Purpose:

- prove the normal conversion workflow works

Steps:

1. receive a conversion-to-paid request
2. approve it
3. generate the payment request or confirm the commercial state
4. complete payment
5. confirm the subscription becomes active
6. confirm the production license is issued for the claimed system

Expected result:

- the customer leaves trial cleanly
- production entitlement is visible and active
- audit and billing history remain understandable

## Section 4. Customer portal scenarios

### Scenario 11. Customer admin can log in and use the portal

Purpose:

- prove the portal is usable for a real customer admin

Steps:

1. create or invite a customer admin
2. complete invite or password setup
3. sign in through the customer portal
4. complete MFA setup if required
5. land on the dashboard

Expected result:

- the customer lands inside the correct tenant only
- portal login and MFA work
- no admin-site-only pages leak into the customer journey

### Scenario 11A. Customer sees legal acceptance status from the main portal home

Purpose:

- prove customers can see whether current product and trial terms are already accepted

Steps:

1. sign in as a customer admin
2. open portal home
3. confirm the home page shows the current status for:
   - product/software use terms
   - trial terms
4. follow the action buttons back into the relevant purchase or trial path

Expected result:

- legal status is visible from the main dashboard
- no extra top-level menu item is needed
- the customer can review or re-accept current versions when required

### Scenario 12. Customer password reset works from email link

Purpose:

- prove real email-driven self-service password reset works

Steps:

1. request password reset
2. receive the email
3. open the link from the email
4. reset the password
5. sign in with the new password

Expected result:

- the email link works even after email-client wrapping
- the user can complete reset without staff intervention

### Scenario 13. Customer sees downloads, licenses, quotes, payments, and subscriptions

Purpose:

- prove the portal gives the customer the expected self-service visibility

Steps:

1. sign in as a portal customer user
2. open:
   - Downloads
   - Licenses
   - Payments
   - Quotes
   - Subscriptions
3. verify each area shows only tenant-appropriate data

Expected result:

- the customer can find the latest approved installers
- license details/download are visible where supported
- quote/payment/subscription detail matches staff-side records

Important note:

- downloads must stay hidden until the customer has an approved or active trial, an active paid entitlement, or an active subscription
- customers must not see downloads too early just because they have signed in

### Scenario 14. Customer admin can invite and manage their own users

Purpose:

- prove tenant self-management works safely

Steps:

1. sign in as customer admin
2. invite a new portal user
3. activate/deactivate the user
4. reset MFA for the user
5. verify role boundaries

Expected result:

- the customer admin can manage tenant users
- users remain confined to their own tenant
- changes are reflected reliably

### Scenario 15. Customer requests trial extension, renewal, or another site from the portal

Purpose:

- prove lifecycle requests start correctly from self-service

Steps:

1. sign in as customer admin
2. submit:
   - trial extension request
   - renewal request
   - additional site/server request
3. verify the request appears in the staff/admin area

Expected result:

- portal requests become visible operational work items
- staff can act on them without re-keying the request manually

### Scenario 15A. Customer must accept the current legal terms before starting trial or purchase

Purpose:

- prove legal acceptance is properly enforced and recorded

Steps:

1. sign in as a customer admin who has not accepted the current versions
2. open the trial flow
3. confirm trial start is blocked until the current product and trial terms are accepted
4. accept them and confirm an email copy is sent
5. open the purchase flow
6. confirm purchase is blocked until the required current product terms are accepted
7. accept them and confirm an email copy is sent

Expected result:

- the customer cannot begin trial or self-service purchase without current legal acceptance
- acceptance is versioned
- an email copy of what was accepted is sent

## Section 5. Staff user, security, and governance scenarios

### Scenario 16. Staff user creation and first login

Purpose:

- prove internal administration is safe and usable

Steps:

1. create each key staff role:
   - platform admin
   - licensing admin
   - support admin
   - billing admin
   - read-only admin
2. send or hand off login
3. complete first login and MFA

Expected result:

- each staff role can sign in
- role-specific access boundaries make sense

### Scenario 17. Sensitive actions require reauthentication

Purpose:

- prove 2FA/sensitive-action unlock controls are real

Steps:

1. sign in as staff
2. attempt a sensitive action such as:
   - mark paid
   - Xero apply/sync path
   - trial extension
   - signing-key state change
   - server transfer preparation
3. complete explicit unlock
4. finish the action

Expected result:

- sensitive actions are gated
- the unlock window behaves predictably

### Scenario 18. Sign out all sessions and lockout/session policies

Purpose:

- prove platform security controls are working

Steps:

1. sign in on more than one browser/session
2. trigger sign-out-all-sessions
3. verify session invalidation
4. exercise lockout/session timeout policies carefully on test accounts

Expected result:

- sessions end when expected
- lockout/session controls do not behave dangerously or silently

### Scenario 19. Audit visibility for important admin actions

Purpose:

- prove security-sensitive work is auditable

Steps:

1. perform key actions:
   - create customer
   - approve trial
   - issue/renew/block/revoke/reactivate license
   - create payment
   - mark paid
   - change signing-key state
2. review audit

Expected result:

- the audit trail is understandable and complete enough for support and investigation

## Section 6. Product, pricing, quote, and payment scenarios

### Scenario 20. Staff can create and manage products and pricing overrides

Purpose:

- prove the commercial catalog is usable

Steps:

1. create or edit:
   - public plan
   - add-on
   - enterprise product
2. add customer-specific negotiated pricing override
3. create a quote or payment from that product

Expected result:

- pricing snapshots are carried through correctly
- overrides apply only where intended

### Scenario 21. Quote lifecycle from draft to conversion

Purpose:

- prove quote handling works as a business workflow

Steps:

1. create a draft quote
2. send it
3. mark or drive acceptance
4. convert it to a payment request

Expected result:

- quote states progress clearly
- converted payment inherits the right commercial details

### Scenario 22. Payment request through payment page

Purpose:

- prove customer-facing payment handoff works

Steps:

1. create a payment request
2. open the public payment page or link
3. verify the customer-facing details are correct
4. complete the payment path as far as the environment allows

Expected result:

- the payment page is correct and understandable
- the payment links point to the right environment/base URL

### Scenario 22A. Stripe-first payment flow updates back into the portal cleanly

Purpose:

- prove the customer can pay via Stripe and then see the correct paid state, receipt detail, and next steps in the portal

Steps:

1. create a self-service purchase
2. pay it in Stripe
3. return to the portal payment page
4. refresh payment status if needed in the dev/test environment
5. confirm the payment updates from pending/open to paid
6. confirm receipt or payment identifying details are shown
7. confirm the customer can download the receipt where available
8. confirm onboarding/download next steps are visible after payment

Expected result:

- the customer-facing payment state matches Stripe
- the payment does not remain confusingly open after success
- the portal shows enough identifying information for support and customer reference

### Scenario 22B. Billing identity is correct in Stripe and Xero

Purpose:

- prove the purchase path uses the correct customer billing entity and email, not stray staff/test contact details

Steps:

1. create a payment from a customer with clear billing details
2. inspect the Stripe customer/payment details
3. inspect the Xero contact and invoice details
4. confirm the billing entity, billing email, address, and cross-system identifiers match the Duress customer profile

Expected result:

- Stripe uses the customer billing identity
- Xero uses the correct billing identity
- cross-system linkage is traceable and supportable

### Scenario 23. Xero billing flow

Purpose:

- prove the accounting flow works without confusing staff

Steps:

1. preview Xero contact action
2. create or match the Xero contact
3. confirm Duress-created contacts are configured so Xero reminder emails are not used where intended
4. for Stripe-first flow, confirm Xero invoice/accounting records are created after payment
5. for EFT/manual invoice flow, confirm the Xero-routed path still works deliberately
6. update and sync invoice status
7. confirm paid/accounting state flows back into Duress where appropriate
8. confirm fulfillment behavior

Expected result:

- no duplicate or wrong-contact behavior
- the queue/status in Duress reflects where the invoice really is
- Stripe-first card checkout does not depend on Xero timing for customer activation

### Scenario 24. Payment operational queue scenarios

Purpose:

- prove staff can work the queue effectively

Test each queue state:

- awaiting Xero payment sync
- awaiting automation paid apply
- paid, awaiting system
- paid, ready for fulfillment

Expected result:

- each queue state is understandable
- staff can tell what action is next

## Section 7. Licensing scenarios

### Scenario 25. Manual signed license export and import

Purpose:

- prove offline/manual licensing still works when needed

Steps:

1. issue a license in cloud
2. export/download the signed file
3. import it into the server
4. confirm the server accepts it

Expected result:

- manual licensing works for support or exception handling

### Scenario 26. License renewal

Purpose:

- prove a normal renewal path succeeds

Steps:

1. renew the license in cloud
2. confirm the renewed period/state
3. confirm server refresh/import path works

Expected result:

- renewed license becomes active without ambiguity

### Scenario 27. License block, reactivate, and revoke

Purpose:

- prove enforcement and support messaging are correct

Steps:

1. block a license
2. confirm server-side/customer-visible outcome
3. reactivate it
4. confirm recovery
5. revoke a license and confirm the old license should no longer remain valid

Expected result:

- blocked/revoked states are enforced
- support messaging is clear

### Scenario 28. Wrong server fingerprint / moved server

Purpose:

- prove the product handles server replacement/mis-binding clearly

Steps:

1. claim or license one server
2. move to a different machine or simulate replacement
3. confirm mismatch handling

Expected result:

- the state is understandable to staff and support
- the old license does not silently validate on the wrong server

## Section 8. Server claim, check-in, replacement, and DR scenarios

### Scenario 29. First claim/bootstrap

Purpose:

- prove first-time linking works

Steps:

1. create a system
2. generate claim token
3. enter cloud claim settings on the server
4. claim now
5. confirm cloud and local server both reflect the claimed state

Expected result:

- the right system links to the right server
- the server receives valid initial licensing

### Scenario 29A. Legacy registration does not poison later cloud claim

Purpose:

- prove a mistaken legacy/manual registration does not permanently break later claim-token use

Steps:

1. register a test server with the legacy/manual path
2. then attempt the normal cloud claim-token path
3. confirm the signed/cloud-managed license becomes the active local state
4. confirm stale legacy license files do not keep the server in a broken half-state

Expected result:

- claim-token onboarding can recover cleanly even after legacy registration mistakes
- the server ends in a valid current signed-license state

### Scenario 30. Ongoing cloud check-in

Purpose:

- prove linked cloud licensing stays healthy

Steps:

1. start with a claimed server
2. trigger or wait for check-in
3. review health/IP telemetry in cloud

Expected result:

- the cloud shows current server identity and health
- current licensing state is visible

### Scenario 31. Server replacement / DR cutover

Purpose:

- prove planned replacement is safe

Steps:

1. prepare replacement or DR in cloud
2. issue the new claim token
3. claim the new server
4. complete cutover
5. retire previous server

Expected result:

- the replacement process is controlled and traceable
- the previous server does not remain silently trusted

### Scenario 32. Trusted signing-key rotation

Purpose:

- prove emergency or planned key rotation works

Steps:

1. create/activate replacement signing key in cloud
2. export `TrustedLicenseKeys.xml`
3. deploy it to the server
4. refresh/reissue licensing
5. confirm validation with the new key

Expected result:

- rotated trust works only when the trusted bundle is present
- the transition is understandable to support

## Section 9. Installer and release distribution scenarios

### Scenario 33. Staff upload and publish installers

Purpose:

- prove the installer publishing model works

Steps:

1. upload new server package
2. upload new client package
3. publish them
4. confirm prior published package archives automatically for the same slot

Expected result:

- one clear current package per type/scope is visible

### Scenario 33A. Terminal Services client install option remains visible and documented

Purpose:

- prove the TS/RDS client path remains available to staff and customers where intended

Steps:

1. review installers/support guidance
2. confirm the terminal-services guide is still visible where expected
3. confirm the MSI/command guidance includes the terminal-services install path

Expected result:

- the TS client path is not lost from the release
- the install/support guidance matches the current MSI support

### Scenario 34. Customer sees the correct downloads

Purpose:

- prove customers get the right package

Steps:

1. sign in as portal customer
2. open Downloads
3. verify visibility rules for:
   - all-customer package
   - hidden package
   - customer-specific package

Expected result:

- customers only see what they should see

## Section 10. Windows server operational scenarios

### Scenario 35. Windows service install and startup

Purpose:

- prove the server runs correctly as a service

Steps:

1. install the server package
2. confirm the service exists
3. start it
4. stop it
5. restart it

Expected result:

- the service behaves like a service, not only like a desktop app

### Scenario 36. Missing-service guidance and admin-rights guidance

Purpose:

- prove operator guidance is clear

Steps:

1. open the manager without the service installed
2. open it without admin rights where relevant

Expected result:

- the operator gets useful guidance instead of silent failure

### Scenario 37. Firewall and recovery behavior

Purpose:

- prove the server’s operational hardening works

Steps:

1. install/start the server
2. verify firewall rule behavior
3. simulate service crash/restart where safe

Expected result:

- the server recovers and remains reachable as designed

## Section 11. Incident workflow and live alerting scenarios

### Scenario 38. Basic alert-response-reset flow

Purpose:

- prove the core real-time product still works

Steps:

1. connect two clients to the server
2. send alert from client A
3. verify client B receives it
4. send response from client B
5. verify client A receives it
6. send reset/clear

Expected result:

- alert, response, and clear/reset all work cleanly

### Scenario 39. Legacy wire compatibility

Purpose:

- prove older protocol behavior still coexists

Steps:

1. run current client/server
2. run compatibility path for legacy message handling

Expected result:

- legacy `Alert`, ` Resp`, and ` Ackn` compatibility remains intact

### Scenario 40. Notification providers do not block incident workflow

Purpose:

- prove outbound notifications are parallel helpers, not critical-path blockers

Steps:

1. configure SMTP and one or more webhook providers
2. trigger an incident
3. confirm:
   - client-to-client routing works
   - email/webhooks are sent

Expected result:

- the incident still flows even if a provider misbehaves

## Section 12. Windows client scenarios

### Scenario 41. Fresh workstation install

Purpose:

- prove the default workstation install is usable

Steps:

1. install the MSI with defaults
2. launch the client
3. confirm first-run settings and connection behavior

Expected result:

- the client can be configured and connected

### Scenario 42. Silent install with MSI properties

Purpose:

- prove field deployment is realistic

Steps:

1. install silently with seeded properties
2. confirm the installed client picked up the expected values

Expected result:

- MSI deployment settings land correctly

### Scenario 43. Terminal-services / RDS style install

Purpose:

- prove per-user/shared configuration behavior works

Steps:

1. install in terminal mode
2. log in as first user
3. log in as second user
4. verify each user gets expected first-run behavior and config isolation/shared seeding

Expected result:

- terminal-friendly behavior works as documented

### Scenario 44. Tray, topmost, and runtime behavior

Purpose:

- prove core client usability behavior

Steps:

1. connect client
2. trigger alert popup
3. confirm always-on-top behavior
4. verify tray/minimise behavior
5. verify disconnected-state tooltip behavior

Expected result:

- the current UI/runtime promises are met

### Scenario 45. Reconnect after server restart

Purpose:

- prove the current reconnect fix works

Steps:

1. connect the client
2. restart the server/service
3. reconnect from client

Expected result:

- the first reconnect attempt succeeds cleanly

### Scenario 46. Client identity rename refresh

Purpose:

- prove renamed clients stay coherent in server monitoring

Steps:

1. rename the client
2. save settings
3. confirm the server monitor refreshes the name for the same installation

Expected result:

- support sees the updated name without duplicated/ghost identity confusion

### Scenario 47. Client policy provisioning from scratch

Purpose:

- prove the managed policy path works cleanly for a new rollout

Steps:

1. configure policy in the server `Client Policy` tab
2. export provisioning bundle
3. install the client using the helper
4. connect the client
5. confirm policy request/apply succeeds

Expected result:

- the client is policy-managed from first connect

### Scenario 48. Policy state mismatch visibility

Purpose:

- prove support can see policy drift

Steps:

1. connect a policy-capable client
2. cause or simulate a mismatch state
3. review the server monitor

Expected result:

- monitor shows `Pending Sync`, `Applied`, `Mismatch`, or error states clearly

## Section 13. Support and exception-handling scenarios

### Scenario 49. Customer uses manual signed license because cloud link is not available

Purpose:

- prove support has a fallback path

Steps:

1. issue/export signed license
2. import manually to server
3. confirm operation continues

Expected result:

- support can recover the customer without undocumented tricks

### Scenario 50. Customer contacts support after block or invalid state

Purpose:

- prove the product gives enough information for triage

Steps:

1. block or invalidate a test license
2. observe customer-visible/support-visible messaging

Expected result:

- the customer is directed to support cleanly
- staff can quickly tell what state the customer is in

### Scenario 51. Customer had wrong system assignment after payment

Purpose:

- prove operational queue and delayed fulfillment work

Steps:

1. create paid state without a correct system assignment
2. leave it as `Paid, awaiting system`
3. later assign the correct system
4. complete fulfillment

Expected result:

- no wrong system receives the entitlement
- later assignment works cleanly

## Section 14. Communication and automation scenarios

### Scenario 52. Manual communications

Purpose:

- prove staff communications are tracked

Steps:

1. send manual communication in each main category:
   - renewal
   - alert
   - offer
   - general update
2. review sent/failure history

Expected result:

- communication history is visible and accurate

### Scenario 53. Automated renewal and unhealthy-system alerts

Purpose:

- prove background automation behaves sensibly

Steps:

1. set up a renewable/test subscription near threshold
2. set up an unhealthy-system condition if environment allows
3. let automation run

Expected result:

- the right communications are produced
- staff can review what automation did

### Scenario 54. Scheduled Xero sync audit visibility

Purpose:

- prove scheduled billing automation is visible and reviewable

Steps:

1. enable scheduled Xero sync
2. let one or more sync windows complete
3. review audit/task visibility

Expected result:

- staff can tell what automation did and when

## Section 15. Topology and environment scenarios

### Scenario 55. Standard local clinic topology

Purpose:

- prove the strongest supported topology works cleanly

Steps:

1. deploy local server in clinic/site
2. connect clients on same network
3. link server to cloud

Expected result:

- this core topology works without special handling

### Scenario 56. Terminal services / RDS shared-user environment

Purpose:

- prove the current client design direction holds in a shared Windows environment

Steps:

1. install in terminal mode
2. test multiple users
3. confirm config behavior and operational experience

Expected result:

- the deployment behaves in line with the current support statement

### Scenario 57. Multi-site customer under one commercial account

Purpose:

- prove control-plane support for multi-site customers

Steps:

1. create one customer with multiple systems/sites
2. manage licensing/subscriptions across them

Expected result:

- multi-site commercial representation works

Important note:

- subgroup routing within shared infrastructure is still not first-class and should be tested carefully, not oversold

### Scenario 58. Cloud outage while local server remains licensed

Purpose:

- prove local runtime continuity claim

Steps:

1. start with a valid local signed license already installed
2. make cloud unavailable
3. continue local incident workflow testing

Expected result:

- local alerting continues while cloud admin/licensing refresh is unavailable

## Section 16. Mac-client scenarios

### Scenario 59. Basic Mac smoke pass

Purpose:

- prove the Mac client is at least minimally viable where in scope

Steps:

1. install/run the Mac client on real Apple hardware
2. verify startup
3. verify connect/disconnect
4. verify alert dialog flow
5. verify settings persistence
6. verify login-at-startup persistence

Expected result:

- the Mac client passes a basic smoke bar

Important note:

- the Mac client is less documented and should be treated as a narrower verification stream unless its release scope is elevated

## Section 17. Negative and failure-path scenarios

These should be run across the product, not treated as one separate corner.

Test at least:

- wrong password
- expired reset link
- wrong tenant/user attempting access
- blocked license
- revoked license
- claim with blank or invalid claim token
- payment in flight but no assigned system
- duplicate/ambiguous public onboarding match
- Xero contact mismatch
- server claimed against the wrong system
- missing service on Windows server
- server replaced without correct cutover flow
- policy-capable client not yet synced
- malformed client/server protocol message

Expected result:

- the state is understandable
- the error is safe
- support can recover without guesswork

## Section 18. Release-candidate full-pass checklist

Before calling a release slice ready for serious customer use, the team should have at least one passing run covering:

- public signup and first portal-user creation
- duplicate-company and duplicate-user signup handling
- portal legal-acceptance enforcement and email copy
- brand-new customer trial onboarding
- brand-new customer direct purchase onboarding
- trial extension
- conversion to paid
- existing customer renewal
- existing customer additional site/server
- linked cloud claim/bootstrap
- linked renewal refresh
- replacement / DR cutover
- trusted-key rotation
- installer publish and portal download
- payment request and accounting sync
- Stripe-first payment status, receipt visibility, and customer billing identity
- client/server incident workflow
- terminal-services client pass
- blocked/revoked/invalid licensing behavior
- key staff security and audit workflows

## Suggested ownership split for test execution

If multiple people are helping, split ownership like this:

- commercial and onboarding:
  - customers
  - quotes
  - payments
  - subscriptions
  - portal requests
- licensing and cloud lifecycle:
  - systems
  - claim/check-in
  - renewals
  - replacement
  - trusted-key rotation
- endpoint and runtime:
  - Windows server
  - Windows client
  - terminal services
  - Mac smoke if in scope
- governance and support:
  - staff roles
  - MFA and sensitive actions
  - audit
  - error recovery

## Final note

The most important thing is not merely to prove isolated features.

It is to prove that the real customer journeys work:

- a new customer can start
- an existing customer can migrate
- a trial customer can extend or convert
- a paid customer can renew
- a replaced server can recover safely
- staff can support the whole lifecycle without hidden manual steps
