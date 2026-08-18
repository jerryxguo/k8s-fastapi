"""A trivial in-memory store standing in for a real datastore.

This is placeholder business logic only, deliberately generic. It exists
purely to give the example endpoints something to do and to demonstrate the
dependency-injection / lifespan-managed-client shape a real service would
use for its actual external clients (databases, third-party APIs, etc.).
"""

from __future__ import annotations

import uuid
from dataclasses import dataclass

from app.schemas.common import ItemStatus


@dataclass
class StoredItem:
    id: str
    name: str
    description: str | None
    status: ItemStatus = ItemStatus.PENDING


class InMemoryItemStore:
    """Not for production use — a real deployment would back this with
    RDS/DynamoDB and inject credentials the same way secrets are handled
    elsewhere in this project (IRSA + External Secrets Operator)."""

    def __init__(self) -> None:
        self._items: dict[str, StoredItem] = {}

    def create(self, name: str, description: str | None) -> StoredItem:
        item = StoredItem(id=str(uuid.uuid4()), name=name, description=description)
        self._items[item.id] = item
        return item

    def get(self, item_id: str) -> StoredItem | None:
        return self._items.get(item_id)

    def list(self) -> list[StoredItem]:
        return list(self._items.values())
