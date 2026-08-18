"""Application settings.

A pydantic-settings model tree, populated from environment variables at
container start -- fully self-contained: no dependency on any internal or
private settings package.

Config is injected as environment variables by Kubernetes (from a
ConfigMap), and secrets are injected as environment variables sourced from
AWS Secrets Manager via the External Secrets Operator (see
`infra/k8s/helm/fastapi-service/templates/`), using the pod's IRSA identity
rather than an app-level AWS SDK client. That keeps this settings module a
plain `pydantic-settings` reader with no AWS SDK calls at all.
"""

from enum import Enum
from functools import lru_cache

from pydantic import Field
from pydantic_settings import BaseSettings, SettingsConfigDict


class Environment(str, Enum):
    LOCAL = "local"
    DEVELOPMENT = "development"
    PRODUCTION = "production"


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


@lru_cache
def get_settings() -> Settings:
    return Settings()
