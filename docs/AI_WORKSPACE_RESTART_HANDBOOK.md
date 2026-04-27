# AI Workspace Restart Handbook

Last updated: `2026-04-27`

## Purpose

This file is the dedicated restart helper for AI-assisted work across the full Duress workspace.

Use it when:

- the coding session crashes
- the assistant loses context
- a fresh AI session needs to resume quickly
- someone needs a single-file map of the whole end-to-end project

This is not a product design document.

It is the operational handoff file for restarting work efficiently across the multiple GitHub repos and runtime surfaces in this workspace.

## The workspace is not one repo

Do not treat `D:\Duress` as a single git repository.

The workspace contains multiple repos:

| Area | Local path | Current default branch | GitHub remote |
|---|---|---|---|
| Windows client | `D:\Duress\Duress2025` | `main` | `https://github.com/andyitd/Duress2025.git` |
| Windows server | `D:\Duress\_external\DuressServer2025` | `v3` | `https://github.com/andyitd/DuressServer2025.git` |
| Cloud control plane / portal | `D:\Duress\DuressCloud` | `main` | `https://github.com/hex007x/DuressCloudV3.git` |
| Shared release/regression/orchestration | `D:\Duress\DuressReleaseOps` | `main` | `https://github.com/hex007x/DuressReleaseOps-` |
| Mac client | `D:\Duress\_external\duress-mac` | `main` | `https://github.com/andyitd/duress-mac.git` |

## The fast restart path

When resuming after a crash, do these first:

1. Read `D:\Duress\AGENTS.md`.
2. Read this file.
3. Check repo status in every participating repo:

```powershell
git -C D:\Duress\Duress2025 status --short
git -C D:\Duress\_external\DuressServer2025 status --short
git -C D:\Duress\DuressCloud status --short
git -C D:\Duress\DuressReleaseOps status --short
git -C D:\Duress\_external\duress-mac status --short
```

4. Do not revert unrelated user changes.
5. Determine which repo or repos the task actually belongs to before editing.

## The current operating reality

Right now the real platform shape is:

- Windows client
- Windows server
- Cloud
- Mac client
- shared release/regression harnesses in `DuressReleaseOps`

Right now the real cloud hosting model is:

- Duress Cloud is run locally from this Windows machine for dev, test, and release rehearsal
- it is started and verified by scripts
- it is not currently “the DigitalOcean production deployment” in day-to-day practice

Do not blur:

1. current real workflow
2. future target production workflow

For current cloud operations, start with:

- `D:\Duress\DuressCloud\docs\CURRENT_HOSTED_DEV_TEST_RELEASE_RUNBOOK_2026-04-23.md`
- `D:\Duress\DuressCloud\docs\CLOUD_START_AND_VERIFY_RUNBOOK.md`

## Canonical workspace docs

Start here before guessing:

- workspace rules: `D:\Duress\AGENTS.md`
- release path: `D:\Duress\RELEASE_OPERATIONS.md`
- readiness/gate state: `D:\Duress\RELEASE_READINESS_CHECKLIST.md`
- versioning: `D:\Duress\RELEASE_VERSIONING_POLICY_2026-04-13.md`
- release ledger: `D:\Duress\LOCAL_RELEASE_LEDGER.md`
- shared docs map: `D:\Duress\DuressReleaseOps\docs\REPO_TESTING_AND_DOCUMENTATION_MAP.md`
- full platform architecture: `D:\Duress\DUress_V3_END_TO_END_ARCHITECTURE.md`

## Repo ownership map

### `Duress2025`

Use for:

- Windows client code
- Windows client installer behavior
- workstation and terminal-services client behavior
- client runtime docs

Start with:

- `D:\Duress\Duress2025\README.md`
- `D:\Duress\Duress2025\docs\WINDOWS_CLIENT_TECHNICAL_TEST_GUIDE.md`
- `D:\Duress\Duress2025\INSTALLER_PARAMETERS.md`

### `_external\DuressServer2025`

Use for:

- Windows server/service code
- licensing-consumer behavior
- claim/check-in/runtime behavior
- rollout/export/provisioning behavior owned by the server

Start with:

