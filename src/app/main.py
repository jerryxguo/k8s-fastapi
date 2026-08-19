"""FastAPI application entrypoint.

A `lifespan` context manager builds shared clients once and stores them on
`app.state`, a `/healthcheck` endpoint is used by both the Kubernetes
liveness/readiness probes and the ALB target group health check, and
versioned routers are registered under `app.include_router`.
"""

import logging
from contextlib import asynccontextmanager

from fastapi import FastAPI
from fastapi.exceptions import RequestValidationError

from app import __version__
from app.middleware import log_validation_errors
from app.routers.v1 import router as v1_router
from app.schemas.common import HealthResponse
from app.service.category_store import InMemoryCategoryStore
from app.service.item_store import InMemoryItemStore
from app.settings import get_settings

logging.basicConfig(level=get_settings().log_level)
logger = logging.getLogger("app")


@asynccontextmanager
async def lifespan(app: FastAPI):
    settings = get_settings()
    logger.info("starting %s in %s (%s)", settings.service_name, settings.env, settings.region)

    # Built once per process and reused across requests -- this is where a
    # real service would construct shared clients (HTTP clients, DB pools,
    # feature-flag clients, etc.) once at startup instead of per-request.
    app.state.item_store = InMemoryItemStore()
    app.state.category_store = InMemoryCategoryStore()

    yield

    logger.info("shutting down %s", settings.service_name)


app = FastAPI(title="K8s Demo Service", version=__version__, lifespan=lifespan)
# RequestValidationError only. Registering pydantic's ValidationError too
# would report server-side model failures to the caller as a 422, hiding a
# server bug and leaking internal field names; those must surface as 500s.
#
# mypy flags this because Starlette's stub types the handler as
# Callable[[Request, Exception], ...]; known stub limitation.
app.add_exception_handler(RequestValidationError, log_validation_errors)  # type: ignore[arg-type]
app.include_router(v1_router)


@app.get("/healthcheck", response_model=HealthResponse)
async def healthcheck() -> HealthResponse:
    settings = get_settings()
    return HealthResponse(service=settings.service_name, version=__version__)
