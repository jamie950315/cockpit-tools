# Cross-host model synchronization workflow

Use this reference for this repository's PPLX Proxy, Pi5 CLIProxyAPI, Cockpit
Tools, and Codex deployment. Discover current state every time; model counts and
versions change frequently.

## 1. Define the requested model-set change

Identify where the change originated:

- PPLX Proxy registry changed: compare its authenticated `/v1/models` response
  with the `pplx/*` entries currently configured in CLIProxyAPI.
- Another CLIProxyAPI provider changed: compare CLIProxyAPI `/v1/models` with
  Cockpit's embedded provider model list.
- Models exist upstream but are missing only in Codex: inspect Cockpit's provider
  catalog, mixed-route snapshot, live manifest, and host catalogs before editing
  the upstream services.

Record exact additions, removals, and renames. Do not infer correctness from a
larger count. Confirm that duplicate IDs, stale aliases, and removed models are
absent from the desired result.

Choose the correct source of truth. A provider's configured model list is the
desired set when the live list can temporarily shrink because a credential is
cooling or rate-limited. Use the live list as health evidence, not as an
automatic deletion instruction, until the difference is proven permanent.

Before changes, inspect Git status and recent commits in every source repository
being touched. Preserve unexplained work separately. Create timestamped backups
for live configuration and catalog files without copying secrets into commands,
logs, chat, Git, or documentation.

All local shell commands in this environment must use the `rtk` prefix. Use
`rg` for local searches and the best available fallback on remote hosts.

## 2. PPLX Proxy

The live repository and service are on RPi:

- repository: `/home/jamie/pplx-proxy`
- service: `pplx-proxy.service`

If the user already updated the PPLX model registry, treat that commit and the
live authenticated `/v1/models` response as the upstream candidate. Verify the
repository is clean and the service is running. If source changes are required,
follow its `AGENTS.md`, preserve its formatting conventions, run its full test
suite and syntax check, restart the service, inspect logs, and make a real
non-streaming plus streaming request.

Codex/OpenAI Chat Completions may send `message.content` as typed content parts
rather than a string. Preserve support for both `input_text` and `text` parts.
An `AttributeError` involving `.lower()` on a list indicates that compatibility
regressed.

When Perplexity answers with a different model, the response should visibly end
with a marker such as:

```text
[Substituted by Perplexity with GPT-5 Nano]
```

This is a successful proxy response with an upstream substitution, not evidence
that the requested model actually served the answer. Confirm the marker survives
the CLIProxyAPI and Codex conversion paths.

## 3. Pi5 CLIProxyAPI

The live deployment is `/home/jamie/docker/cli-proxy-api` and normally listens
on port 8317. Preserve its immutable image digest and rollback-capable updater.

Update only the relevant provider model list in `config.yaml`. For a PPLX
refresh, make its configured IDs match the current PPLX catalog with the expected
`pplx/` namespace. Back up the config first, recreate or restart only the needed
service, and verify:

- the container is running with zero unexpected restarts;
- the installed version is the intended pinned version;
- authenticated `/v1/models` contains every addition and no removed ID;
- a real `/v1/responses` request works for a newly added model;
- logs contain no upstream 5xx, conversion crash, or open circuit breaker.

Use secret-safe request handling: read credentials from their protected source,
never print them, and avoid placing them in process arguments when a stdin or
mode-0600 config can be used. Do not change the five OAuth auth files as part of
a provider model-list refresh.

## 4. Cockpit provider and mixed route

On Mac, relevant runtime paths include:

- persistent collection:
  `~/.antigravity_cockpit/codex_local_access.json`
- live manifest:
  `~/.antigravity_cockpit/codex_local_access_sidecar/manifest.json`
- experimental catalog input:
  `~/.codex/.cockpit-experimental-model-catalog-config.json`
- managed catalog:
  `~/.codex/cockpit-model-catalog.json`

Cockpit 1.3.36 can save a refreshed provider catalog without updating an
existing mixed route's embedded `providerGateway.upstreamModels` snapshot.
Validate and synchronize both objects. The provider remains Responses-compatible
when that is the working CLIProxyAPI wire format.

Treat these as separate states:

- a Codex catalog controls what the selector displays;
- manifest `modelIds` or `/v1/models` controls what the sidecar advertises;
- the running route matcher controls whether a request can actually resolve.

A model can appear in both the selector and live `/v1/models` while a real
request still returns `model_route_not_available`. Always make a real request
after a sidecar reload. A running Cockpit process can retain the old route in
memory and overwrite manual disk edits during regeneration.

The mixed route belongs to the local API key whose `modelRouting` is non-null.
Preserve its default OAuth route, strict failure policy, provider gateway, and
uppercase `CPA`. Saving the mixed-route form may lowercase the namespace. Do not
press Apply merely to inspect it.

If exact store repair is required, make restricted timestamped backups and stop
Cockpit only when the active task does not depend on it. After restart, compare
the persisted collection, backup copy, and live manifest, then verify that the
sidecar still listens on port 57204. Never expose the route's embedded secret.
Do not use immutable file flags or post-exit watcher scripts to win a write race
against Cockpit. If the current task depends on that sidecar, prepare and verify
the stopped-state change, then require a user-controlled relaunch or use another
independent task that will remain connected.

The default Mac Codex config must continue to use `codex_local_access`, the
local port 57204, and `cockpit-model-catalog.json`. Do not inject the route into
the default instance or replace its special `__api_service__` binding.

