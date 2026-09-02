# Fork Maintenance Notes

Read [`docs/COCKPIT_MIXED_ROUTING_RUNBOOK.md`](docs/COCKPIT_MIXED_ROUTING_RUNBOOK.md) before rebuilding, signing, installing, upgrading, or repairing the custom Cockpit Tools app and its five-account OAuth/CLIProxyAPI mixed routing.

This fork keeps three public branches with deliberately separate scopes:

- `xcode27patch`: only the Xcode 27 / Swift 6.4 static-library linker fix in `src-tauri/build.rs`.
- `cliproxy`: upstream mixed-model routing plus the sanitized five-account OAuth and CLIProxyAPI deployment guide.
- `main`: all changes from both branches.

Never commit Cockpit runtime stores, API keys, OAuth tokens, account IDs, auth files, generated model catalogs, build products, or local signing material.

Before publishing code changes, run the relevant frontend, Go, Rust, and macOS bundle checks described in the repository documentation. A model appearing in a catalog is not proof of correct routing; validate an official OAuth request and a namespaced CLIProxyAPI request independently in the target environment.

The Pi5 CLIProxyAPI deployment has a daily, rollback-capable updater maintained
under `ops/cliproxyapi/`. Keep the container pinned by immutable digest through
its `.env`; an update is successful only after the runtime version, model list,
five TEAM auth files, and five real Responses requests pass.

Current installed Cockpit state (verified 2026-09-02): the upstream 1.3.36
arm64 release is installed at `/Applications/Cockpit Tools.app`; official OAuth
and `cliproxy/*` routing both passed real Responses requests after the upgrade.
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
Codex sees `cliproxy/*` because the local API key's `modelRouting` route embeds
the provider gateway and its `upstreamModels`; the sidecar advertises those
models with the route namespace through its model endpoint. Pool membership does
not control namespaced model visibility.

Current Mac Codex context overrides (verified after upgrading to 1.3.36 on
2026-09-02) use Cockpit's managed catalog so API Service takeover remains the
normal launch path. Every entry in
`~/.codex/.cockpit-experimental-model-catalog-config.json` declares context
526316 and compact 450000. Codex applies its catalog default of 95 percent,
producing an actual `model_context_window` of 500000; a real new CLI task
confirmed that value. Keep `model_catalog_json = "cockpit-model-catalog.json"`.
The raw 526316 deliberately compensates for Codex's 95-percent factor and may
overstate smaller upstream models, an accepted user-selected tradeoff.

CTPS Windows deployment (verified 2026-09-02): official Cockpit Tools 1.3.36
x64 and Codex CLI 0.152.1 are installed. Its Cockpit store contains the same
five OAuth credential records and CLIProxyAPI provider copied over encrypted
SSH, while its user-owned model catalog is byte-identical to the Mac catalog.
After a full Cockpit restart, real official and `cliproxy/*` Responses requests
both returned HTTP 200. Keep
`codex_auto_restore_takeover_on_launch = false` on CTPS so Cockpit 1.3.36 does
not replace the user-owned catalog reference with its managed catalog. The old
Windows Codex CLI ChatGPT login has a reused refresh token; this produces login
errors but does not prevent requests through `codex_local_access`. Do not copy
Mac `auth.json` to fix it. Use a fresh Windows `codex login --device-auth` only
if native Codex account features are needed.

RPi SSH-host Codex context (verified 2026-09-02) is independent of the Mac and
uses provider `pi5-api`. Its `/home/jamie/.codex/config.toml` points
`model_catalog_json` to
`/home/jamie/.codex/rpi-all-models-500k-catalog.json`. The static catalog has 71
current models, each declaring context 526316 and compact 450000; Codex applies
95 percent and reports an actual window of 500000. Fresh real
`gpt-5.6-luna` and `cliproxy/grok-4.6` tasks both returned `OK` with
`model_context_window = 500000`. Existing tasks retain the context snapshot
from creation. The pre-change config backup is under
`/home/jamie/.codex/backups/20260902-before-all-models-500k/`. RPi's native
ChatGPT refresh token is invalid, but `pi5-api` requests still work; do not copy
another host's rotating `auth.json` to repair it.
