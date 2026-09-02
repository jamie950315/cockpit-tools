# Cockpit Tools Custom Build and Mixed Routing Runbook

This is the recovery and upgrade runbook for the custom Cockpit Tools build used by Codex. Machine-specific signing identities remain in `~/.codex/LOCAL.md`; never copy them, API keys, OAuth tokens, account IDs, generated catalogs, or runtime stores into Git.

## Purpose and known-good architecture

Required behavior:

- Codex remains signed in with ChatGPT OAuth (`codex login status` reports `Logged in using ChatGPT`).
- Unprefixed official models use the pool of five TEAM OAuth credential records.
- Models under the `cliproxy/` namespace use the CLIProxyAPI provider on Pi5.
- Both groups appear in the Codex model selector and can be switched at any time.
- The default route is `oauth`; the `cliproxy` route uses `failurePolicy = "strict"` so it never silently falls back to the wrong provider.
- The CLIProxyAPI API-key account remains outside the OAuth pool. Its models are
  visible because the `cliproxy` model route references its provider gateway and
  upstream model list, not because the account joins the pool.

Known-good state verified on 2026-09-01 after replacing the custom build with
the upstream release:

- Installed app: `/Applications/Cockpit Tools.app`, upstream version 1.3.35.
- Upstream artifact: official arm64 DMG with its published SHA-256 verified.
- The upstream 1.3.35 macOS artifact is ad-hoc signed. It launches on this Mac,
  but it does not satisfy the strict Apple Development signature check used for
  the previous custom build.
- Original app backup: `/Applications/Cockpit Tools 1.3.34 pre-mixed-routing 20260901.app`.
- Known-good custom mixed-routing backup:
  `/Applications/Cockpit Tools 1.3.34 custom mixed-routing 20260901-231043.app`.
- Immediate pre-upgrade backup:
  `/Applications/Cockpit Tools 1.3.34 pre-original-1.3.35 20260901-231241.app`.
- Five distinct TEAM OAuth credential records in the pool. These records are not
  proof of five distinct ChatGPT login identities or five independently tested
  quota sources.
- `routingStrategy = "auto"`; auto prefers the highest-ranked eligible account
  by plan and remaining quota instead of distributing requests evenly.
- Session affinity is enabled with a one-hour TTL, so the same conversation is
  expected to stay on its selected account.
- One credential is marked as a backup and is used only when regular eligible
  credentials cannot serve the request.
- `modelRouting.defaultRoute = "oauth"`.
- `modelRouting.failurePolicy = "strict"`.
- Route namespace: `cliproxy`.
- Historical manifest count: 69 model IDs, including 60 `cliproxy/*` IDs.
- Historical Codex selector count: 68 models, consisting of 8 official models and 60 `cliproxy/*` models. Counts may change as catalogs change; the presence and function of both groups is authoritative.
- The upstream 1.3.35 sidecar was verified live with official OAuth requests and
  `cliproxy/*` CLIProxyAPI requests, all HTTP 200. Ten official requests carrying
  distinct session IDs all selected one OAuth credential. This proves the
  official route works, but disproves round-robin behavior in the current `auto`
  configuration and does not individually validate all five credentials. The
  live selector catalog contained 10 official and 60 namespaced models at
  verification time.

Mac upgrade state verified on 2026-09-02:

- `/Applications/Cockpit Tools.app` is now upstream version 1.3.36 arm64.
- The first 1.3.36 launch ran takeover restoration while the new setting was
  still enabled and changed `model_catalog_json` from the user-owned 500K
  catalog to `cockpit-model-catalog.json`. Disabling the switch afterward could
  not undo that already-completed write.
- On this migrated configuration, the UI switch appeared disabled but did not
  serialize `codex_auto_restore_takeover_on_launch` into Cockpit's existing
  config. A missing field continued to behave as enabled at the next launch.
  Set the field explicitly to `false`, restore
  `model_catalog_json = "user-mixed-routing-model-catalog.json"`, and confirm
  both survive a user-performed relaunch.
