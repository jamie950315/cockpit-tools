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

Current installed Cockpit state (verified 2026-09-01): the upstream 1.3.35
arm64 release is installed at `/Applications/Cockpit Tools.app`; official OAuth
and `cliproxy/*` routing both passed real Responses requests. The OAuth pool has
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
