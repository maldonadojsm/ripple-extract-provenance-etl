# syntax=docker/dockerfile:1

# Official Redpanda Connect image is scratch-based. Inspected Entrypoint is
# /redpanda-connect (Connect 4.108.0). Copy that binary into a Python runtime.
FROM docker.io/redpandadata/connect:4.108.0 AS connect

FROM python:3.12-slim AS runtime

COPY --from=ghcr.io/astral-sh/uv:0.12.10 /uv /usr/local/bin/uv
COPY --from=connect /redpanda-connect /usr/local/bin/redpanda-connect

WORKDIR /app

ENV UV_COMPILE_BYTECODE=1 \
    UV_LINK_MODE=copy \
    UV_PROJECT_ENVIRONMENT=/app/.venv \
    PATH="/app/.venv/bin:$PATH" \
    PYTHONUNBUFFERED=1 \
    PYTHONDONTWRITEBYTECODE=1

COPY pyproject.toml uv.lock README.md /app/
COPY src /app/src

RUN uv sync --frozen --no-dev --no-editable

COPY connect.yaml plugin.yaml /app/

EXPOSE 4195

ENTRYPOINT ["redpanda-connect"]
CMD ["run", "--rpc-plugins=/app/plugin.yaml", "--disable-telemetry", "/app/connect.yaml"]
