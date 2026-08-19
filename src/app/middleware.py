"""Request/error-handling middleware.

Logging of validation errors, kept deliberately simple and self-contained --
no dependency on any internal/proprietary telemetry package.
"""

import logging

from fastapi import Request
from fastapi.encoders import jsonable_encoder
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

logger = logging.getLogger("app.middleware")


async def log_validation_errors(request: Request, exc: RequestValidationError) -> JSONResponse:
    # jsonable_encoder is required: pydantic v2 puts live exception objects in
    # an error's `ctx`, which json.dumps cannot serialise -- passing
    # exc.errors() raw makes this handler raise and returns a 500 instead.
    errors = jsonable_encoder(exc.errors())

    # In the message, not `extra=`: stdlib logging's default formatter drops
    # extra keys. Locations only, never submitted values (possible user data).
    logger.warning(
        "Request validation failed for '%s': %d error(s) at %s",
        request.url.path,
        len(errors),
        [error.get("loc") for error in errors],
    )
    return JSONResponse(status_code=422, content={"detail": errors})
