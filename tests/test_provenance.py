from ripple_transform.provenance import flatten_record


def _record():
    return {
        "schema_version": "1",
        "observation_id": "e5d636d9-6303-46bb-8dba-0fa4c2667932",
        "tenant_id": "hospital-a",
        "application_id": "oncology-pipeline",
        "observed_at": "2026-10-10T15:47:50Z",
        "received_at": "2026-10-10T15:47:51.775422085Z",
        "source": {"name": "open_targets", "release": "26.06"},
        "observations": [
            {
                "usage": "REQUESTED",
                "entity_type": "gene",
                "identifier": {"namespace": "ensembl", "value": "ENSG00000012048"},
            }
        ],
        "context": {"analysis_id": "analysis-2741"},
    }


def test_flatten_record_keeps_the_envelope_and_drops_observations():
    row = flatten_record(_record(), created_at="2026-10-10T15:47:52Z")

    assert row == {
        "observation_id": "e5d636d9-6303-46bb-8dba-0fa4c2667932",
        "schema_version": "1",
        "tenant_id": "hospital-a",
        "application_id": "oncology-pipeline",
        "observed_at": "2026-10-10T15:47:50Z",
        "received_at": "2026-10-10T15:47:51.775422085Z",
        "source_name": "open_targets",
        "source_release": "26.06",
        "analysis_id": "analysis-2741",
        "intent_code": None,
        "intent_method": None,
        "intent_version": None,
        "created_at": "2026-10-10T15:47:52Z",
    }
    assert "observations" not in row


def test_flatten_record_allows_a_missing_context():
    record = _record()
    del record["context"]

    row = flatten_record(record, created_at="2026-10-10T15:47:52Z")

    assert row["analysis_id"] is None
    assert row["source_name"] == "open_targets"


def test_flatten_record_copies_intent():
    record = _record()
    record["intent"] = {
        "code": "RETRIEVE_GENE_DISEASE_ASSOCIATIONS",
        "method": "HARDCODED",
        "version": "1.0.0",
    }

    row = flatten_record(record, created_at="2026-10-10T15:47:52Z")

    assert row["intent_code"] == "RETRIEVE_GENE_DISEASE_ASSOCIATIONS"
    assert row["intent_method"] == "HARDCODED"
    assert row["intent_version"] == "1.0.0"
