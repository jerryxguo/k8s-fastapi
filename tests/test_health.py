def test_healthcheck(client):
    resp = client.get("/healthcheck")
    assert resp.status_code == 200
    body = resp.json()
    assert body["message"] == "OK"
    assert "service" in body
    assert "version" in body
