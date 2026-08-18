"""A trivial in-memory category store standing in for a real datastore.

Same placeholder shape as `item_store` -- it exists to give the example
category endpoints something to do, not to model a real domain.
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from app.schemas.common import CategoryStatus


@dataclass
class StoredCategory:
    id: str
    name: str
    description: str | None
    status: CategoryStatus = CategoryStatus.ACTIVE


class InMemoryCategoryStore:
    """Not for production use — see `InMemoryItemStore` for the same caveat."""

    def __init__(self) -> None:
        self._categories: dict[str, StoredCategory] = {}

    def create(self, name: str, description: str | None) -> StoredCategory:
        category = StoredCategory(id=str(uuid.uuid4()), name=name, description=description)
        self._categories[category.id] = category
        return category

    def get(self, category_id: str) -> StoredCategory | None:
        return self._categories.get(category_id)

    def list(self) -> list[StoredCategory]:
        return list(self._categories.values())
