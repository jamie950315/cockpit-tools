#!/usr/bin/env bash
set -euo pipefail

readonly APP_DIR="${CLIPROXY_APP_DIR:-/home/jamie/docker/cli-proxy-api}"
readonly COMPOSE_FILE="${CLIPROXY_COMPOSE_FILE:-${APP_DIR}/compose.yml}"
readonly ENV_FILE="${CLIPROXY_ENV_FILE:-${APP_DIR}/.env}"
readonly CONTAINER="${CLIPROXY_CONTAINER:-cli-proxy-api}"
readonly IMAGE_REPO="${CLIPROXY_IMAGE_REPO:-eceasy/cli-proxy-api}"
readonly RELEASE_API="${CLIPROXY_RELEASE_API:-https://api.github.com/repos/router-for-me/CLIProxyAPI/releases/latest}"
readonly API_BASE="${CLIPROXY_API_BASE:-http://127.0.0.1:8317}"
readonly LOCK_FILE="${CLIPROXY_LOCK_FILE:-/run/lock/cliproxyapi-auto-update.lock}"
readonly MODE="${1:-update}"

log() { printf '%s %s\n' "$(date --iso-8601=seconds)" "$*"; }
die() { log "ERROR: $*" >&2; exit 1; }
require_command() { command -v "$1" >/dev/null 2>&1 || die "required command is unavailable: $1"; }

for command_name in curl docker flock jq mktemp; do require_command "$command_name"; done
[[ "$MODE" == "update" || "$MODE" == "--check-only" ]] || die "usage: $0 [--check-only]"
[[ -d "$APP_DIR" ]] || die "application directory does not exist"
[[ -f "$COMPOSE_FILE" ]] || die "compose file does not exist"

exec 9>"$LOCK_FILE"
flock -n 9 || die "another update is already running"

running_version() {
  { docker exec "$CONTAINER" ./CLIProxyAPI --version 2>&1 || true; } \
    | sed -nE 's/^CLIProxyAPI Version: (v[0-9]+\.[0-9]+\.[0-9]+).*/\1/p' | head -n1
}