- After that relaunch, Codex resolved 69 models and every entry used context
  500000, compact 450000, and effective percent 100. Real
  `gpt-5.6-luna` and `cliproxy/grok-4.3` requests both returned HTTP 200; the
  request records showed the official request selected an OAuth account while
  the namespaced request did not use the OAuth pool.
- Do not quit Cockpit remotely during validation when the current Codex task
  depends on its sidecar. Ask the user to relaunch it and wait for port 57204.

## CTPS Windows replica

Known-good state verified on 2026-09-02:

- Host: CTPS, Windows 11 x64 with an interactive desktop session.
- Installed app: official Cockpit Tools 1.3.36 x64 at
  `%LOCALAPPDATA%\Cockpit Tools\cockpit-tools.exe`.
- Installed Codex CLI: 0.152.1.
- Pre-migration state is retained under
  `%USERPROFILE%\.cockpit-migration-backups\20260902-175346-before-cockpit`.
- The Cockpit encryption keys, five current OAuth credential details, one
  CLIProxyAPI provider detail, routing collection, provider collection, and
  fingerprint were copied from the Mac over encrypted SSH. Historical account
  backups and the Mac `auth.json` were deliberately excluded.
- The generated manifest contains five OAuth records, `defaultRoute = "oauth"`,
  `failurePolicy = "strict"`, and a `cliproxy` route with 60 upstream models.
- `%USERPROFILE%\.codex\user-mixed-routing-model-catalog.json` is byte-identical
  to the Mac file. Its 69 entries all use context 500000, compact 450000, and
  effective percent 100. The sidecar currently advertises one additional
  official `gpt-5.3-codex` model that is intentionally absent from both copies
  of the static catalog; do not add it only to Windows if exact Mac parity is
  required.
- `%USERPROFILE%\.codex\config.toml` selects `codex_local_access` and the
  user-owned catalog using Windows paths. Mac-only paths and MCP configuration
  were not copied.
- `codex_auto_restore_takeover_on_launch` is disabled. Cockpit Tools 1.3.36 can
  otherwise replace the user-owned `model_catalog_json` reference with its
  managed catalog when it restores takeover at launch.
- After stopping and relaunching Cockpit in interactive Session 1, both a real
  `gpt-5.6-luna` Responses request and a real `cliproxy/grok-4.3` Responses
  request returned HTTP 200 with the expected answer. The request database
  recorded both as successful sidecar requests. Only one OAuth record was
  anonymously observed serving the official checks, so this does not prove all
  five credentials independently work.

Cockpit must run in the interactive Windows desktop session. A process started
directly by SSH runs in Session 0 and exits. For an attended launch, start
Cockpit from the Windows desktop or Start menu. A temporary Scheduled Task may
be used to launch it in the logged-in session during remote recovery, but remove
that task after the app and sidecar are running.

The existing Windows Codex CLI ChatGPT login currently reports that a refresh
token was reused. `codex login status` can still say `Logged in using ChatGPT`
when that cached login can no longer refresh. This is separate from the five
Cockpit OAuth records: both official and namespaced models still work through
`codex_local_access`, although the CLI logs repeated 401 authentication errors
for native account services.

Do not copy the Mac `~/.codex/auth.json` to Windows. Sharing one rotating
refresh token between hosts can make either copy stale. If Windows needs native
Codex account features, use the official independent login flow:

```powershell
codex logout
codex login --device-auth
codex login status
```

The user must complete the browser/device authorization. Repeat one official
and one `cliproxy/*` end-to-end request afterward and confirm the
`refresh_token_reused` error is gone. The official Codex CLI reference documents
`--device-auth` as the device-code alternative to opening a browser directly:
<https://developers.openai.com/codex/cli/reference>.

## Root cause and what was actually patched

