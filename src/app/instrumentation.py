"""Endpoint instrumentation decorators.

Plain stdlib logging, like `app.middleware` -- no metrics client dependency.
"""

import functools
import inspect
import logging
import time
from collections.abc import Awaitable, Callable
from typing import ParamSpec, TypeVar

logger = logging.getLogger(__name__)

P = ParamSpec("P")
R = TypeVar("R")


def log_latency(name: str) -> Callable[[Callable[P, Awaitable[R]]], Callable[P, Awaitable[R]]]:
    """Log how long an async endpoint took and whether it raised.

    Safe on FastAPI path operations: `functools.wraps` sets `__wrapped__`, which
    FastAPI's `inspect.signature` follows, so request parsing and the OpenAPI
    schema still see the original parameters. The wrapper is itself `async def`
    so FastAPI keeps running it on the event loop rather than the threadpool.
    Apply it *below* the `@router.<method>` decorator, so the route registers
    the wrapped function.
    """

    def decorator(func: Callable[P, Awaitable[R]]) -> Callable[P, Awaitable[R]]:
        if not inspect.iscoroutinefunction(func):
            # A sync function would return before its work ran under a sync
            # wrapper's timer, or be awaited by mistake under this one.
            raise TypeError(f"log_latency supports async functions only, got {func.__qualname__}")

        @functools.wraps(func)
        async def wrapper(*args: P.args, **kwargs: P.kwargs) -> R:
            start = time.perf_counter()
            outcome = "ok"
            try:
                return await func(*args, **kwargs)
            # BaseException so a cancelled request (CancelledError) isn't
            # logged as "ok". Re-raised unchanged either way.
            except BaseException as exc:
                outcome = type(exc).__name__
                status_code = getattr(exc, "status_code", None)
                if status_code is not None:
                    outcome = f"{outcome} {status_code}"
                raise
            finally:
                elapsed_ms = (time.perf_counter() - start) * 1000
                logger.info("%s finished in %.1f ms (%s)", name, elapsed_ms, outcome)

        return wrapper

    return decorator