CTPS has its own Cockpit provider catalog, persistent collection, and live
sidecar manifest under the Windows user profile. Synchronize and verify both its
provider catalog and the route-bearing API key's embedded upstream set
independently from Mac; otherwise a later UI edit can restore a stale route.
WSL routes through this CTPS sidecar. Keep CTPS
`codex_auto_restore_takeover_on_launch = false` so a Cockpit restart does not
replace the user-owned catalog reference. Cockpit and its sidecar must remain in
the interactive Windows desktop session.

When a remote interactive relaunch is necessary, use a narrowly scoped
timestamped Scheduled Task only after confirming CTPS and WSL are idle. Verify
the new processes run in Session 1, then remove the task and its exact temporary
script. Keep the pre-change backup.

## 5. Rebuild host catalogs without losing official models

Derive the desired namespaced set from the current CLIProxyAPI models:

- model ID: `CPA/<upstream-id>`
- display name: `CPA · <upstream-id>`

For every host, preserve its own current unprefixed official entries and replace
only its `CPA/*` entries. Remove stale `cliproxy/*`, lowercase `cpa/*`, renamed,
or deleted IDs unless the user explicitly requested an alias.

Current catalog locations and context policies:

- Mac managed catalog: raw context 526316, default/effective 95 percent, compact
  450000, yielding a usable 500000 window. Update the experimental catalog input
  so Cockpit regenerates the managed file.
- CTPS Windows:
  `%USERPROFILE%\.codex\user-mixed-routing-model-catalog.json`, raw context
  500000, effective 100 percent, compact 450000.
- WSL: `/home/jamie/.codex/wsl-cpa-500k-catalog.json`, raw context 500000,
  effective 100 percent, compact 450000.
- RPi: `/home/jamie/.codex/rpi-all-models-500k-catalog.json`, raw context 526316,
  effective 95 percent, compact 450000.

Do not force total catalog parity: hosts can expose different official models.
Keep WSL's provider as `ctps_local_access` and RPi's provider as `pi5-api`; do
not replace their base URLs or authentication fields during catalog work. Do not
copy `auth.json` between hosts. On CTPS, temporary Scheduled Tasks used for
recovery must be removed afterward. Never round-trip its credential-bearing
Cockpit store through PowerShell `ConvertTo-Json`; repair a sanitized or
backed-up candidate with a structure-preserving tool and compare it before
installation. Validate `modelCatalog` as an array whose elements are string
model IDs, not only by its top-level type and count.

Avoid nested shell quoting such as Mac JavaScript template literals containing
PowerShell replacement strings. In particular, `${...}` can be expanded by the
outer JavaScript before PowerShell sees it and can corrupt JSON. Prefer a local
candidate file plus parse-and-compare validation, or use a PowerShell
`MatchEvaluator`/scriptblock that constructs the replacement from match groups.
Parse the result before any service restart. If WSL is reachable through the
Mac `ssh wsl` alias, run Linux checks directly rather than nesting WSL commands
inside remote PowerShell.

Reload a host's Codex app-server only after confirming no task on that host is
active. Existing tasks may retain their original model/context snapshot until
the owning app-server is safely reloaded or a new task is created.

Before restarting CTPS Cockpit or its sidecar, confirm that neither CTPS nor WSL
has an active task or request. WSL depends on the CTPS sidecar, so a CTPS restart
interrupts both environments even when the WSL app-server itself remains alive.

## 6. Verify every requested layer

Use current live evidence rather than cached counts:

1. PPLX authenticated `/v1/models`, when PPLX is in scope.
2. CLIProxyAPI authenticated `/v1/models`. Test every model for a small change.
   For a bulk import, test representative free or explicitly authorized models,
   avoid unapproved paid calls, and report the untested remainder.
3. Both Mac and CTPS Cockpit provider catalogs, persisted routes, and live
   manifests when those environments are in scope: exact provider and upstream
   sets, one route-bearing API key each, uppercase `CPA`, five OAuth credential
   records, OAuth default route, and strict failure.
4. Each host's `codex debug models`: additions present once, removed IDs absent,
   display names correct, and effective context/compact values correct.
5. For a small change, make at least one real end-to-end request for every newly
   added `CPA/*` model. For a bulk provider import, use representative models and
   do not trigger paid inference without explicit authorization. On every
   requested routing environment, also run one representative official request
   and one representative namespaced request. Inspect logs to distinguish OAuth
   routing from the namespaced provider route; HTTP 200 alone is insufficient.
6. For a PPLX substitution, require the visible substitution marker and report
   that native upstream availability was not proven. Empty assistant output is
   not a successful end-to-end verification even when intermediate HTTP calls
   returned 200.
7. Classify upstream failures precisely. A provider-originated 401, 402/credits,
   or 429 proves the route reached that provider, but does not prove inference
   availability. A Cockpit `model_route_not_available` 404 proves the live route
   matcher is stale or missing even if the model is advertised.
8. Confirm services remain healthy, restart counts are stable, temporary files
   and recovery tasks are gone, and source worktrees are clean after commits.

Do not restart the Mac Cockpit/API Service from the task using it. When that
action is the only remaining step, leave a validated launch preview and ask the
user to perform the launch, then resume verification afterward.

## 7. Document and preserve recovery

When the model set or synchronization behavior changed, update
the repository-root `AGENTS.md` and
`docs/COCKPIT_MIXED_ROUTING_RUNBOOK.md` with current
state and durable failure guidance, not a chronological log. Never include
credentials, account IDs, raw manifests, or fixed model counts as universal
requirements.

Commit and push source changes in their owning repository after tests pass.
Commit Cockpit documentation separately. Keep useful rollback backups until all
target environments pass; delete only exact temporary artifacts created by the
current operation.
