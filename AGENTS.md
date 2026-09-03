# Fork Maintenance Notes

Read [`docs/COCKPIT_MIXED_ROUTING_RUNBOOK.md`](docs/COCKPIT_MIXED_ROUTING_RUNBOOK.md) before rebuilding, signing, installing, upgrading, or repairing the custom Cockpit Tools app and its five-account OAuth/CLIProxyAPI mixed routing.

For model additions, removals, renames, or provider catalog refreshes across
Mac, CTPS Windows, WSL, and RPi, use the repository-scoped
`cockpit-sync-models` skill at
`.agents/skills/cockpit-sync-models/SKILL.md`. The repository copy is canonical;
it requires live set comparison and end-to-end requests rather than relying on
historical model counts.

This fork keeps three public branches with deliberately separate scopes:

- `xcode27patch`: only the Xcode 27 / Swift 6.4 static-library linker fix in `src-tauri/build.rs`.
- `cliproxy`: upstream mixed-model routing plus the sanitized five-account OAuth and CLIProxyAPI deployment guide.
- `main`: all changes from both branches.

Never commit Cockpit runtime stores, API keys, OAuth tokens, account IDs, auth files, generated model catalogs, build products, or local signing material.

Before publishing code changes, run the relevant frontend, Go, Rust, and macOS bundle checks described in the repository documentation. A model appearing in a catalog is not proof of correct routing; validate an official OAuth request and a namespaced CLIProxyAPI request independently in the target environment.

The standalone native macOS utility under `tools/CodexModelManager/` manages
the ordered model definitions used by Cockpit's experimental catalog. It may
reorder models, change display names, and add models already advertised by the
live sidecar manifest, but it must never edit routing stores or credentials.
Cockpit built-in models remain locked at the top in their catalog priority
order; other models can be selected and moved repeatedly with the Up/Down keys
but cannot cross that boundary.
Keep its file-change guard, restricted backups, unknown-field preservation, and
500K/450K context preservation. Build artifacts under its `.build/` and `dist/`
directories are not source. After changing it, run its Swift tests, build and
sign the app, and inspect the real UI against the live catalog without saving.

The Pi5 CLIProxyAPI deployment has a daily, rollback-capable updater maintained
under `ops/cliproxyapi/`. Keep the container pinned by immutable digest through
its `.env`; an update is successful only after the runtime version, model list,
five TEAM auth files, and five real Responses requests pass.

Current installed Cockpit state (verified 2026-09-02): the upstream 1.3.36
arm64 release is installed at `/Applications/Cockpit Tools.app`; official OAuth
and `CPA/*` routing both passed real Responses requests after the upgrade.
On its first launch, 1.3.36 restored takeover before the new setting could be
disabled and changed `model_catalog_json` back to its managed catalog. The UI
toggle did not persist a false value in the existing user config, so the durable
repair was to set `codex_auto_restore_takeover_on_launch = false` explicitly in
Cockpit's config. This setting only disables restoration when Cockpit itself
launches; starting Codex through Cockpit's API Service action is a separate
takeover path and must remain the normal launch method for the five-OAuth plus
CLIProxyAPI setup. The OAuth pool has
five distinct TEAM credential records, but that does not mean five distinct
ChatGPT login identities. With `routingStrategy = "auto"` and session affinity
enabled, ten official requests using distinct session IDs all selected one OAuth
credential; do not describe this state as five-account round-robin. One pool
credential is also marked as a backup. The upstream macOS bundle is ad-hoc
signed, so preserve the two validly signed 1.3.34 custom backups listed in the
mixed-routing runbook for recovery.

The CLIProxyAPI API-key account must remain outside the OAuth account pool.
Codex sees `CPA/*` because the local API key's `modelRouting` route embeds
the provider gateway and its `upstreamModels`; the sidecar advertises those
models with the route namespace through its model endpoint. Pool membership does
not control namespaced model visibility.

