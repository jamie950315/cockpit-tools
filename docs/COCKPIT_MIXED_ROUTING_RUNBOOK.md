# Cockpit Tools Custom Build and Mixed Routing Runbook

This is the recovery and upgrade runbook for the custom Cockpit Tools build used by Codex. Machine-specific signing identities remain in `~/.codex/LOCAL.md`; never copy them, API keys, OAuth tokens, account IDs, generated catalogs, or runtime stores into Git.

## Purpose and known-good architecture

Required behavior:

- Codex remains signed in with ChatGPT OAuth (`codex login status` reports `Logged in using ChatGPT`).
- Unprefixed official models use the pool of five TEAM OAuth credential records.
- Models under the case-sensitive `CPA/` namespace use the CLIProxyAPI provider on Pi5.
- Both groups appear in the Codex model selector and can be switched at any time.
- The default route is `oauth`; the `CPA` route uses `failurePolicy = "strict"` so it never silently falls back to the wrong provider.
- The CLIProxyAPI API-key account remains outside the OAuth pool. Its models are
  visible because the `CPA` model route references its provider gateway and
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
- Historical route namespace: `cliproxy` (renamed to `CPA` on 2026-09-02).
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
  Set the field explicitly to `false`.
- That switch applies only when Cockpit itself starts. Launching or reactivating
  Codex through Cockpit's API Service action is a separate takeover path and
  correctly changes the catalog reference to `cockpit-model-catalog.json`.
  Keep using this path because it also injects the five-account OAuth and
  CLIProxyAPI configuration. A task keeps the context snapshot it had when
  created.
- The durable 500K solution now uses the managed catalog rather than an
  external static catalog. Set every entry in
  `.cockpit-experimental-model-catalog-config.json` to context 526316 and compact
  450000. The generated catalog retains Codex's default effective percentage of
  95, so a new task receives exactly 500000 usable tokens after integer
  rounding. A real `gpt-5.6-sol` CLI task confirmed `model_context_window =
  500000` and was removed after verification.
- Real
  `gpt-5.6-luna` and `CPA/grok-4.3` requests both returned HTTP 200 after the
  namespace migration; the
  request records showed the official request selected an OAuth account while
  the namespaced request did not use the OAuth pool.
- The live route store and manifest now contain exactly one uppercase namespace,
  `CPA`, and expose 58 `CPA/*` models with no `cliproxy/*` alias. The Mac catalog
  contains 66 models in total. Cockpit 1.3.36
  preserves this value when loading the persisted collection, but its mixed-route
  form normalizes a namespace to lowercase when saving. Stop Cockpit before an
  exact persisted-store repair, restart immediately, and verify both files plus
  both real request paths. Editing or copying the route in the UI requires the
  same recheck.
- The selector label is a separate catalog field from the model ID. Every
  namespaced model uses ID `CPA/<upstream-id>` and display name
  `CPA · <upstream-id>`. The launch-preview editor may report `路由缺失` because
  the special API Service pseudo-instance intentionally has no instance-level
  route. Do not "fix" that badge by copying the API Service route into default
  instance settings.
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
  `failurePolicy = "strict"`, and a `CPA` route with 58 upstream models and no
  old-prefix alias.
- `%USERPROFILE%\.codex\user-mixed-routing-model-catalog.json` contains 67
  entries: 58 `CPA/*` models plus the official models available on that host.
  All entries use context 500000, compact 450000, and effective percent 100.
  Do not force byte-identical total catalogs across hosts because their official
  model sets may differ.
- `%USERPROFILE%\.codex\config.toml` selects `codex_local_access` and the
  user-owned catalog using Windows paths. Mac-only paths and MCP configuration
  were not copied.
- `codex_auto_restore_takeover_on_launch` is disabled. Cockpit Tools 1.3.36 can
  otherwise replace the user-owned `model_catalog_json` reference with its
  managed catalog when it restores takeover at launch.
