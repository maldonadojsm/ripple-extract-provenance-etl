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
payload="ripple-integration-test-${id}"
expected="$(python3 -c 'import sys; print(sys.argv[1].upper())' "$payload")"

echo "==> producing unique payload"
produce "$payload"

echo "==> consuming uppercase payload"
wait_for_output "$expected"

key="variant-${id}"
key_payload="hello"
key_expected="HELLO"
produce "$key_payload" "$key"

echo "==> verifying key preservation"
wait_for_output "${key} ${key_expected}" '%k %v'

echo "==> failure/recovery: stop ETL, produce, restart"
docker compose stop ripple-etl
recovery_payload="ripple-recovery-test-${id}"
recovery_expected="$(python3 -c 'import sys; print(sys.argv[1].upper())' "$recovery_payload")"
produce "$recovery_payload"
docker compose start ripple-etl
wait_for_http "$ETL_READY_URL"
wait_for_output "$recovery_expected"

echo "integration tests passed"
