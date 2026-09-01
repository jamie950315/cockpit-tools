# Codex Mixed Routing with a Five-Account OAuth Pool and CLIProxyAPI

This guide describes a sanitized deployment pattern for Cockpit's existing mixed-model routing. It does not contain credentials or machine-specific account identifiers.

## Goal

Keep Codex authenticated with ChatGPT OAuth while exposing two request paths through one Cockpit local endpoint:

- Unprefixed official models use a pool of five TEAM OAuth credential records.
- Models prefixed with `cliproxy/` use a separate CLIProxyAPI provider.

The CLIProxyAPI account must not be added to the OAuth pool. A model catalog entry alone is insufficient; the matching model route must be present in the local-access configuration and generated sidecar manifest.

## Required routing shape

The default local-access key must inherit the OAuth account pool. Its logical routing configuration is:

```json
{
  "inheritAccountPool": true,
  "modelRouting": {
    "defaultRoute": "oauth",
    "failurePolicy": "strict",
    "routes": [
      {
        "id": "route-cliproxyapi",
        "namespace": "cliproxy",
        "providerAccountId": "CURRENT_CLIPROXYAPI_ACCOUNT_ID",
        "providerGateway": "CURRENT_PROVIDER_GATEWAY_OBJECT"
      }
    ]
  }
}
```

Discover the current provider account and gateway from Cockpit at configuration time. Do not copy account IDs, API-key IDs, provider manifest directories, ports, or secrets from another installation.

`failurePolicy = "strict"` is intentional. If the namespaced provider is unavailable, the request must fail instead of silently consuming an OAuth account or reaching a different provider.

## Account-selection semantics

Five OAuth records in the manifest prove that five credentials are configured;
they do not prove five distinct ChatGPT login identities, five independent quota
sources, or successful use of every credential.

Cockpit's `auto` strategy is not round-robin. It prefers eligible credentials by
plan rank and remaining quota, while cooldown, quota reserve, model restrictions,
preferred/backup rules, and health can remove or reorder candidates. Session
affinity keeps an existing conversation on its selected credential. Use `random`
only when deliberate distribution between new conversations is desired; it still
does not override session affinity for an existing conversation.

The live upstream 1.3.35 installation verified on 2026-09-01 used `auto` with
session affinity enabled and one backup credential. Ten successful official
requests with distinct session IDs all selected one credential. Mixed routing
worked, but five-credential round-robin did not.

## Private runtime data

On a default macOS installation, Cockpit runtime state is normally stored below `~/.antigravity_cockpit`, and the Codex client configuration and generated catalog are normally stored below `~/.codex`.

These files may contain secrets and must never be committed, pasted into an issue, or printed in CI logs. Back them up with owner-only permissions before making changes.

Cockpit owns the generated Codex model catalog. Do not fix routing by editing that generated file. Configure the route and its model input through the current Cockpit UI or supported configuration API, then allow Cockpit to regenerate the catalog.

## Invariants

After Cockpit regenerates its sidecar state, verify all of the following without printing credentials:

```bash
manifest="$HOME/.antigravity_cockpit/codex_local_access_sidecar/manifest.json"

jq -e '
  ([.accounts[] | select(.authKind == "oauth")] | length) == 5
  and .apiKeys[0].modelRouting.defaultRoute == "oauth"
  and .apiKeys[0].modelRouting.failurePolicy == "strict"
  and .apiKeys[0].modelRouting.routes[0].namespace == "cliproxy"
' "$manifest" >/dev/null
```

The historical successful deployment exposed official models together with 60 `cliproxy/*` models. Model totals are catalog-dependent and must not be hard-coded as a permanent invariant.

Codex must continue using Cockpit's local OpenAI-compatible endpoint while retaining ChatGPT authentication. Confirm the active installation with:

```bash
codex login status
```

The expected status is `Logged in using ChatGPT`.

## End-to-end verification

Use the local API key only in a private shell variable. Never print it. Send one real non-streaming request through each route:

1. An unprefixed official model, such as `gpt-5.6-luna`.
2. A namespaced provider model, such as `cliproxy/grok-4.3`.

Both requests must return HTTP 200 and a valid answer. Inspect Cockpit's local logs to prove that the official request selected the OAuth pool and the namespaced request selected CLIProxyAPI. HTTP success by itself does not prove that the correct provider was used. One successful official request validates the route, not every credential in the pool.

To claim that all five credentials work, deliberately select and test each one
with a real request, then confirm five anonymous credential slots in the request
log. Requests intended to test distribution must use distinct `Session-Id`
headers. Do not print credential IDs, emails, account IDs, tokens, or API keys,
and restore the original selection strategy and backup rules after the test.

Also test the namespaced model through Codex itself:

```bash
codex exec --model cliproxy/grok-4.3 \
  'What is the capital of France? Reply with only the answer.'
```

Restart Cockpit and repeat the two-route probes. Finally, reopen the Codex model selector and confirm that both official and `cliproxy/*` models are visible and selectable.

## Update safety

An official Cockpit update can replace a custom build. After every update:

1. Confirm the running binary still contains mixed-routing support.
2. Confirm the generated manifest still contains the OAuth default route and `cliproxy` namespace.
3. Repeat both real request probes and inspect route logs. Do not call the pool
   round-robin unless a distinct-session test demonstrates actual distribution.
4. Keep the previous known-good app and routing-state backup until verification finishes.

If a future official binary supports this routing pattern and passes the same live checks, prefer the official binary over a custom build.
