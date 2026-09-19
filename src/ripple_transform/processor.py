import asyncio
import logging

import redpanda_connect

logger = logging.getLogger("ripple_transform")


def transform_message(
    msg: redpanda_connect.Message,
) -> redpanda_connect.Message:
    msg.payload = msg.payload.upper()
    return msg


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