- `D:\Duress\_external\DuressServer2025\README.md`
- `D:\Duress\_external\DuressServer2025\docs\SERVER_TECHNICAL_TEST_GUIDE.md`
- `D:\Duress\_external\DuressServer2025\docs\CLIENT_POLICY_OPERATOR_GUIDE_2026-04-22.md`

### `DuressCloud`

Use for:

- portal/admin/customer cloud code
- billing/commercial/licensing control plane
- installer library publishing and customer download paths
- current local cloud hosting scripts

Start with:

- `D:\Duress\DuressCloud\README.md`
- `D:\Duress\DuressCloud\docs\CURRENT_HOSTED_DEV_TEST_RELEASE_RUNBOOK_2026-04-23.md`
- `D:\Duress\DuressCloud\docs\ADMIN_SITE_USER_GUIDE.md`
- `D:\Duress\DuressCloud\docs\END_TO_END_LICENSE_AND_CUSTOMER_GUIDE.md`

### `DuressReleaseOps`

Use for:

- cross-repo regression
- shared proof packs
- release orchestration
- crash-restart handoff docs like this file

Start with:

- `D:\Duress\DuressReleaseOps\README.md`
- `D:\Duress\DuressReleaseOps\docs\REPO_TESTING_AND_DOCUMENTATION_MAP.md`
- `D:\Duress\DuressReleaseOps\test-env\README.md`

### `_external\duress-mac`

Use for:

- Mac client code
- Mac parity/non-parity notes
- Mac support/runbook docs
- Mac compatibility and smoke guidance

Start with:

- `D:\Duress\_external\duress-mac\README.md`
- `D:\Duress\_external\duress-mac\docs\MAC_CLIENT_TECHNICAL_TEST_GUIDE.md`
- `D:\Duress\_external\duress-mac\docs\MAC_WINDOWS_CLIENT_PARITY_MATRIX.md`
- `D:\Duress\_external\duress-mac\docs\MAC_SUPPORT_ENABLEMENT_RUNBOOK.md`
- `D:\Duress\_external\duress-mac\docs\MAC_VERSION_COMPATIBILITY.md`

## Cloud start and verify discipline

Do not start the cloud by launching `DuressCloud.Web.exe` directly from `bin`.

Use:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Duress\DuressCloud\scripts\setup-local-dev.ps1
powershell -ExecutionPolicy Bypass -File D:\Duress\DuressCloud\scripts\start-duress-cloud.ps1
powershell -ExecutionPolicy Bypass -File D:\Duress\DuressCloud\scripts\verify-duress-cloud.ps1
```

Minimum cloud proof:

- listener on `0.0.0.0:5186` or active LAN IP
- `http://localhost:5186/health` returns `200`
- `http://<lan-ip>:5186/health` returns `200`
- `http://<lan-ip>:5186/css/site.css` returns `200`
- `http://<lan-ip>:5186/Management/Login` returns `200`

Health alone is not enough.

## Build and test anchors

### Windows client

Primary build:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Duress\Duress2025\scripts\build-hardened-release.ps1
```

Key verification:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Duress\DuressReleaseOps\test-env\verify-windows-client-runtime.ps1
powershell -ExecutionPolicy Bypass -File D:\Duress\DuressReleaseOps\test-env\verify-client-config-modes.ps1
```

### Windows server

Primary build:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Duress\_external\DuressServer2025\scripts\build-hardened-release.ps1
```

### Cloud

Key tests:

```powershell
dotnet test D:\Duress\DuressCloud\tests\DuressCloud.Web.Tests\DuressCloud.Web.Tests.csproj
dotnet test D:\Duress\DuressCloud\tests\DuressCloud.Web.IntegrationTests\DuressCloud.Web.IntegrationTests.csproj
```

### Shared regression

Primary regression entry points:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Duress\DuressReleaseOps\test-env\exercise-full-regression-pack.ps1
powershell -ExecutionPolicy Bypass -File D:\Duress\DuressReleaseOps\test-env\exercise-linked-cloud-regression-suite.ps1
powershell -ExecutionPolicy Bypass -File D:\Duress\DuressReleaseOps\test-env\exercise-operator-rollout-regression-suite.ps1
powershell -ExecutionPolicy Bypass -File D:\Duress\DuressReleaseOps\test-env\exercise-server-deployment-ui-smoke-suite.ps1
```

