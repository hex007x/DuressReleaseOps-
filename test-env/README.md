# Local Test Environment

This folder provides a contained local test harness for the latest `Duress2025` client.

## What it does

- builds a sandbox test client from `Duress2025/Duress`
- runs either a fake TCP server or the real `DuressServer2025` Windows service on `127.0.0.1:8001`
- stores all client config and logs under `test-env/sandbox/`
- disables startup-registry writes while testing
- lets you inject remote alert/response messages without a second machine

## Layout

- `build/` compiled test client output
- `sandbox/clients/client-a/user-data/` isolated config and logs for client A
- `sandbox/clients/client-b/user-data/` isolated config and logs for client B
- `sandbox/common-data/` isolated shared config
- `sandbox/runtime/server.log` fake server log
- `sandbox/runtime/server.log.1` to `.5` rotated server log backups when needed
- `server-build/` compiled real server output used for local service testing
- `sandbox/runtime/license-portal/` local hosted-licensing stub data and logs

## Quick start

From `c:\OLDD\Duress`:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\start-test-env.ps1
```

That will:

1. seed sandbox config
2. build the client
3. start the fake server
4. launch the client with sandbox-only paths

To start against the real Windows service:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\start-test-env.ps1 -ServerMode Real
```

To start two local clients:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\start-test-env.ps1 -TwoClients
powershell -ExecutionPolicy Bypass -File .\test-env\start-test-env.ps1 -ServerMode Real -TwoClients
```

To open live monitoring windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\monitor-test-env.ps1
```

To close any leftover visible Duress/MSI test windows:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\close-visible-test-windows.ps1
```

Visual-test rule:

- screenshot/demo/regression scripts should close every visible window they open before reporting completion
- use `close-visible-test-windows.ps1` as a final sweep if you ever want a manual cleanup pass

## Build requirement

The test client needs a modern C# compiler, typically one of:

- Visual Studio 2022
- Build Tools for Visual Studio 2022
- an `MSBuild` installation that includes Roslyn C# targets

The legacy `.NET Framework` compiler alone is not enough for the current `Duress2025` source because it uses newer C# syntax.

## Manual commands

Build the client:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\build-client.ps1
```

Prepare sandbox files:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\prepare-sandbox.ps1
```

Start the fake server:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\start-server.ps1
```

Build the real server:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\build-real-server.ps1
```

Prepare real server config and test license:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\prepare-real-server.ps1
```

Prepare local hosted-licensing stub data:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\prepare-license-portal.ps1
```

Install and start the real Windows service:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\start-real-server.ps1
```

Note: real-service mode requires an elevated PowerShell session because Windows service installation needs administrator rights.

Stop the real Windows service:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\stop-real-server.ps1
```

Start the local hosted-licensing stub:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\start-license-portal.ps1
```

Stop the local hosted-licensing stub:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\stop-license-portal.ps1
```

Uninstall the real Windows service and restore prior local config where possible:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\uninstall-real-server.ps1
```

Rebuild and restart the real Windows service after server code changes:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\redeploy-real-server.ps1
```

Point the real server at the local hosted-licensing stub:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\configure-real-server-license-portal.ps1
```

Switch the local hosted-licensing stub between current and renewed responses:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\set-license-portal-response.ps1 -Mode current
powershell -ExecutionPolicy Bypass -File .\test-env\set-license-portal-response.ps1 -Mode renewed
powershell -ExecutionPolicy Bypass -File .\test-env\set-license-portal-response.ps1 -Mode invalid
powershell -ExecutionPolicy Bypass -File .\test-env\set-license-portal-response.ps1 -Mode error
```

Start the fake server with an explicit log cap:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\start-server.ps1 -MaxBytes 10485760 -BackupCount 5
```

Override log size / backup retention for the current shell:

```powershell
$env:DURESS_SERVER_LOG_MAX_BYTES = 5242880
$env:DURESS_SERVER_LOG_BACKUP_COUNT = 3
powershell -ExecutionPolicy Bypass -File .\test-env\start-server.ps1
```

Launch the client into the sandbox:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\run-client.ps1
```

Launch a specific client sandbox:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\run-client.ps1 -ClientId client-a
powershell -ExecutionPolicy Bypass -File .\test-env\run-client.ps1 -ClientId client-b
```

Launch both local clients:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\run-two-clients.ps1
```

Exercise the full two-client flow automatically:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-two-client-flow.ps1
```

