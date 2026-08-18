"""Generic example category endpoints.

Dummy counterpart to the items router -- same domain-agnostic placeholder
logic, mounted under the shared `/v1` prefix defined in `routers.v1`.
"""

from fastapi import APIRouter, Depends, HTTPException

from app.dependencies import get_category_store
from app.schemas.common import CategoryCreateRequest, CategoryResponse
from app.service.category_store import InMemoryCategoryStore

router = APIRouter(prefix="/categories", tags=["categories"])


@router.post("", response_model=CategoryResponse, status_code=201)
def create_category(
    payload: CategoryCreateRequest,
    store: InMemoryCategoryStore = Depends(get_category_store),
) -> CategoryResponse:
    category = store.create(name=payload.name, description=payload.description)
    return CategoryResponse(
        id=category.id,
        name=category.name,
        description=category.description,
        status=category.status,
    )


@router.get("", response_model=list[CategoryResponse])
def list_categories(
    store: InMemoryCategoryStore = Depends(get_category_store),
) -> list[CategoryResponse]:
    return [
        CategoryResponse(id=c.id, name=c.name, description=c.description, status=c.status)
        for c in store.list()
    ]


@router.get("/{category_id}", response_model=CategoryResponse)
def get_category(
    category_id: str,
    store: InMemoryCategoryStore = Depends(get_category_store),
) -> CategoryResponse:
    category = store.get(category_id)
    if category is None:
        raise HTTPException(status_code=404, detail="category not found")
    return CategoryResponse(
        id=category.id,
        name=category.name,
        description=category.description,
        status=category.status,
    )
