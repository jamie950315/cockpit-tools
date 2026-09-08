# RPi Codex catalog refresh

Python 3.11+ standard-library service for the RPi-owned model catalog. It reads
the selected `pi5-api` provider URL and credential helper from the existing Codex
configuration. It does not modify credentials, provider routing, Cockpit stores,
or running Codex processes, and performs no inference during scheduled runs.

The provider's authenticated `/models` response is the source of discoverable
IDs. Newly advertised official models use exact metadata from the newest locally
installed standalone Codex bundle when available. Other new IDs use a generic
text-only coding profile, not another model's identity instructions. Existing
entries and unknown fields remain intact. New native priorities put Astra near
the top; the internal `gpt-reserve` entry remains hidden.

Only IDs starting with the exact `CPA/` prefix receive the selected 526316 raw /
95% effective / 450000 compaction policy. This reports 500000 usable tokens in
Codex, but does not increase the real upstream capacity of smaller models.
All other IDs have previous context overrides removed and their context fields
restored from the newest installed Codex bundle on every refresh. For older
official IDs absent from that bundle, the original native discovery cache is a
fallback; entries carrying our custom 500K values are excluded. Unknown IDs have
no explicit context override and use Codex's schema/runtime defaults. This also
applies to future models: `CPA/gpt-*` gets 500K, unprefixed `gpt-*` does not.

The updater is additions-only: temporary provider omissions never delete models.
Permanent removals still require a reviewed maintenance operation. A provider
snapshot must expose both official and CPA groups. Network, authentication,
JSON, or Codex schema validation failures leave the original catalog intact.
Updates use a lock, optimistic concurrent-edit detection, a private backup, and
atomic replacement. No-op runs do not rewrite the file. Logs contain status,
counts, and added model names only.

## Deployment

- Script: `/home/jamie/.local/lib/codex-model-catalog/sync_catalog.py`
- Catalog: `/home/jamie/.codex/rpi-all-models-500k-catalog.json`
- Backups: `/home/jamie/.codex/backups/auto-model-catalog/`
- User units: `codex-model-catalog-sync.service` and `.timer`
- Schedule: two minutes after boot, then every ten minutes plus up to 30 seconds
  jitter. The existing `jamie` user has lingering enabled, so SSH logout does not
  stop the schedule. If the provider is offline, the next scheduled run retries.

Copy the script and units to the above user-owned directories, then run:

```sh
systemctl --user daemon-reload
systemctl --user enable --now codex-model-catalog-sync.timer
systemctl --user start codex-model-catalog-sync.service
systemctl --user list-timers codex-model-catalog-sync.timer
journalctl --user -u codex-model-catalog-sync.service -n 20
```

The timer only updates the disk catalog. An already-running Codex app-server may
retain its previous model list; reconnect the RPi host when convenient. Never
automatically restart it while tasks may be running. This service follows the
models the configured provider advertises, not every model on the internet, and
does not repair an upstream Cockpit route snapshot.

## Verification and recovery

```sh
cd ops/rpi-model-catalog
python3 -m unittest -v
python3 -m py_compile sync_catalog.py
python3 sync_catalog.py --check
```

`--check` performs discovery and full candidate validation through the installed
Codex but does not publish. After deployment, run the service twice: expect
`updated` then `unchanged`. Verify `codex debug models` and make independent
official and namespaced inference probes; scheduled refresh never runs these.
Check that every CPA entry has the custom context fields and every other entry
matches native defaults (including removal of the forced compaction threshold).

Disable with `systemctl --user disable --now codex-model-catalog-sync.timer`.
Stop the service before restoring a reviewed backup to the exact catalog path.
Retain backups until successful target-environment verification. Do not restore
or copy any host's `auth.json` as part of catalog recovery.
