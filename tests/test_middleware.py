"""Tests for the validation-error handler.

No endpoint currently triggers either path, so without these the next custom
validator would silently reintroduce both bugs.
"""

import asyncio
import json

import pytest
from fastapi import Request
from fastapi.exceptions import RequestValidationError
from pydantic import ValidationError

from app.main import app
from app.middleware import log_validation_errors


def _request(path: str) -> Request:
    return Request(
        {
            "type": "http",
            "method": "POST",
            "scheme": "http",
            "server": ("testserver", 80),
            "path": path,
            "query_string": b"",
            "headers": [],
        }
    )


@pytest.fixture
def validator_error() -> RequestValidationError:
    """What pydantic v2 produces when a validator raises ValueError: `ctx`
    holds a live exception object, which json.dumps cannot serialise."""
    return RequestValidationError(
        [
            {
                "type": "value_error",
                "loc": ("body", "name"),
                "msg": "Value error, name is not allowed",
                "input": "bad",
                "ctx": {"error": ValueError("name is not allowed")},
            }
        ]
    )


def test_non_serialisable_error_context_still_returns_422(validator_error):
    response = asyncio.run(log_validation_errors(_request("/v1/items"), validator_error))

    assert response.status_code == 422

    # Genuinely JSON is the property that was broken.
    body = json.loads(response.body)
    error = body["detail"][0]
    assert error["loc"] == ["body", "name"]
    assert error["msg"] == "Value error, name is not allowed"
    # jsonable_encoder flattens the ValueError to {} rather than raising.
    assert error["ctx"] == {"error": {}}


def test_pydantic_validation_error_is_not_handled_as_a_client_error():
    """A server-side ValidationError must surface as a 500, not a 422."""
    assert ValidationError not in app.exception_handlers
    assert RequestValidationError in app.exception_handlers