The official Cockpit Tools 1.3.34 release binary did not contain the newer mixed-routing implementation, although the then-current upstream source contained `modelRouting`. Editing the generated Codex model catalog did not solve the problem because Cockpit owns and rewrites that file, and a catalog row does not create a working request route.

The mixed-routing feature was not injected by hex-editing the compiled executable. The successful solution was:

1. Build current Cockpit source that already contains `modelRouting`.
2. Patch only the macOS build glue when necessary so Xcode 27 / Swift 6.4 can link the Swift static library.
3. Sign and install the rebuilt app.
4. Configure Cockpit's model-routing data and verify both real request paths.

The current fork preserves the work on three branches:

- `xcode27patch`: only the Xcode 27 / Swift 6.4 linker compatibility change.
- `cliproxy`: mixed-model routing and the five-account OAuth/CLIProxyAPI deployment guide.
- `main`: both sets of changes.

## Before rebuilding after a future update

Do not immediately overwrite the installed app or edit Codex's generated catalog.

1. Inspect the installed binary and live state:

```bash
installed_app='/Applications/Cockpit Tools.app'
/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$installed_app/Contents/Info.plist"
codesign --verify --deep --strict --verbose=2 "$installed_app"
strings "$installed_app/Contents/MacOS/cockpit-cliproxy" | rg 'model_route_not_available|modelRouting|defaultRoute'
jq '{oauthCredentials:([.accounts[]|select(.authKind=="oauth")]|length),routingStrategy,defaultRoute:.apiKeys[0].modelRouting.defaultRoute,failurePolicy:.apiKeys[0].modelRouting.failurePolicy,namespace:.apiKeys[0].modelRouting.routes[0].namespace,modelIds:(.modelIds|length),cliproxyModels:([.modelIds[]|select(startswith("cliproxy/"))]|length)}' "$HOME/.antigravity_cockpit/codex_local_access_sidecar/manifest.json"
jq '{sessionAffinity:.routing["session-affinity"],strategy:.routing.strategy}' "$HOME/.antigravity_cockpit/codex_local_access_sidecar/config.json"
codex login status
```

2. If a new official binary already supports mixed routing and passes the complete live verification below, keep the official binary. A custom build is unnecessary in that case.
3. If the official binary lacks mixed routing but upstream source contains it, rebuild from source.
4. If upstream source no longer contains `modelRouting`, investigate the new routing design instead of blindly applying this build-only patch.

## Clone and inspect the source

Fork:

`https://github.com/jamie950315/cockpit-tools.git`

Upstream:

`https://github.com/jlcodes99/cockpit-tools.git`

Use the durable checkout at `~/cockpit-tools`, record the exact revision used, and refresh both remotes:

```bash
cockpit_repo="$HOME/cockpit-tools"
git -C "$cockpit_repo" fetch origin
git -C "$cockpit_repo" fetch upstream
git -C "$cockpit_repo" status --short
git -C "$cockpit_repo" rev-parse HEAD
rg -n 'modelRouting|model_routing|model_route_not_available' "$cockpit_repo/src" "$cockpit_repo/src-tauri" "$cockpit_repo/sidecars"
```

Read `AGENTS.md` and current build documentation before changing files. Preserve the exact upstream commit in a durable branch or work report.

## Xcode 27 / Swift 6.4 source patch

Symptom requiring this patch: the Rust/Tauri link step cannot find `MacosNativeMenuSwift`, while the library exists below a path ending in `out/Products/Debug` or `out/Products/Release`.

Confirm first:

```bash
find "$cockpit_repo" -path '*MacosNativeMenuSwift*' -name 'libMacosNativeMenuSwift.a' -print
rg -n 'out/Products|link_xcode_27_swift_package_products' "$cockpit_repo/src-tauri/build.rs"
```

If upstream already contains an equivalent linker search path, do not apply the patch twice. Otherwise update `src-tauri/build.rs` with this change:

