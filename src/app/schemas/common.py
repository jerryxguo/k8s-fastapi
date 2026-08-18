"""Shared enums/schemas for the example API.

Centralizes shared enums used across request/response models.
"""

from enum import Enum

from pydantic import BaseModel, Field


class ItemStatus(str, Enum):
    PENDING = "pending"
    ACTIVE = "active"
    ARCHIVED = "archived"


class CategoryStatus(str, Enum):
    ACTIVE = "active"
    ARCHIVED = "archived"


class HealthResponse(BaseModel):
    message: str = "OK"
    service: str
    version: str


class ItemCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)


class ItemResponse(BaseModel):
    id: str
    name: str
    description: str | None = None
    status: ItemStatus = ItemStatus.PENDING


class CategoryCreateRequest(BaseModel):
    name: str = Field(..., min_length=1, max_length=200)
    description: str | None = Field(default=None, max_length=2000)


class CategoryResponse(BaseModel):
    id: str
    name: str
    description: str | None = None
    status: CategoryStatus = CategoryStatus.ACTIVE