- After stopping and relaunching Cockpit in interactive Session 1, both a real
  `gpt-5.6-luna` Responses request and a real `CPA/grok-4.3` Responses
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
and one `CPA/*` end-to-end request afterward and confirm the
`refresh_token_reused` error is gone. The official Codex CLI reference documents
`--device-auth` as the device-code alternative to opening a browser directly:
<https://developers.openai.com/codex/cli/reference>.

## RPi SSH-host Codex context

Remote SSH tasks use the remote host's own Codex configuration; the Mac managed
catalog is not inherited. This matches the official remote-connections behavior:
<https://developers.openai.com/codex/remote-connections>.

Known-good state verified on 2026-09-02:

- Provider remains `pi5-api`; do not replace its URL or authentication fields.
- `/home/jamie/.codex/config.toml` sets:

  ```toml
  model_catalog_json = "/home/jamie/.codex/rpi-all-models-500k-catalog.json"
  ```

- The catalog was generated from the 69 models the RPi resolver actually saw,
  including 58 `CPA/*` models.
  Every entry uses context 526316, max context 526316, and compact 450000.
  Codex applies its 95-percent effective factor and records
  `model_context_window = 500000`.
- Fresh real `gpt-5.6-luna` and `CPA/grok-4.6` tasks both returned `OK` and
  recorded a 500000 window.
- The original config is backed up under
  `/home/jamie/.codex/backups/20260902-before-all-models-500k/`.
- Existing tasks keep their creation-time window while their app-server writer
  remains active. The pre-change `更新並驗證 Perplexity 模型` task was upgraded
  in place from 124518 to 500000 by confirming all RPi tasks were idle,
  restarting only the RPi Codex 0.147.0 app-server that owns
  `app-server-control.sock`, and then sending a minimal new turn to the same task
  ID. Its history and project state were preserved; the latest token record and
  reply were 500000 and `CONTEXT-500K-OK`. Do not restart that writer while any
  RPi task is active, and do not edit old rollout token records to fake a larger
  window.
- The RPi native ChatGPT refresh token is invalid and produces login warnings,
  but both `pi5-api` routes still completed. Use an independent device login if
  native account features are required; never copy another host's rotating
  `auth.json`.
- The pre-existing `更新並驗證 Perplexity 模型` task was moved from its saved
  `cliproxy/grok-4.6` name to `CPA/grok-4.6` only after all RPi tasks were idle
  and its app-server was reloaded. A supported model override on a new turn
  preserved the task history and recorded `model_context_window = 500000`.

When the Pi5 model set changes, regenerate the RPi catalog from `codex debug
models`, reapply the three numeric fields to every current entry, and repeat one
official plus one namespaced real task. Never assume the historical count of 71
is fixed.

## PPLX and OpenCode Zen model-list synchronization

Known-good state verified on 2026-09-03:

- The PPLX proxy advertises 23 models.
- Pi5 CLIProxyAPI also serves OpenCode Zen through `openai-compatibility` at
  `https://opencode.ai/zen/v1` with prefix `opencode`. Free models require
  official CLI identification headers, not a browser User-Agent:
  `User-Agent: opencode/<version>`, `x-opencode-client`, `x-opencode-session`,
  `x-opencode-project`, and `x-opencode-request`. Keep `disable-cooling: true`
  and `request-retry: 0` on this provider. Client IDs are
  `opencode/<upstream-id>`; Cockpit IDs are `CPA/opencode/<upstream-id>`.
- `CPA/*` catalogs follow the current CLIProxyAPI set, including OpenCode Zen and
  `CPA/gemini-3.8-flash-high`. Host totals differ because official models differ.
- Mac and RPi use raw context 526316 with Codex's 95-percent factor; CTPS and
  WSL use raw context 500000 with an explicit 100-percent factor. All four
  produce a usable 500000 context and compact at 450000.
