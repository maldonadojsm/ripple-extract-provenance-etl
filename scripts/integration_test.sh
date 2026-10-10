#!/usr/bin/env bash
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
cd "$ROOT"

INPUT_TOPIC="${INPUT_TOPIC:-ripple.etl.input}"
OUTPUT_TOPIC="${OUTPUT_TOPIC:-ripple.etl.output}"
ETL_READY_URL="${ETL_READY_URL:-http://127.0.0.1:43195/ready}"
WAIT_SECONDS="${WAIT_SECONDS:-90}"

if [[ ! -f .env ]]; then
  cp .env.example .env
fi

cleanup() {
  echo "==> stopping compose stack"
  docker compose down || true
}
trap cleanup EXIT

produce() {
  local value="$1"
  local key="${2:-}"
  if [[ -n "$key" ]]; then
    printf '%s' "$value" | docker compose exec -i -T redpanda \
      rpk topic produce "$INPUT_TOPIC" -X brokers=redpanda:9092 -f '%v' -k "$key"
  else
    printf '%s' "$value" | docker compose exec -i -T redpanda \
      rpk topic produce "$INPUT_TOPIC" -X brokers=redpanda:9092 -f '%v'
  fi
}

wait_for_http() {
  local url="$1"
  local deadline=$((SECONDS + WAIT_SECONDS))
  while (( SECONDS < deadline )); do
    if curl -fsS "$url" >/dev/null 2>&1; then
      return 0
    fi
    sleep 2
  done
  echo "timed out waiting for $url" >&2
  docker compose logs ripple-etl >&2 || true
  return 1
}

wait_for_output() {
  local expected="$1"
  local format="${2:-%v}"
  local deadline=$((SECONDS + WAIT_SECONDS))
  # Consume from the start of the topic through the current end. -o -1 only
  # tails new records, so a message already written by the ETL is missed.
  while (( SECONDS < deadline )); do
    if docker compose exec -T redpanda rpk topic consume "$OUTPUT_TOPIC" \
      -X brokers=redpanda:9092 \
      -o 0:end \
      -f "${format}\n" \
      --fetch-max-wait 1s 2>/dev/null | grep -F -- "$expected" >/dev/null; then
      return 0
    fi
    sleep 1
  done
  echo "timed out waiting for output message: $expected" >&2
  docker compose logs ripple-etl >&2 || true
  return 1
}

echo "==> starting compose stack"
docker compose up -d --build

echo "==> waiting for Redpanda"
deadline=$((SECONDS + WAIT_SECONDS))
until docker compose exec -T redpanda rpk cluster health -X brokers=redpanda:9092 2>/dev/null | grep -E 'Healthy:.+true' >/dev/null; do
  if (( SECONDS >= deadline )); then
    echo "timed out waiting for Redpanda" >&2
    docker compose logs redpanda >&2 || true
    exit 1
  fi
  sleep 2
done

echo "==> waiting for ETL /ready"
wait_for_http "$ETL_READY_URL"

id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
payload="$(python3 -c 'import json,sys; print(json.dumps({"schema_version":"1","observation_id":sys.argv[1],"tenant_id":"hospital-a","application_id":"oncology-pipeline","observed_at":"2026-10-10T15:47:50Z","received_at":"2026-10-10T15:47:51.775422085Z","source":{"name":"open_targets","release":"26.06"},"observations":[],"context":{"analysis_id":"analysis-2741"}}))' "$id")"

echo "==> producing an observation"
produce "$payload"

echo "==> consuming the flattened provenance row"
wait_for_output "$id"
wait_for_output '"source_name":"open_targets"'

key="variant-${id}"
produce "$payload" "$key"

echo "==> verifying key preservation"
wait_for_output "${key} ${id}" '%k %v'

echo "==> failure/recovery: stop ETL, produce, restart"
docker compose stop ripple-etl
recovery_id="$(python3 -c 'import uuid; print(uuid.uuid4())')"
recovery_payload="$(python3 -c 'import json,sys; print(json.dumps({"schema_version":"1","observation_id":sys.argv[1],"tenant_id":"hospital-a","application_id":"oncology-pipeline","observed_at":"2026-10-10T15:47:50Z","received_at":"2026-10-10T15:47:51.775422085Z","source":{"name":"open_targets","release":"26.06"},"observations":[],"context":{"analysis_id":"analysis-recovery"}}))' "$recovery_id")"
produce "$recovery_payload"
docker compose start ripple-etl
wait_for_http "$ETL_READY_URL"
wait_for_output "$recovery_id"

echo "integration tests passed"
