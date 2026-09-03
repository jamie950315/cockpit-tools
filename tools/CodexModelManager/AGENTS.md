# Codex Model Manager

This native SwiftUI utility edits the user-owned Cockpit experimental catalog
input and its generated Codex catalog without changing Cockpit, Codex, or
ChatGPT binaries.

Preserve model array order, write matching sequential priorities, preserve
unknown JSON fields and context values, and keep all routed model IDs. The app
may read provider, route, and manifest model IDs to calculate differences but
must never write Cockpit route stores, credentials, or the live manifest.

Synchronization is additions-only and may add only models already advertised by
the live manifest. Never remove models automatically or run a persistent watcher
outside the app. Provider removals must be detected and shown as a
non-destructive difference.

Run `swift test --package-path tools/CodexModelManager` and build the `.app`
with `tools/CodexModelManager/scripts/build-app.sh` before delivery. Validate
catalog changes against copies or fixtures; do not restart Cockpit or Codex
while an active task depends on the sidecar.