The current namespace is the case-sensitive `CPA`, with no visible
`cliproxy/*` alias. Cockpit 1.3.36 preserves an uppercase namespace when loading
the stopped app's persisted collection, but its mixed-route form normalizes a
saved namespace to lowercase. After editing or copying that route in the UI,
recheck both the persistent collection and live manifest before trusting the
selector. Existing tasks may retain their old model name until their host's
idle app-server is reloaded and a supported model override is sent.
Model IDs use `CPA/<upstream-id>` and their selector display names use
`CPA · <upstream-id>`; changing only the ID leaves the old provider label in
Codex. Do not inject the API Service route into the default Codex instance to
remove the launch-preview editor's `路由缺失` badge. The default launch binding
must remain Cockpit's special `__api_service__` identity with no instance-level
`modelRouting`; replacing it with a normal instance configuration makes API
Service client launch fail. The badge is only an editor limitation, while the
real route is owned by the local API key's `modelRouting`. Do not press Apply in
that dialog solely to inspect it, because 1.3.36 may lowercase the uppercase
namespace on save.

Launching Codex through a single Cockpit OAuth account can replace API Service
takeover with a temporary per-account localhost provider, remove the managed
catalog reference, and leave Codex sending the single OAuth token to the API
Service sidecar. Restoring `config.toml` and the catalog is not sufficient: the
final API Service launch action must run so Cockpit switches client auth back to
its local API key. That action restarts Codex, so never trigger it from the
active task performing the repair; leave the validated launch preview for the
user to finish.

Current Mac Codex context overrides (verified after upgrading to 1.3.36 on
2026-09-02) use Cockpit's managed catalog so API Service takeover remains the
normal launch path. Every entry in
`~/.codex/.cockpit-experimental-model-catalog-config.json` declares context
526316 and compact 450000. Codex applies its catalog default of 95 percent,
producing an actual `model_context_window` of 500000; a real new CLI task
confirmed that value. Keep `model_catalog_json = "cockpit-model-catalog.json"`.
The raw 526316 deliberately compensates for Codex's 95-percent factor and may
overstate smaller upstream models, an accepted user-selected tradeoff.
Codex Desktop currently renders only the first 50 internal model definitions.
The model manager changes the actual definition array order rather than
prefixing display names; moving a model into that first-50 window is the durable
way to make it visible without modifying ChatGPT or Codex binaries.

CTPS Windows deployment (verified 2026-09-02): official Cockpit Tools 1.3.36
x64 and Codex CLI 0.152.1 are installed. Its Cockpit store contains the same
five OAuth credential records and CLIProxyAPI provider copied over encrypted
SSH. Its user-owned catalog carries the same `CPA/*` set as Mac but is not
byte-identical: host-specific official models differ, and Windows uses raw
context 500000 with effective percent 100 while Mac uses 526316 with the default
95-percent factor.
After a full Cockpit restart, real official and `CPA/*` Responses requests
both returned HTTP 200. Keep
`codex_auto_restore_takeover_on_launch = false` on CTPS so Cockpit 1.3.36 does
not replace the user-owned catalog reference with its managed catalog. The old
Windows Codex CLI ChatGPT login has a reused refresh token; this produces login
errors but does not prevent requests through `codex_local_access`. Do not copy
Mac `auth.json` to fix it. Use a fresh Windows `codex login --device-auth` only
if native Codex account features are needed.
The Windows active static catalog also uses `CPA · <upstream-id>` display names,
but no default-instance file should be created solely to mirror the API Service
route.