```diff
@@
 #[cfg(target_os = "macos")]
 fn link_macos_swift_runtime_rpaths() {
     println!("cargo:rustc-link-arg=-Wl,-rpath,/usr/lib/swift");
 }
+
+#[cfg(target_os = "macos")]
+fn link_xcode_27_swift_package_products(package_name: &str) {
+    let configuration = if std::env::var("DEBUG").ok().as_deref() == Some("true") {
+        "Debug"
+    } else {
+        "Release"
+    };
+    let products_dir = PathBuf::from(
+        std::env::var("OUT_DIR").expect("OUT_DIR is required for Swift package linking"),
+    )
+    .join("swift-rs")
+    .join(package_name)
+    .join("out")
+    .join("Products")
+    .join(configuration);
+    println!("cargo:rustc-link-search=native={}", products_dir.display());
+}
@@
         SwiftLinker::new("12.0")
             .with_package("MacosNativeMenuSwift", "native/macos-native-menu")
             .link();
+        // Swift 6.4 / Xcode 27 places static package products under
+        // out/Products/{Debug,Release}; swift-rs 1.0.7 still advertises the
+        // pre-Xcode-27 triple/configuration directory.
+        link_xcode_27_swift_package_products("MacosNativeMenuSwift");
         link_macos_swift_runtime_rpaths();
```

Run `git diff --check` and inspect the diff before building. If future upstream refactors `build.rs`, port the intent—adding the actual Swift product directory to Cargo's native link search path—rather than forcing the old context.

## Test and build

Install dependencies and run all relevant suites. `rtk` may be used as a transparent command wrapper when available; it is not required by Cockpit itself.

```bash
cd "$cockpit_repo"
npm ci
(cd sidecars/cockpit-cliproxy && go test ./...)
npm run test:codex-api-key-scope
npm run build

SDKROOT=$(xcrun --sdk macosx --show-sdk-path) \
  env -u NVM_BIN -u NVM_DIR -u FNM_DIR -u FNM_MULTISHELL_PATH -u ASDF_DATA_DIR \
  cargo test --manifest-path src-tauri/Cargo.toml -j 1 -- --test-threads=1

SDKROOT=$(xcrun --sdk macosx --show-sdk-path) \
  npm run tauri -- build --bundles app --target aarch64-apple-darwin
```

The app is expected at:

`$cockpit_repo/target/aarch64-apple-darwin/release/bundle/macos/Cockpit Tools.app`

Historical successful results were 1006 Rust tests passed with 2 ignored, 151 Go tests passed, 5 frontend tests passed, plus successful typecheck and production build. Future totals may differ; zero unexpected failures is required.

Confirm the rebuilt app contains mixed-routing code before installation:

```bash
built_app="$cockpit_repo/target/aarch64-apple-darwin/release/bundle/macos/Cockpit Tools.app"
strings "$built_app/Contents/MacOS/cockpit-cliproxy" | rg 'model_route_not_available|modelRouting|defaultRoute'
file "$built_app/Contents/MacOS/cockpit-tools" "$built_app/Contents/MacOS/cockpit-cliproxy"
```

## Sign the custom app

Re-check the valid signing identity with `security find-identity -v -p codesigning`. Use the Apple Development identity documented in `~/.codex/LOCAL.md`; do not infer the Xcode team from the identifier shown in parentheses in the certificate name.

Quit Cockpit and ensure its app and sidecar processes have exited. Then sign the embedded sidecar first and the app bundle second:

```bash
sign_identity='<Apple Development identity from ~/.codex/LOCAL.md>'
built_app="$cockpit_repo/target/aarch64-apple-darwin/release/bundle/macos/Cockpit Tools.app"

codesign --force --options runtime --timestamp=none --sign "$sign_identity" \
  "$built_app/Contents/MacOS/cockpit-cliproxy"
codesign --force --deep --options runtime --timestamp=none --sign "$sign_identity" \
  "$built_app"
codesign --verify --deep --strict --verbose=2 "$built_app"
codesign -dvv "$built_app" 2>&1 | rg 'Identifier|Authority|TeamIdentifier|Runtime Version'
```

