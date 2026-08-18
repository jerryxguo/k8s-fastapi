"""v1 API surface.

Owns the `/v1` prefix in one place so every resource router below it only
declares its own path segment (`/items`, `/categories`), and `main` mounts a
single router per API version.
"""

from fastapi import APIRouter

from app.routers.v1.categories import router as categories_router
from app.routers.v1.items import router as items_router

router = APIRouter(prefix="/v1")
router.include_router(items_router)
router.include_router(categories_router)