Exercise the real server protocol directly without UI automation:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-real-server-protocol.ps1
```

Run the full incident workflow suite against the real server:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-incident-suite.ps1
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-incident-suite.ps1 -IncludeNotifications
```

Run the licensing and entitlement suite snapshot against the real server:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-licensing-suite.ps1
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-licensing-suite.ps1 -IncludeProtocolSmoke
```

Run the focused Google Chat unit tests:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\run-googlechat-unit-test.ps1
```

Run the Windows client unit tests:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\run-client-unit-test.ps1
```

Run the fuller regression pack with screenshots and collected logs:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-full-regression-pack.ps1
```

That pack gathers:

- client unit tests
- server regression tests
- cloud unit/integration/publish smoke
- authenticated cloud staff and portal smoke with MFA completion plus portal installer download
- public customer signup, invite/password setup, MFA enrolment, legal acceptance, self-service trial unlock, download gating, and self-service purchase creation
- known-issue regression checks for previously fixed bugs
- commercial regressions for trial extension, payment activation, subscription lifecycle, and Xero automation
- MSI upgrade metadata checks across current and previous cloud-hosted client/server packages
- policy suite
- compatibility suite
- linked-cloud claim/check-in/replacement/key-rotation regressions when the real service is available
- visual client screenshots
- policy monitor screenshot

Run the focused customer-onboarding journey gate directly:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-customer-onboarding-regression-suite.ps1
```

That suite proves:

- public signup creates a fresh organisation and first portal admin
- invite-driven password setup and MFA enrolment complete
- downloads stay locked before entitlement
- trial terms acceptance unlocks a self-service trial and downloads
- purchase terms acceptance unlocks self-service purchase creation and a pending payment page

It writes a timestamped artifact folder under:

- `test-env\sandbox\full-regression\`

Verify desktop/shared and terminal/per-user installer writes:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\verify-client-config-modes.ps1
```

Verify uninstall leaves generated config intact in both desktop and terminal modes:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\verify-client-uninstall-config-preservation.ps1
```

Verify visible-mode runtime behavior:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\verify-windows-client-runtime.ps1
```

Run the compatibility suite for current-client and legacy-wire behavior:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-compatibility-suite.ps1
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-compatibility-suite.ps1 -IncludeRealService
```

Run the secure client-policy suite for signed policy apply, server-side status reporting, queued resend, offline unlock, and legacy coexistence:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-client-policy-suite.ps1
```

Start or stop the dedicated legacy-wire compatibility relay:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\start-legacy-wire-server.ps1
powershell -ExecutionPolicy Bypass -File .\test-env\stop-legacy-wire-server.ps1
```

Exercise real-service online license refresh through the local hosted-licensing stub:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-license-refresh.ps1
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-license-refresh.ps1 -UseRenewedLicense
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-cloud-license-scenarios.ps1
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-cloud-issued-license-refresh.ps1
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-server-cloud-claim.ps1 -CloudClaimUrl http://localhost:5186/api/systems/claim -ClaimToken <token>
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-server-cloud-checkin.ps1 -CloudCheckinUrl http://localhost:5186/api/licensing/checkin -SignedLicensePath <license.xml>
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-linked-cloud-claim.ps1 -ClaimToken <token>
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-linked-cloud-checkin.ps1
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-linked-cloud-replacement.ps1 -ReplacementClaimToken <token>
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-linked-cloud-trusted-key-rotation.ps1
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-linked-cloud-regression-suite.ps1
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-cloud-regression-suite.ps1
powershell -ExecutionPolicy Bypass -File .\test-env\exercise-known-issue-regression-suite.ps1
```

Note: `exercise-license-refresh.ps1` restarts the real Windows service, so it must be run from an elevated PowerShell session.
`exercise-cloud-issued-license-refresh.ps1` also backs up and restores the installed real-server license automatically.
`exercise-server-cloud-claim.ps1` uses an isolated `DURESS_SERVER_DATA_ROOT` sandbox so it does not touch the live `%ProgramData%` server config.

Reset everything to a clean baseline:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\reset-test-env.ps1
```

Show a quick text status summary:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\show-status.ps1
```

Inject a remote alert:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\inject-message.ps1
```

Inject a response:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\inject-message.ps1 -Command ' Resp' -Message 'Responder acknowledged'
```

