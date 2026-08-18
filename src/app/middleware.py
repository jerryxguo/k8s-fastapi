"""Request/error-handling middleware.

Structured logging of validation errors, kept deliberately simple and
self-contained -- no dependency on any internal/proprietary telemetry
package.
"""

import logging

from fastapi import Request
from fastapi.exceptions import RequestValidationError
from fastapi.responses import JSONResponse

logger = logging.getLogger("app.middleware")


async def log_validation_errors(request: Request, exc: RequestValidationError) -> JSONResponse:
    logger.warning(
        "request_validation_error",
        extra={"path": request.url.path, "errors": exc.errors()},
    )
    return JSONResponse(status_code=422, content={"detail": exc.errors()})