- OpenCode paid models require a workspace payment method. OpenCode counts free
  model requests per client IP. If the model's `rateLimit.checkHeader` is absent,
  Zen uses `fallbackValue` instead of the real quota, which can 429 immediately.
  After sending the CLI headers above, `opencode/big-pickle` and
  `CPA/opencode/big-pickle` returned HTTP 200 with `PING` on 2026-09-03. A later
  429 with those headers present is the real IP quota. Do not rotate IPs to evade
  it. Occasional `500 Internal server error` is OpenCode upstream.
- A running Cockpit sidecar keeps the previous mixed-route snapshot in memory.
  Disk updates are not live until the user relaunches Cockpit. Do not quit
  Cockpit from a Codex task that uses the sidecar.
- On CTPS, keep `modelCatalog` as a JSON array. If it becomes `{Count, value}`,
  unwrap it; do not round-trip the store through PowerShell `ConvertTo-Json`.
- After the 2026-09-03 OpenCode refresh, CTPS was safely relaunched in Windows
  interactive Session 1 with no CTPS or WSL requests active. Its live sidecar
  then exposed 125 `CPA/*` models, including 66 `CPA/opencode/*` models, and WSL
  observed the same set through CTPS. Those hosts originally reached
  `CPA/opencode/big-pickle` and received `429 FreeUsageLimitError` instead of a
  missing-route 404, before the CLI header repair. After that repair, Mac
  Cockpit and Pi5 CLIProxyAPI returned HTTP 200 with `PING`. Retest CTPS/WSL if
  they still show the old 429. A real official OAuth request returned HTTP 200.
  CTPS and WSL `codex debug models` retained 500000 context, 100 percent
  effective context, and 450000 compact. The temporary Scheduled Task and
  scripts used for the interactive relaunch were removed after verification.

Refreshing the model list in Cockpit's provider editor is not sufficient in
1.3.36. The existing API key's mixed route embeds its own
`providerGateway.upstreamModels` snapshot, and Cockpit does not refresh that
snapshot when only the provider catalog is saved. Synchronize and verify all of
the following without exposing the provider key or OAuth material:

1. Pi5 CLIProxyAPI `config.yaml` and its authenticated `/v1/models` response.
2. The route snapshot in Cockpit's persistent collection and live manifest.
3. Mac's managed catalog and the static catalogs on CTPS, WSL, and RPi.
4. `codex debug models` and one real new-model request on every target host.

Preserve the uppercase namespace `CPA`. Cockpit 1.3.36 may lowercase it when a
mixed route is saved in the UI, so recheck the persistent collection and live
manifest after any edit. Never assume the API key with `modelRouting` is array
index zero; select the record by the presence of `modelRouting`. Do not rewrite
the credential-bearing Windows store through PowerShell `ConvertTo-Json`, which
can alter or lose route data.

The repository includes a native helper at `tools/CodexModelManager`. Its
manual **同步模型** action compares the Mac CLIProxyAPI provider catalog, the
persisted `CPA` route snapshot, and both Mac Codex catalogs. It adds missing
provider models to the route snapshot and catalogs without deleting models or
editing the live manifest. The app watches those source files only while it is
open and refreshes its difference display automatically. It blocks route writes
while Cockpit is running, makes restricted backups, preserves unknown and
credential fields without displaying them, and requires the user to relaunch
Cockpit and launch Codex through API Service afterward. This helper covers the
local Mac layers only; use the full cross-host workflow for CTPS, WSL, and RPi.
When a refreshed provider catalog removes models, the helper reports the exact
stale route entries but does not delete them automatically.

Codex sends Chat Completions message content as an array of typed text parts.
PPLX proxy commit `f215bde` normalizes `input_text` and `text` parts before
prompt detection; without it, the proxy raises `AttributeError` and the Cockpit
sidecar returns an upstream 503. The fix is covered by the PPLX proxy unit suite
and a real content-array request. Perplexity may still substitute a newly named
model with another model such as GPT-5 Nano; the proxy reports that substitution
in the answer instead of treating the advertised model as unavailable.

## CPA namespace deployment across hosts