Current PPLX/CLIProxyAPI model synchronization (verified 2026-09-03): the PPLX
proxy still advertises 23 models. Pi5 CLIProxyAPI now also has OpenCode Zen as an
`openai-compatibility` provider at `https://opencode.ai/zen/v1` with prefix
`opencode`. Free OpenCode models require official CLI identification headers:
`User-Agent: opencode/<version>`, `x-opencode-client`, `x-opencode-session`,
`x-opencode-project`, and `x-opencode-request`. A browser User-Agent that was
added to avoid Cloudflare 1010 makes Zen treat the request as a non-official
client and apply the fallback IP quota, which can return `429 FreeUsageLimitError`
with no successful prior use. After switching those headers, live
`opencode/big-pickle` and `CPA/opencode/big-pickle` requests returned HTTP 200
with `PING`. Keep `disable-cooling: true` and `request-retry: 0` on this
provider so a later 429 does not hide the catalog or multiply retries. Namespaced
IDs are `opencode/<upstream-id>`. OpenCode paid models need a workspace payment
method. A remaining 429 after the CLI headers are present is the real IP quota,
not a missing route. Occasional `500 Internal server error` is OpenCode upstream.
`CPA/*` catalogs follow the current CLIProxyAPI
set, including `CPA/opencode/*` and `CPA/gemini-3.8-flash-high`. Host totals
still differ because official models differ; do not force parity. Cockpit 1.3.36
does not propagate a saved provider catalog into an existing mixed-route
`providerGateway.upstreamModels` snapshot, and a running sidecar keeps the old
in-memory set until Cockpit is relaunched by the user. After a provider refresh,
synchronize that route snapshot, the live manifest, and every host catalog,
preserve uppercase `CPA`, then verify with `codex debug models`. Do not quit
Cockpit from a Codex task that depends on the sidecar. On CTPS, keep the
CLIProxyAPI `modelCatalog` as a JSON array; a PowerShell `ConvertTo-Json`
round-trip can wrap it as `{Count, value}` and must be unwrapped. PPLX proxy
commit `f215bde` accepts Codex/OpenAI content-part arrays; keep this
compatibility when changing its prompt handling.

The native `tools/CodexModelManager` app can now detect provider, persisted
mixed-route, live-manifest, and Mac Codex catalog differences while it is open.
Its **同步模型** action is additions-only and extends the route-bearing API
key's uppercase `CPA` upstream snapshot plus both Mac catalogs. It blocks route
writes while Cockpit is running, never edits the live manifest or restarts apps,
and requires a user-controlled Cockpit relaunch followed by API Service launch.
Provider removals are shown as a non-destructive difference and are never
deleted automatically.
It does not synchronize CTPS, WSL, or RPi; use `cockpit-sync-models` for those
hosts.
After a safe Cockpit relaunch in Windows interactive Session 1, the CTPS live
sidecar exposed all 125 configured `CPA/*` routes, including 66
`CPA/opencode/*` routes. WSL observed the same live set through CTPS. After the OpenCode CLI header
repair, a real `CPA/opencode/big-pickle` request from Mac Cockpit and from Pi5
CLIProxyAPI returned HTTP 200 with `PING`. CTPS/WSL previously proved route
reachability with `429 FreeUsageLimitError`; retest those hosts if they still
show the old error. A real official OAuth request returned HTTP 200. CTPS and WSL `codex debug models`
retained 500000 context, 100 percent effective context, and 450000 compact.

RPi SSH-host Codex context uses provider `pi5-api`. Its
`/home/jamie/.codex/config.toml` points `model_catalog_json` to
`/home/jamie/.codex/rpi-all-models-500k-catalog.json`. The static catalog keeps
the host's official models and the current `CPA/*` set from CLIProxyAPI,
including `CPA/opencode/*`, each declaring context 526316 and compact 450000; Codex applies
95 percent and reports an actual window of 500000. Fresh real
`gpt-5.6-luna` and `CPA/grok-4.6` tasks both returned `OK` with
`model_context_window = 500000`. Existing tasks retain the context snapshot
while the current app-server writer remains active. The existing
`更新並驗證 Perplexity 模型` task was upgraded in place from 124518 to 500000
by restarting only the idle RPi Codex 0.147.0 app-server, then sending a new
minimal turn to the same task ID; its history and project state were preserved.
Do this only after confirming no RPi task is active. The pre-change config backup is under
`/home/jamie/.codex/backups/20260902-before-all-models-500k/`. RPi's native
ChatGPT refresh token is invalid, but `pi5-api` requests still work; do not copy
another host's rotating `auth.json` to repair it.

WSL uses provider `ctps_local_access`, the CTPS local-access URL, and
`/home/jamie/.codex/wsl-cpa-500k-catalog.json`. Its catalog keeps the host's
official models plus the current `CPA/*` set with `CPA · <upstream-id>` display
names and no old prefix. WSL depends on the CTPS sidecar, so a CTPS Cockpit
relaunch interrupts WSL even if the WSL app-server stays up.
After reloading Codex 0.143.0 app-server,
fresh official and `CPA/*` CLI sessions both returned the expected answer with
`model_context_window = 500000`.
