"""FastAPI dependency-injection providers.

Exposes shared clients attached to `app.state` (built once in `lifespan`)
as request-scoped dependencies, rather than constructing them per-request.
"""

from fastapi import Request

from app.service.category_store import InMemoryCategoryStore
from app.service.item_store import InMemoryItemStore


def get_item_store(request: Request) -> InMemoryItemStore:
    return request.app.state.item_store


def get_category_store(request: Request) -> InMemoryCategoryStore:
    return request.app.state.category_store