Known-good state verified on 2026-09-02:

- The rename is strict and case-sensitive: expose `CPA/*`; do not retain a
  visible `cliproxy/*` alias. Provider names, service names, and the
  `route-cliproxyapi-pi5` internal route ID do not need renaming.
- Mac: the Cockpit collection and live manifest use `CPA`; the manifest exposes
  58 `CPA/*` models and zero old-prefix models. Real `gpt-5.6-luna` and
  `CPA/grok-4.3` Responses requests returned HTTP 200. A real Codex CLI session
  selected `CPA/grok-4.3`, replied successfully, and recorded 500000 context.
  The pre-change files are under
  `~/.antigravity_cockpit/backups/manual/20260902-before-cpa-prefix/`.
- Mac display-name corrections are backed up under
  `~/.codex/backups/20260902-before-cpa-display-name/`. The directory
  `~/.antigravity_cockpit/backups/manual/20260902-before-cpa-display-route-sync/`
  is the known-good pre-incident default-instance state and was restored after
  an attempted route sync broke API Service client launch.
- CTPS Windows: Cockpit and sidecar run in interactive Session 1; the store and
  live manifest use `CPA`, with 58 new-prefix and zero old-prefix models. Both
  real routes returned HTTP 200, and a Codex CLI session using
  `CPA/grok-4.3` recorded 500000 context. The pre-change backup is
  `%USERPROFILE%\.cockpit-migration-backups\20260902-before-cpa-prefix`.
- WSL: provider `ctps_local_access` still points to CTPS. The catalog is
  `/home/jamie/.codex/wsl-cpa-500k-catalog.json`, with 58 new-prefix and zero
  old-prefix models. After reloading Codex 0.143.0 app-server, fresh official
  and `CPA/grok-4.3` CLI sessions both succeeded with 500000 context. The
  pre-change backup is `/home/jamie/.codex/backups/20260902-before-cpa-prefix/`.
- RPi: provider `pi5-api` is unchanged. Its 69-model catalog contains 58
  `CPA/*` entries and no old prefix. After reloading Codex 0.147.0 app-server,
  fresh official and `CPA/grok-4.6` CLI sessions both succeeded with 500000
  context. The pre-existing Perplexity task also accepted a supported model
  override to `CPA/grok-4.6` and recorded 500000 on its latest turn. The
  pre-change backup is `/home/jamie/.codex/backups/20260902-before-cpa-prefix/`.

All active and recovery catalogs must update `display_name` and `description`
alongside `model_id` or `slug`. Keep each host's pre-display-name backup under
its `20260902-before-cpa-display-name` backup directory. A successful request
does not prove the selector label is correct; verify the Mac launch-preview UI
and inspect the active catalog on each remote host.

The default Mac Codex instance must preserve `bindAccountId = "__api_service__"`
and no instance-level `modelRouting`. The API Service launch preview should open
without a missing OAuth-account error. On CTPS, do not create
`codex_instances.json` merely to mirror the local-access route; the erroneous
files from the 2026-09-02 incident are retained only under
`%USERPROFILE%\.cockpit-migration-backups\20260902-erroneous-default-route-sync`
for diagnosis.

If a single-account Cockpit launch replaces API Service takeover, restore all
three layers before declaring recovery:

1. Preserve the default instance's special `__api_service__` binding and keep
   its instance-level `modelRouting` unset.
2. Restore `model_provider = "codex_local_access"`,
   `model_catalog_json = "cockpit-model-catalog.json"`, and provider Base URL
   `http://localhost:57204/v1`; restore the 526316/450000 managed catalog with
   `CPA · <upstream-id>` display names.
3. Open the API Service launch preview and confirm it has no missing-account
   error, then let the user press its final launch button. This last action is
   required to replace the single OAuth token with Cockpit's local client key
   and restarts Codex, so the repairing task must not press it itself.

