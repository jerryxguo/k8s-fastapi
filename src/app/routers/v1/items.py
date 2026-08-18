"""Generic example CRUD endpoints.

Deliberately domain-agnostic placeholder logic -- the point of this router
is to demonstrate routing/versioning/DI conventions and give the deployment
pipeline something real to build, containerize, and roll out.
"""

from fastapi import APIRouter, Depends, HTTPException

from app.dependencies import get_item_store
from app.schemas.common import ItemCreateRequest, ItemResponse
from app.service.item_store import InMemoryItemStore

router = APIRouter(prefix="/items", tags=["items"])


@router.post("", response_model=ItemResponse, status_code=201)
def create_item(
    payload: ItemCreateRequest,
    store: InMemoryItemStore = Depends(get_item_store),
) -> ItemResponse:
    item = store.create(name=payload.name, description=payload.description)
    return ItemResponse(
        id=item.id, name=item.name, description=item.description, status=item.status
    )


@router.get("", response_model=list[ItemResponse])
def list_items(store: InMemoryItemStore = Depends(get_item_store)) -> list[ItemResponse]:
    return [
        ItemResponse(id=i.id, name=i.name, description=i.description, status=i.status)
        for i in store.list()
    ]


@router.get("/{item_id}", response_model=ItemResponse)
def get_item(item_id: str, store: InMemoryItemStore = Depends(get_item_store)) -> ItemResponse:
    item = store.get(item_id)
    if item is None:
        raise HTTPException(status_code=404, detail="item not found")
    return ItemResponse(
        id=item.id, name=item.name, description=item.description, status=item.status
    )
