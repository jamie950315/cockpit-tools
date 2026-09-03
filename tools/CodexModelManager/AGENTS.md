# Codex Model Manager

This native SwiftUI utility edits the user-owned Cockpit experimental catalog
input and its generated Codex catalog without changing Cockpit, Codex, or
ChatGPT binaries.

Preserve model array order, unknown JSON fields, context values, the uppercase
`CPA` namespace, and all routed model IDs. The app may read the provider catalog
and structure-preservingly extend only the route-bearing API key's
`modelRouting.routes[].providerGateway.upstreamModels` for the uppercase `CPA`
route. It must keep `defaultRoute = oauth` and `failurePolicy = strict`, select
the API key by non-null `modelRouting` rather than array position, and never
display, log, or alter API keys, OAuth data, account IDs, or unrelated route
fields.

Synchronization is additions-only. Never modify the live manifest, remove
models automatically, run a persistent watcher outside the app, or write the
route store while Cockpit Tools is running. Back up the credential-bearing
route store with mode 0600 before changing it and require a user-controlled
Cockpit relaunch afterward. Provider removals must be detected and shown as a
non-destructive difference.

Treat visible, unprefixed managed-catalog entries with priority below 1000 as
Cockpit built-ins. Keep them fixed at the top in priority order and reject any
save that moves or reorders that block. Movable models use Cockpit's fallback
`1000 + array index` priority and may never cross above the built-in block. The
list supports a visible row selection and repeated Up/Down keyboard movement;
selecting a model must end any previous search-field editing focus, while
text-field arrow keys must remain available during active editing. Closing the
last app window must terminate the process rather than leave a menu-bar-only
application running.

Run `swift test --package-path tools/CodexModelManager` and build the `.app`
with `tools/CodexModelManager/scripts/build-app.sh` before delivery. Validate
catalog changes against copies or fixtures; do not restart Cockpit or Codex
while an active task depends on the sidecar.