Before that restart, a safe client test may temporarily supply the local key
through a one-process provider `env_key` override. Verify one official and one
`CPA/*` request plus 500000 context without logging the key. Repeated 401 rows
with blank model IDs in the sidecar request log mean Codex is still sending the
single-account OAuth token and the final API Service launch has not run.

The current 1.3.36 UI lowercases a namespace when its mixed-route form is
saved, even though startup accepts the persisted uppercase value. Do not edit
or copy this route without immediately checking the persisted collection, live
manifest, model list, and both real routes. If a task still holds an old model
name, confirm all tasks on that host are idle, reload only that host's Codex
app-server, then send a new turn with the supported `CPA/<model>` override. Do
not rewrite rollout history.

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
jq '{oauthCredentials:([.accounts[]|select(.authKind=="oauth")]|length),routingStrategy,defaultRoute:.apiKeys[0].modelRouting.defaultRoute,failurePolicy:.apiKeys[0].modelRouting.failurePolicy,namespace:.apiKeys[0].modelRouting.routes[0].namespace,modelIds:(.modelIds|length),cpaModels:([.modelIds[]|select(startswith("CPA/"))]|length),oldPrefixModels:([.modelIds[]|select(startswith("cliproxy/"))]|length)}' "$HOME/.antigravity_cockpit/codex_local_access_sidecar/manifest.json"
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
        "namespace": "CPA",
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
- CLIProxyAPI upstream models are exposed with the `CPA/` prefix and route only through the matching current provider account.
- Pool membership and model visibility are independent. The OAuth pool controls
  which credentials may serve the default OAuth route. The active API key's
  `modelRouting.routes[].providerGateway.upstreamModels` controls which
  namespaced provider models the sidecar advertises to Codex.
- The sidecar adds `<namespace>/` to every configured upstream model when it
  builds the authenticated `/v1/models` response. Selecting one of those models
  resolves the matching route, strips exactly one namespace prefix, and sends the
  remaining upstream model ID to CLIProxyAPI.
- Disabling or deleting the `CPA` route, removing its provider gateway, or
  emptying its upstream model list removes those models from the API key's visible
  catalog. The UI action that adds an account to the API Service pool is not the
  visibility control for namespaced routes.
- Copy the provider gateway object from the current CLIProxyAPI provider manifest without printing its API key. Never store that object in this file, Git, memory, logs, or chat.
- Cockpit owns `~/.codex/cockpit-model-catalog.json`; never treat a manual edit to that generated file as the fix.
- If the current Cockpit source still uses `~/.codex/.cockpit-experimental-model-catalog-config.json` as model input, populate it with the current official models plus unique `CPA/<upstream-id>` entries, then let Cockpit regenerate the managed catalog. Do not require the historical count of 68.

The persistent collection is currently located at:

`~/.antigravity_cockpit/codex_local_access.json`

The generated sidecar manifest is currently located at:

`~/.antigravity_cockpit/codex_local_access_sidecar/manifest.json`

Codex must continue pointing to Cockpit's local endpoint in `~/.codex/config.toml`:

```toml
base_url = "http://localhost:57204/v1"
```

The current upstream 1.3.36 Mac installation uses Cockpit's managed catalog.
`~/.codex/config.toml` points `model_catalog_json` at
`cockpit-model-catalog.json`; do not replace it with the historical external
catalog. Every model definition in
`~/.codex/.cockpit-experimental-model-catalog-config.json` uses context 526316
and compact 450000. Codex applies its default 95-percent effective factor, so a
new task reports 500000 usable tokens. This may overstate the upstream limit of
smaller models; an upstream rejection near the end of a long thread is an
accepted tradeoff. After the visible model set changes, apply these two values
to every current definition, let Cockpit regenerate its managed catalog, and
repeat both live route checks. Historical user-owned catalogs remain recovery
artifacts only and are not the active Mac configuration.

### Native ordered-catalog manager

