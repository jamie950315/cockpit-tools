# Codex Model Manager

This native SwiftUI utility edits the user-owned Cockpit experimental catalog
input and its generated Codex catalog without changing Cockpit, Codex, or
ChatGPT binaries.

Preserve model array order, unknown JSON fields, context values, the uppercase
`CPA` namespace, and all routed model IDs. New models may be added only when
they are already present in Cockpit's live manifest. Never read, display, log,
or modify provider API keys, OAuth data, route stores, or account IDs.

Run `swift test --package-path tools/CodexModelManager` and build the `.app`
with `tools/CodexModelManager/scripts/build-app.sh` before delivery. Validate
catalog changes against copies or fixtures; do not restart Cockpit or Codex
while an active task depends on the sidecar.
