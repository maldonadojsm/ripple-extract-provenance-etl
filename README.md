# Ripple Redpanda Connect ETL

A small, production-shaped ETL that uppercases message payloads.

Redpanda Connect owns consumption, acknowledgements, retries, and production.
Python owns only the transformation.

```text
Redpanda topic
    ↓
Redpanda Connect
    ↓
Python RPC processor
    ↓
Redpanda Connect
    ↓
Redpanda topic
```

`hello ripple` becomes `HELLO RIPPLE`.

## Architecture

```text
┌───────────────────────────────────────────┐
│ Redpanda                                 │
│ ripple.etl.input                         │
└──────────────────┬────────────────────────┘
                   │ Kafka protocol
                   ▼
┌───────────────────────────────────────────┐
│ ripple-etl container                     │
│                                          │
│ Redpanda Connect (PID 1)                 │
│   input.redpanda                         │
│         ↓                                │
│   ripple_transform (gRPC / Unix socket)  │
│         ↓                                │
│   Python process                         │
│   transform_message()                    │
│         ↓                                │
│   output.redpanda                        │
└──────────────────┬────────────────────────┘
                   │ Kafka protocol
                   ▼
┌───────────────────────────────────────────┐
│ Redpanda                                 │
│ ripple.etl.output                        │
└───────────────────────────────────────────┘
```

File responsibilities:

| File | Role |
| --- | --- |
| `connect.yaml` | Dataflow and orchestration |
| `plugin.yaml` | RPC plugin registration |
| `src/ripple_transform/processor.py` | Transformation logic |
| `Dockerfile` | Runtime packaging (Connect + Python + processor) |
| `docker-compose.yml` | Local broker, topics, ETL, and Console |

Python does not create Kafka consumers or producers. Broker and topic names are environment variables consumed only by Connect.

## Delivery semantics

This pipeline is **at-least-once**, not exactly-once.

```text
consume message
    ↓
process message
    ↓
write output
    ↓
output acknowledges write
    ↓
input offset can advance
```

A crash after the output write and before the input offset commit can replay a message. That is acceptable for this MVP.

The current transformation is naturally idempotent:

```text
hello
→ HELLO
→ HELLO
→ HELLO
```

Future processors must consider idempotency themselves. Duplicate deliveries will re-run `transform_message`.

Message keys are preserved by Connect (`key: '${! meta("kafka_key") }'`). The Python processor does not touch keys.

## Requirements

- Docker
- Docker Compose
- uv
- Python 3.12+
- rpk — optional for host-side debugging (Compose uses the `rpk` bundled in the Redpanda image)

Pinned runtime:

- Redpanda Connect `4.108.0` (`docker.io/redpandadata/connect:4.108.0`)
- Redpanda `v26.2.2`
- Python `redpanda-connect` SDK `>=0.1.3`

## Local startup

```bash
cp .env.example .env
docker compose up --build
```

Or:

```bash
make up
```

Compose creates `ripple.etl.input` and `ripple.etl.output` explicitly via `rpk topic create --if-not-exists`. The ETL container talks to the broker at `redpanda:9092` on the Docker network.

Health:

- Liveness: http://127.0.0.1:43195/ping
- Readiness (input and output connected): http://127.0.0.1:43195/ready
- Redpanda Console: http://127.0.0.1:18080

## Produce a test message

Using Compose (recommended):

```bash
printf 'hello ripple' | docker compose exec -i -T redpanda \
  rpk topic produce ripple.etl.input -X brokers=redpanda:9092 -f '%v'
```

Or `make produce`.

With a key:

```bash
printf 'hello' | docker compose exec -i -T redpanda \
  rpk topic produce ripple.etl.input -X brokers=redpanda:9092 -f '%v' -k variant-123
```

If `rpk` is installed on the host, advertise Kafka is on `localhost:19092`:

```bash
printf 'hello ripple\n' | rpk topic produce ripple.etl.input -X brokers=localhost:19092
```

## Consume output

```bash
docker compose exec -T redpanda \
  rpk topic consume ripple.etl.output -X brokers=redpanda:9092 -o start -f '%k %v\n'
```

Or `make consume`.

Expected payload for `hello ripple`:

```text
HELLO RIPPLE
```

Expected for key `variant-123` and payload `hello`:

```text
variant-123 HELLO
```

## Run unit tests

```bash
uv sync
uv run pytest
```

Unit tests call `transform_message` directly. They do not start Redpanda Connect or the RPC server.

## Lint

```bash
make lint
```

This runs Ruff and `rpk connect lint connect.yaml` (or the equivalent Connect image if `rpk` is not on `PATH`). Dummy broker/topic values are supplied for interpolation.

## Run integration tests

```bash
make integration-test
```

The script starts Compose, waits for Redpanda health and ETL `/ready`, produces a unique payload, asserts the uppercase result, checks key preservation, then stops the ETL, produces another message, restarts the ETL, and confirms the consumer group resumes. Compose is stopped when the script exits (success or failure).

## Shutdown

```bash
docker compose down
```

Or `make down`.

## Configuration

Copy `.env.example` to `.env`. There are no secrets in the local MVP.

```env
REDPANDA_BROKERS=redpanda:9092
INPUT_TOPIC=ripple.etl.input
OUTPUT_TOPIC=ripple.etl.output
CONSUMER_GROUP=ripple-transform-etl-v1
```

The Python processor has no broker or topic configuration.

## Reuse for a future ETL

Replace only:

1. `transform_message` in `src/ripple_transform/processor.py`
2. Topic and consumer group values in `.env` / Compose
3. Plugin name in `plugin.yaml` and `connect.yaml` if you want a new processor identity

Keep Connect as the consumer/producer. Keep Python as the transformation.
