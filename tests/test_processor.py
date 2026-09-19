from redpanda_connect import Message

from ripple_transform.processor import transform_message


def test_hello_is_uppercased() -> None:
    msg = Message(payload="hello")
    result = transform_message(msg)
    assert result is msg
    assert result.payload == "HELLO"


def test_hello_world_is_uppercased() -> None:
    msg = Message(payload="Hello World")
    result = transform_message(msg)
    assert result is msg
    assert result.payload == "HELLO WORLD"


def test_already_upper_is_unchanged() -> None:
    msg = Message(payload="ALREADY UPPER")
    result = transform_message(msg)
    assert result is msg
    assert result.payload == "ALREADY UPPER"


def test_empty_payload_is_unchanged() -> None:
    msg = Message(payload="")
    result = transform_message(msg)
    assert result is msg
    assert result.payload == ""


def test_returns_same_message_object() -> None:
    msg = Message(payload="hello")
    result = transform_message(msg)
    assert result is msg


def test_metadata_is_untouched() -> None:
    metadata = {"kafka_key": "variant-123", "source": "unit-test"}
    msg = Message(payload="hello", metadata=dict(metadata))
    result = transform_message(msg)
    assert result is msg
    assert result.metadata == metadata
    assert result.payload == "HELLO"


def test_bytes_payload_is_uppercased() -> None:
    msg = Message(payload=b"hello ripple")
    result = transform_message(msg)
    assert result is msg
    assert result.payload == b"HELLO RIPPLE"
