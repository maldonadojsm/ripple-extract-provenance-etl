.PHONY: install lint test build up down logs produce consume integration-test


install:
	uv sync

lint:
	uv run ruff check .
	@echo "Linting connect.yaml with the ETL image so ripple_transform is registered"
	docker compose build ripple-etl
	docker compose run --rm --no-deps --entrypoint redpanda-connect \
		-e REDPANDA_BROKERS=redpanda:9092 \
		-e INPUT_TOPIC=ripple.etl.input \
		-e OUTPUT_TOPIC=ripple.etl.output \
		-e CONSUMER_GROUP=ripple-transform-etl-v1 \
		ripple-etl --rpc-plugins=/app/plugin.yaml lint /app/connect.yaml

test:
	uv run pytest

build:
	docker compose build

up:
	@test -f .env || cp .env.example .env
	docker compose up -d --build

down:
	docker compose down

logs:
	docker compose logs -f ripple-etl

produce:
	printf 'hello ripple' | docker compose exec -i -T redpanda \
		rpk topic produce ripple.etl.input -X brokers=redpanda:9092 -f '%v'

consume:
	docker compose exec -T redpanda \
		rpk topic consume ripple.etl.output -X brokers=redpanda:9092 -o start -n 10 -f '%k %v\n'

integration-test:
	./scripts/integration_test.sh
