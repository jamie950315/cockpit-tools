---
name: cockpit-sync-models
description: Synchronize model additions, renames, removals, or refreshed catalogs through this deployment's PPLX Proxy, Pi5 CLIProxyAPI, Cockpit Tools CPA mixed route, and Codex on Mac, CTPS Windows, WSL, and RPi. Use for this repository's model-list changes, not generic Codex model configuration.
---

# Cockpit model synchronization

Make the requested model-set change visible and usable through every requested
layer without disturbing official OAuth routing, host-specific official models,
or the selected 500K context policy.

## Load the deployment contract

Resolve the repository root with Git, then read the current project
instructions and `docs/COCKPIT_MIXED_ROUTING_RUNBOOK.md` from that root before
any mutation. When changing `/home/jamie/pplx-proxy`, also read that repository's
`AGENTS.md` and inspect its current Git state.

Read [references/sync-workflow.md](references/sync-workflow.md) for the complete
cross-host procedure. Use only the host sections relevant to the user's request.
When adding or changing an OpenAI-compatible provider such as OpenCode Zen, also
read
[references/openai-compatible-provider.md](references/openai-compatible-provider.md).

## Preserve these invariants

- Unprefixed official models continue through Cockpit's OAuth route. Keep the
  five TEAM credential records and the CLIProxyAPI API-key account in their
  separate roles; do not claim that the five records are round-robin identities.
- Keep `defaultRoute = "oauth"`, `failurePolicy = "strict"`, session affinity,
  and the case-sensitive `CPA` namespace unless the user explicitly changes the
  routing design.
- Select the API key that actually has `modelRouting`; never assume array index
  zero. Do not rewrite credential-bearing Windows stores with PowerShell
  `ConvertTo-Json`.
- Do not add instance-level `modelRouting` to the default Mac Codex instance.
  Its API Service binding remains `__api_service__`.
- Keep CTPS `codex_auto_restore_takeover_on_launch = false`, WSL on provider
  `ctps_local_access`, and RPi on provider `pi5-api`; a model refresh must not
  replace these host-specific bindings.
- Never print, copy into chat, or commit API keys, OAuth material, account IDs,
  auth files, generated runtime stores, or provider gateway secrets. If a secret
  appears in tool output, inform the user and do not rotate it without explicit
  authorization.
- Do not quit Cockpit or relaunch API Service from the Codex task that depends on
  that sidecar. Ask the user to perform the final launch action when required.
- Do not make Cockpit runtime files immutable and do not leave background
  watchers that rewrite them after exit. These interfere with Cockpit's normal
  persistence and can leave disk, advertised models, and live routing divergent.

## Work from live differences

Discover the current upstream and downstream model sets, then calculate exact
additions, removals, and renames. Counts are observations, not acceptance
criteria. Preserve each host's own official models and replace only the `CPA/*`
portion derived from the current CLIProxyAPI catalog.

Back up every file before changing a credential-bearing store, provider config,
route snapshot, or static catalog. Make the narrowest change that produces the
requested set; retain rollback artifacts until live verification passes.

## Completion standard

Do not stop at catalog visibility. Verify the upstream service, CLIProxyAPI,
Cockpit's persisted route and live manifest, each requested host's resolved
Codex model list and context values. For a small model-set change, test every
new model. For a bulk provider import, test representative models without
incurring unapproved charges and state that the remaining models were not
individually proven. Also run representative official and namespaced requests on
each requested routing environment. Treat a visible Perplexity substitution
notice as proof that routing worked but not proof that the requested upstream
model answered. An upstream quota, payment, or rate-limit response proves route
reachability but not successful inference.

Update the repository runbook and `AGENTS.md` when paths, behavior, model-set
state, or recovery guidance changed. Run relevant tests, inspect service logs,
commit independently recoverable source or documentation changes, push them,
and remove only confirmed temporary files.
