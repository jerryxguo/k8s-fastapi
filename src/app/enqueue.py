"""Helpers for endpoints that hand work to the Celery worker.

`broker_unavailable_as_503` is the one place that decides what a caller sees
when the Redis broker can't be reached, so every enqueueing endpoint answers
the same way instead of each re-implementing the try/except.
"""

import logging
from collections.abc import Generator
from contextlib import contextmanager

from fastapi import HTTPException, status
from kombu.exceptions import OperationalError

logger = logging.getLogger(__name__)

RETRY_AFTER_SECONDS = 30


@contextmanager
def broker_unavailable_as_503(what: str) -> Generator[None, None, None]:
    """Turn a broker connection failure inside the block into a 503.

    The message was NOT queued, so 503 + Retry-After tells the sender to
    resend, rather than a 202 that would silently lose it. Use it as a `with`
    block around the enqueue call only: an OperationalError raised anywhere
    else would be misreported as "queue unavailable".
    """
    try:
        yield
    except OperationalError as exc:
        logger.exception("failed to enqueue %s", what)
        raise HTTPException(
            status_code=status.HTTP_503_SERVICE_UNAVAILABLE,
            detail="Queue unavailable; request not accepted. Retry later.",
            headers={"Retry-After": str(RETRY_AFTER_SECONDS)},
        ) from exc