Stop the fake server:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\stop-server.ps1
```

## Notes

- The test client uses these environment variables at runtime:
  - `DURESS_USER_DATA_ROOT`
  - `DURESS_COMMON_DATA_ROOT`
  - `DURESS_SKIP_STARTUP_REGISTRY=1`
- Those overrides were added so the app does not touch the real `%APPDATA%` or startup registry during local testing.
- The fake server is intentionally simple: it registers persistent clients, logs messages, and broadcasts injected or client-sent messages to other connected clients.
- The harness now supports two server modes:
  - `Fake`: local Python server with JSON rotating logs
  - `Real`: local install of the actual `DuressServer2025` Windows service
- For real-server verification, `exercise-real-server-protocol.ps1` is the most reliable smoke test because it bypasses desktop click automation and talks directly to the TCP service.
- `exercise-incident-suite.ps1` is the higher-level real-server workflow suite and is the preferred command when you want one result that covers routing plus notifications.
- `exercise-licensing-suite.ps1` is intentionally separate so licensing warnings and entitlement checks do not get mixed into every normal incident test.
- `exercise-linked-cloud-regression-suite.ps1` is the preferred release-gating proof for linked-cloud claim, replacement, renewal check-in, and trusted-key rotation.
- `exercise-cloud-regression-suite.ps1` is the preferred release-gating proof for Duress Cloud tests, publish output, and live site smoke.
- `exercise-known-issue-regression-suite.ps1` is the preferred release-gating proof for bugs we have already fixed and do not want to reintroduce.
- `exercise-client-policy-suite.ps1` is the preferred end-to-end verification for signed server-managed client policy, monitor-visible policy state, queued resend processing, and the break-glass offline unlock path.
- `run-googlechat-unit-test.ps1` is a local-only automated test for the Google Chat webhook code path. It validates payload formatting and HTTP dispatch against a stub listener, not your real Google Chat space.
- Client A and Client B are seeded with distinct names and messages so their logs are easy to tell apart.
- The server log is JSON-lines audit logging with rotation.
- Default maximum size is `10 MB` for `server.log`.
- When the current log would exceed the limit, it rotates to `server.log.1`, then `.2`, up to the configured backup count.
- If a single log event is larger than the configured limit, it is compacted so the active log file still stays under the cap.
- Real-server mode seeds a local localhost config and a permissive local test license using the current server's existing license rules.
- The local hosted-licensing stub serves the same `LicenseCheckResponse` XML contract the real server now expects for online refresh.
- The real server now supports Slack, Teams, and Google Chat webhook delivery from the server side.
- Production email helpers are available for:
  - `configure-o365-email.ps1`
  - `configure-gmail-email.ps1`
  - `configure-smtp-email.ps1`
- Notification retry/backoff/timeouts can be set with `configure-notification-policy.ps1`.
- Email and webhook delivery outcomes are now written to the real server audit log under `%ProgramData%\DuressAlert\Audit`.
- During migration, avoid enabling the same chat webhooks in both the client and server at once or you will get duplicate notifications.
- Real-server mode writes server config under `%ProgramData%\DuressAlert` because the current server code does not yet support sandbox path overrides.
- The real server now supports an override for its config/data root using `DURESS_SERVER_DATA_ROOT`, which is used by the Google Chat unit tests to avoid touching live `%ProgramData%` data.

## Monitor demo

To generate a mixed-state monitor demo with modern, legacy, connected, disconnected, and recent-notification activity:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\invoke-monitor-demo.ps1
```

To capture the server monitor UI directly into the demo artifacts folder:

```powershell
powershell -ExecutionPolicy Bypass -File .\test-env\capture-monitor-screenshot.ps1
```

Recent monitor demo artifacts are stored under:

- `test-env/sandbox/demo-shots/`

## What you will see visually

In the actual client windows:

- both clients appear as small circles on screen because `Pin` is seeded as `false`
- disconnected state is grey
- connected state is green
- alert state is red
- response state is orange
- incoming alerts also show popup notification windows near the bottom-right of the screen

In the monitor windows:

- `Duress Fake Server Log` shows registrations and raw protocol messages
- `Duress Client A Log` shows A's local actions and received events
- `Duress Client B Log` shows B's local actions and received events

Recommended workflow:

1. `reset-test-env.ps1`
2. `start-test-env.ps1 -TwoClients`
3. `monitor-test-env.ps1`
4. `exercise-two-client-flow.ps1`

That gives you both the real UI color changes and a clear textual trace of what just happened.
