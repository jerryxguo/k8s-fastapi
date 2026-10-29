"""Application settings.

A pydantic-settings model tree, populated from environment variables at
container start -- fully self-contained: no dependency on any internal or
private settings package.

Config is injected as environment variables by Kubernetes (from a
ConfigMap), and secrets are injected as environment variables sourced from
AWS Secrets Manager via the External Secrets Operator (see
`infra/k8s/helm/fastapi-service/templates/`), using the pod's IRSA identity
rather than an app-level AWS SDK client. That keeps this settings module a
plain `pydantic-settings` reader with no AWS SDK calls at all. The Celery
broker (ElastiCache Redis) follows the same pattern: its URL, auth token
included, is just another secret env var (APP_REDIS_URL).
"""

from enum import Enum
from functools import lru_cache

from pydantic import Field, SecretStr, model_validator
from pydantic_settings import BaseSettings, SettingsConfigDict


class Environment(str, Enum):
    LOCAL = "local"
    DEVELOPMENT = "development"
    PRODUCTION = "production"


class QueueBackend(str, Enum):
    MEMORY = "memory"
    REDIS = "redis"


class Settings(BaseSettings):
    """Top-level app settings, sourced from environment variables.

    Naming (`APP_SERVICE_NAME`, `APP_NAME_PREFIX`, `APP_ENV`, `APP_REGION`)
    matches the env-var contract populated by the Helm chart's ConfigMap.
    """

    model_config = SettingsConfigDict(env_prefix="APP_", extra="ignore")

    service_name: str = Field(default="k8s-demo-service")
    name_prefix: str = Field(default="k8s-demo-dev")
    env: Environment = Field(default=Environment.LOCAL)
    region: str = Field(default="ap-southeast-2")
    log_level: str = Field(default="INFO")

    # Example of a "business" setting an app like this would normally read
    # from a ConfigMap/Secret rather than hardcoding.
    example_upstream_url: str = Field(default="https://example.invalid")
    example_upstream_timeout_seconds: float = Field(default=5.0)

    # Celery broker (see app.worker). "memory" runs tasks eagerly inline, for
    # tests and quick local runs; "redis" is a real broker -- ElastiCache in
    # deployed environments, where the API enqueues and the worker
    # Deployment consumes, or a local `docker run redis` for a two-process
    # local setup.
    queue_backend: QueueBackend = Field(default=QueueBackend.MEMORY)
    # e.g. rediss://:<token>@<host>:6379/0 (TLS) or redis://localhost:6379/0.
    # SecretStr: it embeds the auth token, so it must never reach logs/reprs.
    # Deployed environments get it from the ESO-synced Kubernetes Secret
    # (Terraform writes it to Secrets Manager as ${name_prefix}/redis).
    redis_url: SecretStr | None = Field(default=None)
    # How long an unacked (in-progress) task stays reserved before Redis
    # hands it to another worker. Must exceed the longest task run, retry
    # countdowns included, or a still-running task is executed twice.
    celery_visibility_timeout_seconds: int = Field(default=300, ge=30, le=43200)

    @model_validator(mode="after")
    def _require_redis_url(self) -> "Settings":
        if self.queue_backend is QueueBackend.REDIS and not self.redis_url:
            raise ValueError("APP_REDIS_URL is required when APP_QUEUE_BACKEND=redis")
        return self


@lru_cache
def get_settings() -> Settings:
    return Settings()