This is a locally Apple Development-signed build, not a notarized public release. `codesign --verify --deep --strict` and the expected TeamIdentifier are required.

## Back up and install safely

Never delete or overwrite the current app without a versioned backup. Resolve every path explicitly and abort if the backup target already exists.

```bash
installed_app='/Applications/Cockpit Tools.app'
built_app="$cockpit_repo/target/aarch64-apple-darwin/release/bundle/macos/Cockpit Tools.app"
installed_version=$(/usr/libexec/PlistBuddy -c 'Print :CFBundleShortVersionString' "$installed_app/Contents/Info.plist")
backup_stamp=$(date '+%Y%m%d-%H%M%S')
backup_app="/Applications/Cockpit Tools ${installed_version} pre-custom ${backup_stamp}.app"

test ! -e "$backup_app"
test -d "$installed_app"
test -d "$built_app"
mv "$installed_app" "$backup_app"
ditto "$built_app" "$installed_app"
codesign --verify --deep --strict --verbose=2 "$installed_app"
strings "$installed_app/Contents/MacOS/cockpit-cliproxy" | rg -q 'model_route_not_available'
```

Also back up the routing state before changing it. The files can contain secrets, so keep permissions restrictive and never print or commit their raw contents:

```bash
backup_stamp=$(date '+%Y%m%d-%H%M%S')
cockpit_backup="$HOME/.antigravity_cockpit/backups/manual/${backup_stamp}-before-mixed-routing"
mkdir -p "$cockpit_backup"
chmod 700 "$cockpit_backup"
cp -p "$HOME/.antigravity_cockpit/codex_local_access.json" "$cockpit_backup/"
cp -p "$HOME/.antigravity_cockpit/codex_instances.json" "$cockpit_backup/"
cp -p "$HOME/.codex/config.toml" "$cockpit_backup/"
cp -p "$HOME/.codex/.cockpit-experimental-model-catalog-config.json" "$cockpit_backup/" 2>/dev/null || true
cp -p "$HOME/.codex/cockpit-model-catalog.json" "$cockpit_backup/" 2>/dev/null || true
chmod 600 "$cockpit_backup"/*
```

## Restore mixed-routing configuration

Prefer Cockpit's current UI or supported configuration API if it exposes mixed routing. Do not hard-code old account IDs, API-key IDs, gateway hash directories, ports, or model counts after an update; discover them from the current state.

The required logical configuration for the default local-access key is:

```json
{
  "inheritAccountPool": true,
  "modelRouting": {
    "defaultRoute": "oauth",
    "failurePolicy": "strict",
    "routes": [
      {
        "id": "route-cliproxyapi-pi5",
        "namespace": "cliproxy",
        "providerAccountId": "CURRENT_CLIPROXYAPI_ACCOUNT_ID",
        "providerGateway": "COPY_THE_CURRENT_PROVIDER_GATEWAY_OBJECT_WITHOUT_LOGGING_ITS_SECRET"
      }
    ]
  }
}
```

Rules:

- The top-level OAuth account pool contains exactly five distinct TEAM OAuth
  credential records. Do not infer distinct login identities from the record
  count.
- The CLIProxyAPI API-key account is excluded from that OAuth pool.
- The default key inherits the OAuth pool.
- Official models have no namespace and therefore use `oauth`.
- CLIProxyAPI upstream models are exposed with the `cliproxy/` prefix and route only through the matching current provider account.
- Pool membership and model visibility are independent. The OAuth pool controls
  which credentials may serve the default OAuth route. The active API key's
  `modelRouting.routes[].providerGateway.upstreamModels` controls which
  namespaced provider models the sidecar advertises to Codex.