`tools/CodexModelManager/` contains a standalone SwiftUI app for managing the
Mac catalog without patching Cockpit, ChatGPT, or Codex binaries. Codex Desktop
currently shows only the first 50 internal model definitions after sorting by
ascending `priority`. Cockpit's visible unprefixed entries below priority 1000
remain fixed at the top in their built-in order. The utility lets every other
model move below that boundary, writes Cockpit's `1000 + array index` fallback
priority, updates names, and can add provider models through the existing
uppercase `CPA` route.
Selecting a model ends any prior search-field editing focus so the Up/Down keys
move it immediately. Closing the last Model Manager window terminates the app.

The utility must remain narrower than the model synchronization workflow:

- It never displays or alters provider keys, OAuth records, account IDs, or
  unrelated routing fields. Additions-only synchronization may extend only the
  route-bearing API key's uppercase `CPA` upstream model array while Cockpit is
  stopped.
- Every catalog save backs up both writable catalog files. Route synchronization
  also backs up the credential-bearing route store with restricted permissions.
  Both paths preserve unknown fields and refuse to overwrite files changed
  externally since load.
- Provider removals remain visible until the user invokes the explicit removal
  action with Cockpit stopped. That action backs up the route store and both
  catalogs, removes the stale `CPA` entries, and leaves the live manifest for
  Cockpit to regenerate after relaunch.
- A save does not reload a running Codex app-server. Restart Codex through the
  normal API Service path only after active work is finished.

Build and verify it independently:

```bash
swift test --package-path tools/CodexModelManager
tools/CodexModelManager/scripts/build-app.sh
```

Do not replace ChatGPT OAuth with a CLIProxyAPI login. `codex login status` must remain `Logged in using ChatGPT`.

## Complete live verification

Start Cockpit and wait for port 57204. Verify persisted structure without exposing the local key:

```bash
open -a '/Applications/Cockpit Tools.app'
lsof -nP -iTCP:57204 -sTCP:LISTEN

jq -e '.apiKeys[0].modelRouting.defaultRoute=="oauth"
  and .apiKeys[0].modelRouting.failurePolicy=="strict"
  and .apiKeys[0].modelRouting.routes[0].namespace=="CPA"
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

cpa_response=$(mktemp)
cpa_code=$(curl -sS --max-time 180 -o "$cpa_response" -w '%{http_code}' \
  -H "Authorization: Bearer $local_key" \
  -H 'Content-Type: application/json' \
  --data-binary '{"model":"CPA/grok-4.3","input":"What is the capital of France? Reply with only the answer.","stream":false}' \
  http://127.0.0.1:57204/v1/responses)

official_reply=$(jq -r '[.output[]?.content[]? | select(.type=="output_text") | .text] | join("")' "$official_response")
cpa_reply=$(jq -r '[.output[]?.content[]? | select(.type=="output_text") | .text] | join("")' "$cpa_response")

test "$official_code" = '200'
test "$cpa_code" = '200'
printf '%s' "$official_reply" | rg -qi 'Paris|巴黎'
printf '%s' "$cpa_reply" | rg -qi 'Paris|巴黎'
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
codex exec --model CPA/grok-4.3 \
  'What is the capital of France? Reply with only the answer.'
```

Finally restart Cockpit once more and repeat the structure and two-route probes. Reopen the Codex app and visually confirm that both official and `CPA/*` models are present and selectable, with no old-prefix alias. A build, model count, or catalog file alone is not completion.

## Rollback

If the custom build fails, quit Cockpit, move the failed `/Applications/Cockpit Tools.app` aside to a uniquely named diagnostic backup, restore the most recent known-good `.app` backup with `ditto`, verify its signature, and restore the matching restricted-permission routing backup. Never delete the failed or previous app until the restored version launches and its expected route has been tested.

## Future update warning

Cockpit auto-update can replace this custom build. If Codex suddenly shows only default models:

1. Check the running Cockpit version, signature, and mixed-routing marker.
2. Check whether the sidecar manifest still contains `modelRouting`.
3. Check whether the five OAuth accounts and uppercase `CPA` namespace remain intact.
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
