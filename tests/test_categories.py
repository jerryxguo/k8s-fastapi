def test_create_and_get_category(client):
    resp = client.post(
        "/v1/categories", json={"name": "widgets", "description": "an example category"}
    )
    assert resp.status_code == 201
    created = resp.json()
    assert created["name"] == "widgets"
    assert created["status"] == "active"

    resp = client.get(f"/v1/categories/{created['id']}")
    assert resp.status_code == 200
    assert resp.json()["id"] == created["id"]


def test_list_categories(client):
    client.post("/v1/categories", json={"name": "a"})
    client.post("/v1/categories", json={"name": "b"})
    resp = client.get("/v1/categories")
    assert resp.status_code == 200
    assert len(resp.json()) >= 2


def test_get_missing_category_404(client):
    resp = client.get("/v1/categories/does-not-exist")
    assert resp.status_code == 404


def test_create_category_validation_error(client):
    resp = client.post("/v1/categories", json={"name": ""})
    assert resp.status_code == 422
