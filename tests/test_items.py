def test_create_and_get_item(client):
    resp = client.post("/v1/items", json={"name": "widget", "description": "an example item"})
    assert resp.status_code == 201
    created = resp.json()
    assert created["name"] == "widget"
    assert created["status"] == "pending"

    resp = client.get(f"/v1/items/{created['id']}")
    assert resp.status_code == 200
    assert resp.json()["id"] == created["id"]


def test_list_items(client):
    client.post("/v1/items", json={"name": "a"})
    client.post("/v1/items", json={"name": "b"})
    resp = client.get("/v1/items")
    assert resp.status_code == 200
    assert len(resp.json()) == 2


def test_get_missing_item_404(client):
    resp = client.get("/v1/items/does-not-exist")
    assert resp.status_code == 404


def test_create_item_validation_error(client):
    resp = client.post("/v1/items", json={"name": ""})
    assert resp.status_code == 422
