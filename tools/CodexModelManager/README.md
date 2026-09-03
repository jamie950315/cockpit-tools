# Codex Model Manager

Codex Model Manager is a native macOS utility for maintaining the model order
and display names used by Cockpit Tools' managed Codex catalog. It does not
modify the Cockpit Tools, Codex, or ChatGPT application binaries.

## Features

- Keep Cockpit's built-in priority models fixed at the top of the catalog.
- Select a movable model and use the Up/Down arrow keys for fast repeated
  movement, or enter an exact one-based position below the locked section.
- Show a persistent selection highlight and lock indicators in the model list.
- End search-field editing when a model is selected so Up/Down movement works
  immediately after filtering.
- Quit the application when its last window is closed.
- Edit the display name without changing the routed model ID.
- Add models that are already advertised by Cockpit's live sidecar manifest.
- Automatically detect provider, mixed-route, and catalog changes while the app
  is open.
- Synchronize newly refreshed CLIProxyAPI models into the existing `CPA` mixed
  route and both Codex catalogs with one button. Synchronization is additions
  only; it never removes existing models.
- Clearly identify models removed from the refreshed provider catalog without
  automatically deleting them from the route or Codex.
- Block route synchronization while Cockpit Tools is running so its in-memory
  state cannot overwrite the saved route.
- Preserve unknown JSON fields and the existing model context configuration.
- Back up every changed catalog and route file before each atomic save.
- Refuse to overwrite catalog files changed by Cockpit after they were loaded.

## Managed files

- `~/.codex/.cockpit-experimental-model-catalog-config.json`
- `~/.codex/cockpit-model-catalog.json`
- `~/.antigravity_cockpit/codex_local_access_sidecar/manifest.json` (read only)
- `~/.antigravity_cockpit/codex_model_providers.json` (model metadata only)
- `~/.antigravity_cockpit/codex_local_access.json` (only the routed API key's
  `CPA` `providerGateway.upstreamModels` array is extended during synchronization)

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

After Cockpit's provider refresh, switch to Codex Model Manager. It reloads the
source files automatically and shows the exact pending count. Finish active
Codex work, quit Cockpit Tools, press **同步模型**, reopen Cockpit, then launch
Codex through Cockpit's API Service. The app never edits the live manifest or
restarts either application itself.

Cockpit's built-in models are detected from the managed catalog as visible,
unprefixed entries with priority below 1000. Their priority order is fixed.
Other entries remain movable but cannot cross above that locked block.
