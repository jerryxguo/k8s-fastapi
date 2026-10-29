from unittest import mock

import pytest
from kombu.exceptions import OperationalError

from app.service.vulnerability_service import VulnerabilityService
from app.worker import process_vulnerability_task

VALID = {
    "scanner_id": "scanner-1",
    "asset_id": "i-0abc123",
    "cve_id": "CVE-2026-1234",
    "severity": "HIGH",
    "raw_metadata": {"cvss": 8.1},
}


def test_ingest_enqueues_task_and_returns_202(client):
    # Tests run Celery eagerly (APP_QUEUE_BACKEND=memory), so .delay() executes
    # the task inline -- this exercises API -> task -> service end to end.
    with mock.patch.object(
        VulnerabilityService,
        "process_and_enrich_finding",
        wraps=VulnerabilityService.process_and_enrich_finding,
    ) as spy:
        resp = client.post("/v1/vulnerabilities/ingest", json=VALID)

    assert resp.status_code == 202
    body = resp.json()
    assert body["status"] == "accepted"
    assert body["task_id"]
    spy.assert_called_once_with(VALID)  # enum serialised back to a plain string


@pytest.mark.parametrize(
    "override",
    [
        {"severity": "SEVERE"},
        {"severity": "high"},
        {"cve_id": "2026-1234"},
        {"asset_id": ""},
    ],
)
def test_ingest_rejects_invalid_payload_before_queueing(client, override):
    with mock.patch.object(process_vulnerability_task, "delay") as delay:
        resp = client.post("/v1/vulnerabilities/ingest", json={**VALID, **override})
    assert resp.status_code == 422
    delay.assert_not_called()


def test_ingest_returns_503_when_broker_unreachable(client):
    with mock.patch.object(
        process_vulnerability_task, "delay", side_effect=OperationalError("connection refused")
    ):
        resp = client.post("/v1/vulnerabilities/ingest", json=VALID)
    assert resp.status_code == 503
    assert resp.headers["retry-after"] == "30"


def test_finding_id_is_deterministic_for_idempotent_redelivery():
    first = VulnerabilityService.process_and_enrich_finding(VALID)
    again = VulnerabilityService.process_and_enrich_finding(dict(VALID))
    assert first == again
    assert first != VulnerabilityService.finding_id(VALID["asset_id"], "CVE-2026-9999")
    # No separator collisions between asset and CVE parts.
    assert VulnerabilityService.finding_id("a_b", "c") != VulnerabilityService.finding_id(
        "a", "b_c"
    )


def test_task_returns_finding_id():
    result = process_vulnerability_task.apply(args=[VALID]).get()
    assert result == {
        "status": "success",
        "finding_id": VulnerabilityService.finding_id(VALID["asset_id"], VALID["cve_id"]),
    }


def test_task_autoretries_on_failure():
    # apply() follows the retry inline; on a real worker it's re-queued with
    # exponential backoff instead.
    with mock.patch.object(
        VulnerabilityService, "process_and_enrich_finding", side_effect=[RuntimeError("db"), "f1"]
    ) as service:
        result = process_vulnerability_task.apply(args=[VALID], throw=False)
    assert service.call_count == 2
    assert result.get() == {"status": "success", "finding_id": "f1"}


def test_ingest_logs_latency_and_outcome(client, caplog):
    with caplog.at_level("INFO", logger="app.instrumentation"):
        client.post("/v1/vulnerabilities/ingest", json=VALID)
        with mock.patch.object(
            process_vulnerability_task, "delay", side_effect=OperationalError("down")
        ):
            client.post("/v1/vulnerabilities/ingest", json=VALID)
    messages = [r.getMessage() for r in caplog.records if r.name == "app.instrumentation"]
    assert len(messages) == 2
    assert messages[0].startswith("vulnerabilities.ingest finished in") and "(ok)" in messages[0]
    assert "(HTTPException 503)" in messages[1]


def test_log_latency_keeps_endpoint_signature_for_fastapi():
    import inspect

    from app.routers.v1.vulnerabilities import ingest_vulnerability

    assert list(inspect.signature(ingest_vulnerability).parameters) == ["payload"]


def test_log_latency_rejects_sync_functions():
    from app.instrumentation import log_latency

    with pytest.raises(TypeError):
        log_latency("x")(lambda: None)  # type: ignore[arg-type,return-value]


def test_broker_unavailable_as_503_passes_other_errors_through():
    from fastapi import HTTPException

    from app.enqueue import broker_unavailable_as_503

    with pytest.raises(HTTPException) as caught:
        with broker_unavailable_as_503("thing"):
            raise OperationalError("down")
    assert caught.value.status_code == 503
    assert isinstance(caught.value.__cause__, OperationalError)

    with pytest.raises(ValueError):
        with broker_unavailable_as_503("thing"):
            raise ValueError("not a broker problem")


def test_task_logs_task_id_and_outcome(caplog):
    with caplog.at_level("INFO", logger="app.worker"):
        result = process_vulnerability_task.apply(args=[VALID], task_id="task-123")
    finding_id = result.get()["finding_id"]
    messages = [r.getMessage() for r in caplog.records if r.name == "app.worker"]
    assert messages == [
        "task task-123: processing CVE-2026-1234 on asset i-0abc123 (attempt 1 of 4)",
        f"task task-123: processed finding {finding_id} (CVE-2026-1234 on asset i-0abc123)",
    ]


def test_log_latency_records_cancellation():
    import asyncio

    from app.instrumentation import log_latency

    @log_latency("cancelled.op")
    async def op() -> None:
        raise asyncio.CancelledError

    with mock.patch("app.instrumentation.logger") as logger:
        with pytest.raises(asyncio.CancelledError):
            asyncio.run(op())
    assert logger.info.call_args.args[-1] == "CancelledError"


def test_task_log_handles_unlimited_retries(caplog):
    with mock.patch.object(process_vulnerability_task, "max_retries", None):
        with caplog.at_level("INFO", logger="app.worker"):
            process_vulnerability_task.apply(args=[VALID], task_id="task-u").get()
    assert "(attempt 1 of unlimited)" in caplog.records[0].getMessage()
