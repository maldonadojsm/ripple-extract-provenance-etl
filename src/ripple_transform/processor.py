import asyncio
import json
import logging

import redpanda_connect

from ripple_transform import provenance

logger = logging.getLogger("ripple_transform")


def transform_message(
    msg: redpanda_connect.Message,
) -> redpanda_connect.Message:
    raw = msg.payload
    try:
        record = _decode(raw)
        flat = provenance.flatten_record(
            record, created_at=provenance.created_at_now()
        )
    except Exception:
        logger.exception(
            "failed to flatten provenance record (payload %s)", type(raw).__name__
        )
        raise
    msg.payload = _encode(raw, flat)
    return msg


def _decode(raw: object) -> dict:
    if isinstance(raw, (bytes, bytearray)):
        return json.loads(raw.decode("utf-8"))
    if isinstance(raw, str):
        return json.loads(raw)
    if isinstance(raw, dict):
        return raw
    raise TypeError(f"unsupported payload type: {type(raw).__name__}")


def _encode(raw: object, record: dict) -> object:
    if isinstance(raw, dict):
        return record
    encoded = json.dumps(record, separators=(",", ":"))
    return encoded.encode("utf-8") if isinstance(raw, (bytes, bytearray)) else encoded


def main() -> None:
    logging.basicConfig(level=logging.INFO)
    logger.info("processor starting")
    try:
        logger.info("processor ready")
        asyncio.run(
            redpanda_connect.processor_main(
                redpanda_connect.processor(transform_message)
            )
        )
    except Exception:
        logger.exception("processor error")
        raise
    finally:
        logger.info("processor stopping")


if __name__ == "__main__":
    main()
