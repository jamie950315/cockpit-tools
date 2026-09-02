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
Cockpit's config and restore the user-owned catalog reference. This setting only
disables restoration when Cockpit itself launches. Starting Codex through
Cockpit's API Service action still reactivates takeover and replaces the
external catalog reference; restore the reference afterward and create a new
task, or start Codex directly without reactivating API Service. The OAuth pool has
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

Current Codex context overrides (verified after upgrading to 1.3.36 on
2026-09-02) use the external,
user-owned `~/.codex/user-mixed-routing-model-catalog.json` selected by
`model_catalog_json`; they do not modify the upstream 1.3.35 app. Every catalog
model is deliberately forced to context 500000, compact 450000, and
`effective_context_window_percent = 100`, regardless of its upstream limit.
Because this is a static catalog, regenerate and revalidate it whenever
Cockpit's visible model set changes.

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
