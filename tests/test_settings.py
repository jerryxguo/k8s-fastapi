import ssl

import pytest
from pydantic import ValidationError

from app.settings import QueueBackend, Settings
from app.worker import create_celery

TLS_URL = "rediss://:s3cret-token@master.k8s-demo-dev-redis.abc123.apse2.cache.amazonaws.com:6379/0"


def test_defaults_to_eager_in_memory_celery(monkeypatch):
    monkeypatch.delenv("APP_QUEUE_BACKEND", raising=False)
    settings = Settings()
    assert settings.queue_backend is QueueBackend.MEMORY
    conf = create_celery(settings).conf
    assert conf.task_always_eager is True
    assert conf.broker_url == "memory://"


def test_redis_backend_requires_url(monkeypatch):
    monkeypatch.setenv("APP_QUEUE_BACKEND", "redis")
    monkeypatch.delenv("APP_REDIS_URL", raising=False)
    with pytest.raises(ValidationError, match="APP_REDIS_URL"):
        Settings()


def test_redis_url_is_never_rendered(monkeypatch):
    monkeypatch.setenv("APP_QUEUE_BACKEND", "redis")
    monkeypatch.setenv("APP_REDIS_URL", TLS_URL)
    settings = Settings()
    assert "s3cret-token" not in repr(settings)
    assert "s3cret-token" not in str(settings.model_dump())


def test_redis_tls_celery_config(monkeypatch):
    monkeypatch.setenv("APP_QUEUE_BACKEND", "redis")
    monkeypatch.setenv("APP_REDIS_URL", TLS_URL)
    conf = create_celery(Settings()).conf

    assert conf.broker_url == TLS_URL
    assert conf.task_always_eager is False
    assert conf.broker_use_ssl == {"ssl_cert_reqs": ssl.CERT_REQUIRED}
    assert conf.broker_transport_options["visibility_timeout"] == 300
    assert conf.task_acks_late is True
    assert conf.worker_prefetch_multiplier == 1


def test_plain_redis_for_local_dev_skips_tls(monkeypatch):
    monkeypatch.setenv("APP_QUEUE_BACKEND", "redis")
    monkeypatch.setenv("APP_REDIS_URL", "redis://localhost:6379/0")
    assert not create_celery(Settings()).conf.broker_use_ssl