current_version="$(running_version)"
[[ "$current_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "could not determine the running version"
release_json="$(curl --fail --silent --show-error --location --max-time 30 \
  -H 'Accept: application/vnd.github+json' -H 'X-GitHub-Api-Version: 2022-11-28' "$RELEASE_API")"
latest_version="$(jq -r 'select(.draft == false and .prerelease == false) | .tag_name' <<<"$release_json")"
[[ "$latest_version" =~ ^v[0-9]+\.[0-9]+\.[0-9]+$ ]] || die "latest release tag is invalid"

log "running=$current_version latest=$latest_version"
if [[ "$current_version" == "$latest_version" ]]; then log "already current"; exit 0; fi
newest_version="$(printf '%s\n%s\n' "$current_version" "$latest_version" | sort -V | tail -n1)"
if [[ "$newest_version" == "$current_version" ]]; then
  log "running version is newer than the published stable release; refusing to downgrade"
  exit 0
fi
if [[ "$MODE" == "--check-only" ]]; then log "update available"; exit 10; fi

current_image_id="$(docker inspect "$CONTAINER" --format '{{.Image}}')"
current_image_ref="$(docker image inspect "$current_image_id" --format '{{index .RepoDigests 0}}')"
[[ "$current_image_ref" == *'@sha256:'* ]] || die "running image has no immutable repository digest"

candidate_tag="${IMAGE_REPO}:${latest_version}"
log "pulling release $latest_version"
docker pull "$candidate_tag" >/dev/null
candidate_image_ref="$(docker image inspect "$candidate_tag" --format '{{index .RepoDigests 0}}')"
[[ "$candidate_image_ref" == *'@sha256:'* ]] || die "candidate image has no immutable repository digest"

health_config="$(mktemp "${TMPDIR:-/tmp}/cliproxyapi-health.XXXXXX")"
env_backup="$(mktemp "${APP_DIR}/.env.pre-update.XXXXXX")"
cleanup() { rm -f "$health_config" "$env_backup"; }
trap cleanup EXIT
chmod 600 "$health_config"
if [[ -f "$ENV_FILE" ]]; then
  cp -p "$ENV_FILE" "$env_backup"
else
  printf 'CLIPROXY_IMAGE=%s\n' "$current_image_ref" >"$env_backup"
  chmod 600 "$env_backup"
fi

write_image_env() {
  local temporary
  temporary="$(mktemp "${APP_DIR}/.env.new.XXXXXX")"
  printf 'CLIPROXY_IMAGE=%s\n' "$1" >"$temporary"
  chmod 600 "$temporary"
  mv "$temporary" "$ENV_FILE"
}

extract_local_api_key() {
  awk '
    /^api-keys:[[:space:]]*$/ { in_keys=1; next }
    in_keys && /^[[:space:]]*-[[:space:]]*/ {
      value=$0; sub(/^[[:space:]]*-[[:space:]]*/, "", value); sub(/[[:space:]]+#.*$/, "", value)
      gsub(/^['\"']|['\"']$/, "", value); print value; exit
    }
    in_keys && /^[^[:space:]]/ { exit }
  ' "${APP_DIR}/config.yaml"
}

wait_for_api() {
  local attempt code
  for attempt in $(seq 1 60); do
    code="$(curl --silent --output /dev/null --write-out '%{http_code}' --max-time 3 "${API_BASE}/v1/models" || true)"
    [[ "$code" == "200" || "$code" == "401" ]] && return 0
    sleep 2
  done
  return 1
}

verify_release() {
  local expected="$1" api_key response_file code request_index codex_auth_count attempt request_ok
  if [[ "$(running_version)" != "$expected" ]]; then
    log "verification: runtime version mismatch"
    return 1
  fi
  api_key="$(extract_local_api_key)"
  if [[ -z "$api_key" ]]; then
    log "verification: local API key unavailable"
    return 1
  fi
  printf 'header = "Authorization: Bearer %s"\n' "$api_key" >"$health_config"
  unset api_key

  response_file="$(mktemp "${TMPDIR:-/tmp}/cliproxyapi-response.XXXXXX")"
  codex_auth_count="$(find "${APP_DIR}/auths" -maxdepth 1 -type f -name 'codex-*-team.json' | wc -l | tr -d ' ')"
  if [[ "$codex_auth_count" != "5" ]]; then
    log "verification: expected five TEAM auth files, found $codex_auth_count"
    rm -f "$response_file"
    return 1
  fi

  request_ok=false
  for attempt in $(seq 1 60); do
    code="$(curl --config "$health_config" --silent --show-error --max-time 5 \
      --output "$response_file" --write-out '%{http_code}' "${API_BASE}/v1/models" || true)"
    if [[ "$code" == "200" ]] && jq -e '.data | length > 0' "$response_file" >/dev/null; then
      request_ok=true
      break
    fi
    sleep 2
  done
  if [[ "$request_ok" != "true" ]]; then
    log "verification: authenticated model catalog did not become ready"
    rm -f "$response_file"
    return 1
  fi

  for request_index in 1 2 3 4 5; do
    request_ok=false
    for attempt in 1 2 3; do
      code="$(jq -nc --arg cache_key "auto-update-${latest_version}-${request_index}" \
        '{model:"gpt-5.6-luna",input:"Reply only OK.",stream:false,store:false,max_output_tokens:16,prompt_cache_key:$cache_key}' \
        | curl --config "$health_config" --silent --show-error --max-time 180 \
            -H 'Content-Type: application/json' --data-binary @- \
            --output "$response_file" --write-out '%{http_code}' "${API_BASE}/v1/responses" || true)"
      if [[ "$code" == "200" ]] && jq -e '.id and (.error | not)' "$response_file" >/dev/null; then
        request_ok=true
        break
      fi
      log "verification: Responses check $request_index attempt $attempt failed with HTTP $code"
      sleep 2
    done
    if [[ "$request_ok" != "true" ]]; then
      rm -f "$response_file"
      return 1
    fi
  done
  rm -f "$response_file"
}

rollback() {
  log "verification failed; restoring $current_version"
  cp -p "$env_backup" "$ENV_FILE"
  docker compose --project-directory "$APP_DIR" --file "$COMPOSE_FILE" up -d --force-recreate >/dev/null
  wait_for_api || true
  die "update to $latest_version failed and rollback was attempted"
}

write_image_env "$candidate_image_ref"
docker compose --project-directory "$APP_DIR" --file "$COMPOSE_FILE" up -d --force-recreate >/dev/null
verify_release "$latest_version" || rollback
rm -f "$env_backup"
log "updated successfully to $latest_version and passed five-account Responses checks"
