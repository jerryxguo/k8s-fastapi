"""Vulnerability ingestion endpoint.

Validates scanner webhooks and hands them to the Celery worker, returning
202 as soon as the message is on the queue -- enrichment runs on the worker
node group, never in this API pod.
"""

from fastapi import APIRouter, status
from fastapi.concurrency import run_in_threadpool

from app.enqueue import broker_unavailable_as_503
from app.instrumentation import log_latency
from app.schemas.vulnerability import VulnerabilityIngestAccepted, VulnerabilityIngestPayload
from app.worker import process_vulnerability_task

router = APIRouter(prefix="/vulnerabilities", tags=["vulnerabilities"])


@router.post(
    "/ingest",
    response_model=VulnerabilityIngestAccepted,
    status_code=status.HTTP_202_ACCEPTED,
    summary="Ingest raw vulnerability finding",
)
@log_latency("vulnerabilities.ingest")
async def ingest_vulnerability(payload: VulnerabilityIngestPayload) -> VulnerabilityIngestAccepted:
    # mode="json" turns the Severity enum into a plain string for the
    # Celery JSON serializer.
    task_payload = payload.model_dump(mode="json")
    # Enqueue onto the Redis broker. `.delay()` is a blocking network call
    # (redis-py), so it runs in the threadpool rather than stalling this
    # worker's event loop. The `with` covers only the enqueue, so nothing
    # else here can be misreported as a broker outage.
    with broker_unavailable_as_503(f"finding for asset {payload.asset_id}"):
        task = await run_in_threadpool(process_vulnerability_task.delay, task_payload)
    return VulnerabilityIngestAccepted(task_id=task.id)