- The sidecar adds `<namespace>/` to every configured upstream model when it
  builds the authenticated `/v1/models` response. Selecting one of those models
  resolves the matching route, strips exactly one namespace prefix, and sends the
  remaining upstream model ID to CLIProxyAPI.
- Disabling or deleting the `cliproxy` route, removing its provider gateway, or
  emptying its upstream model list removes those models from the API key's visible
  catalog. The UI action that adds an account to the API Service pool is not the
  visibility control for namespaced routes.
- Copy the provider gateway object from the current CLIProxyAPI provider manifest without printing its API key. Never store that object in this file, Git, memory, logs, or chat.
- Cockpit owns `~/.codex/cockpit-model-catalog.json`; never treat a manual edit to that generated file as the fix.
- If the current Cockpit source still uses `~/.codex/.cockpit-experimental-model-catalog-config.json` as model input, populate it with the current official models plus unique `cliproxy/<upstream-id>` entries, then let Cockpit regenerate the managed catalog. Do not require the historical count of 68.

The persistent collection is currently located at:

`~/.antigravity_cockpit/codex_local_access.json`

The generated sidecar manifest is currently located at:

`~/.antigravity_cockpit/codex_local_access_sidecar/manifest.json`

Codex must continue pointing to Cockpit's local endpoint in `~/.codex/config.toml`:

```toml
base_url = "http://localhost:57204/v1"
```

The current upstream 1.3.35 installation uses a user-owned static catalog that
deliberately forces every listed model to context 500000, compact 450000, and
effective percent 100. This may overstate the upstream limit of smaller models;
an upstream rejection near the end of a long thread is an accepted tradeoff.

`~/.codex/config.toml` points `model_catalog_json` at
`~/.codex/user-mixed-routing-model-catalog.json`. This preserves the original
app binary and does not affect route selection. It also means Cockpit's dynamic
model visibility updates do not automatically enter the static catalog; after
the upstream or CLIProxyAPI model set changes, regenerate the catalog and repeat
both live route checks. The previous per-model catalog is backed up as
`~/.codex/user-mixed-routing-model-catalog.before-global-500k-20260902.json`.

Do not replace ChatGPT OAuth with a CLIProxyAPI login. `codex login status` must remain `Logged in using ChatGPT`.

## Complete live verification

Start Cockpit and wait for port 57204. Verify persisted structure without exposing the local key:

```bash
open -a '/Applications/Cockpit Tools.app'
lsof -nP -iTCP:57204 -sTCP:LISTEN

jq -e '.apiKeys[0].modelRouting.defaultRoute=="oauth"
  and .apiKeys[0].modelRouting.failurePolicy=="strict"
  and .apiKeys[0].modelRouting.routes[0].namespace=="cliproxy"
  and (.apiKeys[0].modelRouting.routes[0].providerGateway.upstreamModels|length)>0
  and .routingStrategy=="auto"
  and ([.accounts[]|select(.authKind=="oauth")]|length)==5' \
  "$HOME/.antigravity_cockpit/codex_local_access_sidecar/manifest.json" >/dev/null

jq -e '.routing["session-affinity"]==true' \
  "$HOME/.antigravity_cockpit/codex_local_access_sidecar/config.json" >/dev/null

rg -q '^base_url = "http://localhost:57204/v1"$' "$HOME/.codex/config.toml"
codex login status
codesign --verify --deep --strict --verbose=2 '/Applications/Cockpit Tools.app'
```

Test both routes with real non-streaming requests. Read the local key into a shell variable, but never print it:

