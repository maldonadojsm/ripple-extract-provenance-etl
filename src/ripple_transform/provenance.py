"""Flatten an ingress observation into one provenance row."""

from __future__ import annotations

from datetime import datetime, timezone


def created_at_now() -> str:
    return datetime.now(timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


def flatten_record(record: dict, *, created_at: str) -> dict:
    """Copy the record envelope into the ``provenance`` columns.

    Observation items are not part of this row. ``created_at`` is when the
    row is produced, not ``received_at``.
    """
    source = record.get("source") or {}
    context = record.get("context") or {}
    intent = record.get("intent") or {}
    return {
        "observation_id": record.get("observation_id"),
        "schema_version": record.get("schema_version"),
        "tenant_id": record.get("tenant_id"),
        "application_id": record.get("application_id"),
        "observed_at": record.get("observed_at"),
        "received_at": record.get("received_at"),
        "source_name": source.get("name"),
        "source_release": source.get("release"),
        "analysis_id": context.get("analysis_id"),
        "intent_code": intent.get("code"),
        "intent_method": intent.get("method"),
        "intent_version": intent.get("version"),
        "created_at": created_at,
    }
