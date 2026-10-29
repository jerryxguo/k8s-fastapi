"""Celery application and tasks.

Imported by both sides: the API enqueues payloads with `.delay()`, and the
worker Deployment runs the same image as `celery -A app.worker worker` on
its own node group (infra/k8s/helm/fastapi-service/templates/
worker-deployment.yaml). Business logic lives in `app.service`, not here --
tasks are thin wrappers.

Broker is Redis: ElastiCache in deployed environments (TLS + auth token,
infra/terraform/modules/elasticache-redis), reached at APP_REDIS_URL. No
AWS SDK or IAM involved -- the URL arrives as a secret env var via the
External Secrets Operator, like every other secret.

There is no result backend: callers get a task ID, not a result. Point
`result_backend` at the same Redis only if something needs task outcomes.

With APP_QUEUE_BACKEND=memory (tests) tasks run eagerly,
inline in the calling process, so no broker or worker process is needed.
"""

import logging
import ssl
from typing import Any

from celery import Celery, Task

from app.service.vulnerability_service import VulnerabilityService
from app.settings import QueueBackend, Settings, get_settings

logger = logging.getLogger(__name__)


def create_celery(settings: Settings) -> Celery:
    app = Celery(settings.service_name)
    app.conf.update(
        task_serializer="json",
        accept_content=["json"],
        timezone="UTC",
        enable_utc=True,
        # At-least-once: a task is acked only after it finishes, so a worker
        # killed mid-task (OOM, node loss) leaves it to be redelivered once
        # the visibility timeout passes. Tasks must therefore be idempotent.
        task_acks_late=True,
        task_reject_on_worker_lost=True,
        # One message per worker process at a time: fair distribution across
        # worker pods, and nothing prefetched into a busy worker.
        worker_prefetch_multiplier=1,
        task_ignore_result=True,  # no result backend
        broker_connection_retry_on_startup=True,
    )

    if settings.queue_backend is QueueBackend.REDIS:
        assert settings.redis_url is not None  # enforced by Settings
        broker_url = settings.redis_url.get_secret_value()
        app.conf.update(
            broker_url=broker_url,
            broker_transport_options={
                # Must exceed the longest task run (retry countdowns
                # included), or Redis restores a still-running task's message
                # and a second worker runs it too.
                "visibility_timeout": settings.celery_visibility_timeout_seconds,
                # Detect half-open connections (e.g. ElastiCache failover)
                # instead of hanging on a dead socket.
                "socket_keepalive": True,
                "health_check_interval": 30,
            },
        )
        if broker_url.startswith("rediss://"):
            # ElastiCache in-transit encryption: verify the server cert
            # against the image's CA bundle (Amazon-issued).
            app.conf.broker_use_ssl = {"ssl_cert_reqs": ssl.CERT_REQUIRED}
    else:
        app.conf.update(
            broker_url="memory://",
            task_always_eager=True,
            task_eager_propagates=True,
        )
    return app


celery_app = create_celery(get_settings())


# Explicit name: it's the message contract between API and worker, so it
# must not change if this module is moved or renamed.
#
# retry_backoff_max stays well below the broker visibility timeout: a retry's
# countdown is held by the worker as an unacked message, and outliving the
# visibility timeout would make Redis redeliver it to another worker as well.
#
# bind=True gives the task its own request context: the task ID (the one
# /ingest returned to the caller) goes into each log line explicitly, so it
# shows in eager mode too, where Celery's worker log format isn't applied.
@celery_app.task(
    bind=True,
    name="vulnerabilities.process",
    autoretry_for=(Exception,),
    retry_backoff=True,
    retry_backoff_max=60,
    retry_jitter=True,
    max_retries=3,
)
def process_vulnerability_task(self: Task, payload: dict[str, Any]) -> dict[str, str]:
    """Enrich and score one finding. Exceptions trigger an automatic retry
    with exponential backoff; after max_retries the task fails and is
    logged by Celery."""
    cve_id, asset_id = payload["cve_id"], payload["asset_id"]
    # max_retries=None means unlimited in Celery; must not break this line.
    max_attempts = "unlimited" if self.max_retries is None else self.max_retries + 1
    logger.info(
        "task %s: processing %s on asset %s (attempt %d of %s)",
        self.request.id,
        cve_id,
        asset_id,
        self.request.retries + 1,
        max_attempts,
    )
    finding_id = VulnerabilityService.process_and_enrich_finding(payload)
    logger.info(
        "task %s: processed finding %s (%s on asset %s)",
        self.request.id,
        finding_id,
        cve_id,
        asset_id,
    )
    return {"status": "success", "finding_id": finding_id}
