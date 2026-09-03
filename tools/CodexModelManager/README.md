# Codex Model Manager

Codex Model Manager is a native macOS utility for maintaining the model order
and display names used by Cockpit Tools' managed Codex catalog. It does not
modify the Cockpit Tools, Codex, or ChatGPT application binaries.

## Features

- Move a model to an exact one-based position or nudge it up and down.
- Edit the display name without changing the routed model ID.
- Add models that are already advertised by Cockpit's live sidecar manifest.
- Warn about provider models that have not reached the live mixed route.
- Preserve unknown JSON fields and the existing model context configuration.
- Back up both catalog files before every atomic save.
- Refuse to overwrite catalog files changed by Cockpit after they were loaded.

## Managed files

- `~/.codex/.cockpit-experimental-model-catalog-config.json`
- `~/.codex/cockpit-model-catalog.json`
- `~/.antigravity_cockpit/codex_local_access_sidecar/manifest.json` (read only)
- `~/.antigravity_cockpit/codex_model_providers.json` (model metadata only)

Backups are written to `~/.codex/model-manager-backups/` with mode `0700`; the
backed-up files use mode `0600`.

## Build and test

```bash
swift test --package-path tools/CodexModelManager
tools/CodexModelManager/scripts/build-app.sh
```

The app bundle is generated at
`tools/CodexModelManager/dist/Codex Model Manager.app`. Set
`CODE_SIGN_IDENTITY` to use a non-ad-hoc signing identity.

After saving, restart Codex or launch it again through Cockpit's API Service so
the app-server loads the updated catalog. Do not restart Cockpit or Codex while
an active task depends on the sidecar.
