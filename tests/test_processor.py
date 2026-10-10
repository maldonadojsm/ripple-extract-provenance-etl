import json

from redpanda_connect import Message

from ripple_transform import provenance
from ripple_transform.processor import transform_message


def _record():
    return {
        "schema_version": "1",
        "observation_id": "e5d636d9-6303-46bb-8dba-0fa4c2667932",
        "tenant_id": "hospital-a",
        "application_id": "oncology-pipeline",
        "observed_at": "2026-10-10T15:47:50Z",
        "received_at": "2026-10-10T15:47:51.775422085Z",
        "source": {"name": "open_targets", "release": "26.06"},
        "observations": [],
        "context": {"analysis_id": "analysis-2741"},
    }


def test_message_is_flattened_and_metadata_is_kept(monkeypatch):
    monkeypatch.setattr(provenance, "created_at_now", lambda: "2026-10-10T15:47:52Z")
    metadata = {"kafka_key": "hospital-a:oncology-pipeline"}
    msg = Message(payload=json.dumps(_record()).encode(), metadata=dict(metadata))

    result = transform_message(msg)

    assert result is msg
    assert result.metadata == metadata
    body = json.loads(result.payload)
    assert body["observation_id"] == "e5d636d9-6303-46bb-8dba-0fa4c2667932"
    assert body["source_name"] == "open_targets"
    assert body["source_release"] == "26.06"
    assert body["analysis_id"] == "analysis-2741"
    assert body["created_at"] == "2026-10-10T15:47:52Z"
    assert "observations" not in body


def test_dict_payload_is_replaced_with_the_row(monkeypatch):
    monkeypatch.setattr(provenance, "created_at_now", lambda: "2026-10-10T15:47:52Z")
    msg = Message(payload=_record())

    result = transform_message(msg)

    assert isinstance(result.payload, dict)
    assert result.payload["tenant_id"] == "hospital-a"


def test_string_payload_stays_a_string(monkeypatch):
    monkeypatch.setattr(provenance, "created_at_now", lambda: "2026-10-10T15:47:52Z")
    msg = Message(payload=json.dumps(_record()))

    result = transform_message(msg)

    assert isinstance(result.payload, str)
    assert json.loads(result.payload)["application_id"] == "oncology-pipeline"