```bash
collection="$HOME/.antigravity_cockpit/codex_local_access.json"
local_key=$(jq -r '.apiKeys[0].key' "$collection")

official_response=$(mktemp)
official_code=$(curl -sS --max-time 180 -o "$official_response" -w '%{http_code}' \
  -H "Authorization: Bearer $local_key" \
  -H 'Content-Type: application/json' \
  --data-binary '{"model":"gpt-5.6-luna","input":"What is the capital of France? Reply with only the answer.","stream":false}' \
  http://127.0.0.1:57204/v1/responses)

cliproxy_response=$(mktemp)
cliproxy_code=$(curl -sS --max-time 180 -o "$cliproxy_response" -w '%{http_code}' \
  -H "Authorization: Bearer $local_key" \
  -H 'Content-Type: application/json' \
  --data-binary '{"model":"cliproxy/grok-4.3","input":"What is the capital of France? Reply with only the answer.","stream":false}' \
  http://127.0.0.1:57204/v1/responses)

official_reply=$(jq -r '[.output[]?.content[]? | select(.type=="output_text") | .text] | join("")' "$official_response")
cliproxy_reply=$(jq -r '[.output[]?.content[]? | select(.type=="output_text") | .text] | join("")' "$cliproxy_response")

test "$official_code" = '200'
test "$cliproxy_code" = '200'
printf '%s' "$official_reply" | rg -qi 'Paris|巴黎'
printf '%s' "$cliproxy_reply" | rg -qi 'Paris|巴黎'
```

Accept any response containing `Paris` or `巴黎`; do not require exact equality.
Inspect Cockpit logs to prove that the official request used the OAuth pool and
the namespaced request used Pi5. An HTTP 200 alone does not prove correct
routing. One successful official request proves only that the pool route works;
it does not prove that every OAuth credential was selected or can complete the
request.

When diagnosing distribution, send requests with distinct `Session-Id` headers
and count distinct selected account IDs in Cockpit's request log without printing
the IDs. Under `auto`, repeated use of one healthy high-ranked credential is
expected. A five-credential validation is complete only when each intended
credential is deliberately selected, returns a successful real response, and is
identified anonymously in the logs. Restore the original routing strategy and
backup rules after any controlled per-credential test.

Then verify Codex end to end:

```bash
codex exec --model cliproxy/grok-4.3 \
  'What is the capital of France? Reply with only the answer.'
```

Finally restart Cockpit once more and repeat the structure and two-route probes. Reopen the Codex app and visually confirm that both official and `cliproxy/*` models are present and selectable. A build, model count, or catalog file alone is not completion.

## Rollback

If the custom build fails, quit Cockpit, move the failed `/Applications/Cockpit Tools.app` aside to a uniquely named diagnostic backup, restore the most recent known-good `.app` backup with `ditto`, verify its signature, and restore the matching restricted-permission routing backup. Never delete the failed or previous app until the restored version launches and its expected route has been tested.

## Future update warning

Cockpit auto-update can replace this custom build. If Codex suddenly shows only default models:

1. Check the running Cockpit version, signature, and mixed-routing marker.
2. Check whether the sidecar manifest still contains `modelRouting`.
3. Check whether the five OAuth accounts and `cliproxy` namespace remain intact.
4. Test both routes and inspect logs.
5. Rebuild only if the official binary still lacks the feature.

Do not start by rewriting `~/.codex/cockpit-model-catalog.json`, changing `~/.codex/config.toml`, re-importing accounts, or replacing ChatGPT OAuth.

## Pi5 CLIProxyAPI automatic updates

The Pi5 deployment checks the upstream stable GitHub release once per day using
`cliproxyapi-auto-update.timer`. The updater is stored at
`/home/jamie/docker/cli-proxy-api/auto-update.sh`; its maintained source is in
`ops/cliproxyapi/`.

The updater resolves each stable release to an immutable container digest,
recreates the service, and checks the runtime version, model catalog, five TEAM
auth files, and five real Responses requests. Any failed check restores the
previous digest. The API key is read into a mode-0600 temporary curl config and
is never printed or placed in a process argument.

```bash
systemctl status cliproxyapi-auto-update.timer
systemctl status cliproxyapi-auto-update.service
journalctl -u cliproxyapi-auto-update.service --since today
/home/jamie/docker/cli-proxy-api/auto-update.sh --check-only
```
