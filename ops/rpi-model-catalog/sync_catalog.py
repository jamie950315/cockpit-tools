#!/usr/bin/env python3
"""Refresh the RPi-owned Codex catalog without changing auth or running tasks."""
import argparse
import copy
import fcntl
import json
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile
import time
import tomllib
import urllib.request


def model_map(document):
    rows = document.get("models")
    if not isinstance(rows, list) or not rows:
        raise ValueError("empty or invalid model catalog")
    result = {}
    for row in rows:
        slug = row.get("slug") if isinstance(row, dict) else None
        if not isinstance(slug, str) or not slug or slug in result:
            raise ValueError("invalid or duplicate model ID")
        result[slug] = row
    return result


def advertised_ids(document):
    rows = document.get("data")
    if not isinstance(rows, list) or not rows:
        raise ValueError("empty or invalid provider response")
    ids = []
    for row in rows:
        value = row.get("id") if isinstance(row, dict) else None
        if not isinstance(value, str) or not re.fullmatch(r"[A-Za-z0-9][A-Za-z0-9._:/+-]{0,255}", value):
            raise ValueError("invalid provider model ID")
        if value not in ids:
            ids.append(value)
    # A partial/cooling provider response must not erase either group.
    if not any(x.startswith("gpt-") for x in ids) or not any(x.startswith("CPA/") for x in ids):
        raise ValueError("provider response missing a required model group")
    return ids


def merge_catalog(current, bundled, ids):
    old = model_map(current)
    native = model_map(bundled)
    # Existing entries are retained when absent upstream: a temporary outage is
    # not proof of permanent removal. Preserve user ordering and unknown fields.
    merged = copy.deepcopy(old)
    template = next((r for s, r in old.items() if s.startswith("CPA/")), None)
    if template is None:
        raise ValueError("missing generic provider template")
    for slug in ids:
        if slug in merged:
            continue
        if slug in native:
            row = copy.deepcopy(native[slug])
        else:
            row = copy.deepcopy(template)
            row.update(slug=slug, display_name=("CPA · " + slug[4:] if slug.startswith("CPA/") else slug),
                       description="Model advertised by the configured provider",
                       priority=1000 + len(merged), upgrade=None, comp_hash="",
                       additional_speed_tiers=[], service_tiers=[],
                       input_modalities=["text"], supports_search_tool=False)
            # Never copy a model-specific prompt or message template to a new ID.
            row["base_instructions"] = "You are a coding assistant. Follow the user's instructions, use available tools when appropriate, and report verified results accurately."
            row.pop("model_messages", None)
            row["visibility"] = "hide" if slug == "gpt-reserve" else "list"
        merged[slug] = row
    for row in merged.values():
        row.update(context_window=526316, max_context_window=526316,
                   effective_context_window_percent=95, auto_compact_token_limit=450000)
    result = copy.deepcopy(current)
    result["models"] = sorted(merged.values(), key=lambda x: x.get("priority", 10000))
    return result


def codex_binary(home):
    candidates = list((home / "packages/standalone/releases").glob("*/bin/codex"))
    def version(path):
        match = re.match(r"(\d+)\.(\d+)\.(\d+)-", path.parent.parent.name)
        return tuple(map(int, match.groups())) if match else (0, 0, 0)
    candidates = [p for p in candidates if os.access(p, os.X_OK)]
    if candidates:
        return str(max(candidates, key=version))
    binary = shutil.which("codex")
    if not binary:
        raise ValueError("Codex binary unavailable")
    return binary


def run_json(command):
    result = subprocess.run(command, capture_output=True, timeout=45, check=True)
    return json.loads(result.stdout)


def publish(target, original, candidate, binary, check=False):
    if json.loads(original) == candidate:
        return "unchanged"
    fd, name = tempfile.mkstemp(prefix=".catalog-candidate-", suffix=".json", dir=target.parent)
    temporary = Path(name)
    try:
        with os.fdopen(fd, "w") as stream:
            json.dump(candidate, stream, ensure_ascii=False)
            stream.flush()
            os.fsync(stream.fileno())
        # Let the installed Codex enforce its complete, version-specific schema.
        resolved = run_json([binary, "-c", "model_catalog_json=" + json.dumps(str(temporary)), "debug", "models"])
        if set(model_map(resolved)) != set(model_map(candidate)):
            raise ValueError("Codex resolved a different candidate model set")
        if target.read_bytes() != original:
            raise ValueError("catalog changed concurrently; retry next run")
        if check:
            return "update-available"
        backups = target.parent / "backups/auto-model-catalog"
        backups.mkdir(parents=True, exist_ok=True, mode=0o700)
        backup = backups / (str(time.time_ns()) + ".json")
        with backup.open("xb") as stream:
            os.chmod(backup, 0o600)
            stream.write(original)
        os.replace(temporary, target)
        return "updated"
    finally:
        temporary.unlink(missing_ok=True)


def sync(home, check=False):
    config = tomllib.loads((home / "config.toml").read_text())
    if config.get("model_provider") != "pi5-api":
        raise ValueError("provider changed; refusing to take over another configuration")
    target = Path(config["model_catalog_json"])
    if not target.is_absolute():
        target = home / target
    expected = home / "rpi-all-models-500k-catalog.json"
    if target != expected or target.is_symlink():
        raise ValueError("catalog target changed; refusing to overwrite")
    provider = config["model_providers"]["pi5-api"]
    auth = provider["auth"]["command"]
    if not isinstance(auth, str) or not Path(auth).is_absolute():
        raise ValueError("unsupported credential helper")
    token = subprocess.check_output([auth], stderr=subprocess.DEVNULL, timeout=10, text=True).strip()
    if not token or "\n" in token or "\r" in token:
        raise ValueError("invalid credential helper response")
    request = urllib.request.Request(provider["base_url"].rstrip("/") + "/models",
                                     headers={"Authorization": "Bearer " + token})
    # Do not forward the credential to a redirected destination.
    class NoRedirect(urllib.request.HTTPRedirectHandler):
        def redirect_request(self, *args, **kwargs):
            return None
    with urllib.request.build_opener(NoRedirect).open(request, timeout=30) as response:
        body = response.read(8 * 1024 * 1024 + 1)
    if len(body) > 8 * 1024 * 1024:
        raise ValueError("provider response too large")
    ids = advertised_ids(json.loads(body))
    original = target.read_bytes()
    current = json.loads(original)
    binary = codex_binary(home)
    bundled = run_json([binary, "debug", "models", "--bundled"])
    candidate = merge_catalog(current, bundled, ids)
    status = publish(target, original, candidate, binary, check)
    print(json.dumps({"status": status, "models": len(candidate["models"]),
                      "added": sorted(set(model_map(candidate)) - set(model_map(current))),
                      "retained_absent": len(set(model_map(current)) - set(ids))}))


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument("--home", type=Path, default=Path.home() / ".codex")
    parser.add_argument("--check", action="store_true")
    args = parser.parse_args()
    os.umask(0o077)
    try:
        with (args.home / ".auto-model-catalog.lock").open("a") as lock:
            fcntl.flock(lock, fcntl.LOCK_EX | fcntl.LOCK_NB)
            sync(args.home, args.check)
    except BlockingIOError:
        print('{"status":"already-running"}')
    except Exception as error:
        # Exceptions from network/process calls can include credentials or URLs.
        print(json.dumps({"status": "failed", "error_type": type(error).__name__,
                          "catalog_preserved": True}))
        raise SystemExit(1)


if __name__ == "__main__":
    main()