### Mac

Current truth:

- source-level progress exists
- parity/support/version docs now exist in the Mac repo
- meaningful runtime proof still requires a real Mac

Current remote access path from this Windows machine:

- SSH alias: `duress-mac`
- Host: `192.168.20.73`
- User: `itd`
- Dedicated key: `C:\Users\jforr\.ssh\id_ed25519_duress_mac`

Quick verify command:

```powershell
ssh -o BatchMode=yes duress-mac "hostname && sw_vers"
```

If this fails after a restart:

1. check `C:\Users\jforr\.ssh\config`
2. confirm `C:\Users\jforr\.ssh\id_ed25519_duress_mac` still exists
3. retry `ssh -vvv duress-mac "exit"`
4. only fall back to password auth if key auth stops working again

## Release flow

The enforced release path is:

1. choose scope and version
2. check repo status in all participating repos
3. commit intended changes in each participating repo
4. run release prep
5. build artifacts
6. run repo-local and shared proof
7. update release notes and ledger
8. publish MSI packages to the cloud library if needed
9. run release verification

Release prep:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Duress\scripts\prepare-release.ps1 -Version <version> -Products Client,Server,Cloud
```

Release verification:

```powershell
powershell -ExecutionPolicy Bypass -File D:\Duress\scripts\verify-release.ps1 -Version <version> -Products Client,Server,Cloud
```

If `verify-release.ps1` fails, the release is not complete.

## Commit and push rule

Any change we make should be committed and pushed in the relevant repo.

That means:

- check `git status --short` first
- stage only the intended files
- use a real commit message
- push the branch after the commit
- do not sweep unrelated user changes into the commit

## Quick “what changed?” commands

Use these after a restart:

```powershell
git -C D:\Duress\Duress2025 status --short
git -C D:\Duress\_external\DuressServer2025 status --short
git -C D:\Duress\DuressCloud status --short
git -C D:\Duress\DuressReleaseOps status --short
git -C D:\Duress\_external\duress-mac status --short
```

And if needed:

```powershell
git -C D:\Duress\Duress2025 log --oneline -n 5
git -C D:\Duress\_external\DuressServer2025 log --oneline -n 5
git -C D:\Duress\DuressCloud log --oneline -n 5
git -C D:\Duress\DuressReleaseOps log --oneline -n 5
git -C D:\Duress\_external\duress-mac log --oneline -n 5
```

## Path hygiene

If older docs mention `C:\OLDD\Duress`, translate them to `D:\Duress`.

Prefer:

- `D:\Duress\DuressReleaseOps\test-env`

over the older root-level `D:\Duress\test-env` when shared docs point there.

## Current known caution areas

- `DuressReleaseOps` may contain unrelated in-progress user changes; do not revert them casually.
- Mac runtime proof cannot be completed from this Windows machine alone.
- Cloud start/verify must stay script-driven.
- Server/client rollout changes often require client and server to release together.
- The cloud’s current real host is this Windows machine, not the future DigitalOcean target.

## When restarting after a crash, what should the AI say first?

The AI should quickly state:

1. which repo or repos are in scope
2. what the current dirty state is
3. what docs it is using as the canonical source of truth
4. what first verification or read step it is taking

That avoids repeating broad rediscovery work and keeps the restart efficient.

## Recommended companion files to keep open

- `D:\Duress\AGENTS.md`
- `D:\Duress\RELEASE_OPERATIONS.md`
- `D:\Duress\RELEASE_READINESS_CHECKLIST.md`
- `D:\Duress\DuressCloud\docs\CURRENT_HOSTED_DEV_TEST_RELEASE_RUNBOOK_2026-04-23.md`
- `D:\Duress\DuressReleaseOps\docs\REPO_TESTING_AND_DOCUMENTATION_MAP.md`

## Maintenance rule for this file

Update this file whenever one of these changes:

- repo list
- branch defaults
- GitHub remotes
- current cloud hosting model
- primary restart commands
- canonical docs
- release flow
- shared regression entry points

If those drift, restart efficiency drops quickly.
