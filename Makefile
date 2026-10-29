.PHONY: install lock test lint fmt build run down venv dev tf-fmt tf-validate helm-lint

BUILD_VERSION ?= dev

# Pants itself isn't installed by this Makefile -- install the launcher once
# per machine (see README.md's "Local development" section), which then
# self-bootstraps the exact toolchain version pants.toml pins on first use.
install:
	@echo "Install the Pants launcher once (see README.md), then run 'make lock'."

lock:
	pants generate-lockfiles

test:
	pants test ::

lint:
	pants lint check ::

fmt:
	pants fmt ::

build:
	BUILD_VERSION=$(BUILD_VERSION) pants package src/app:docker

# API + Celery worker + Redis as separate containers (docker-compose.yml).
run: build
	docker compose up

down:
	docker compose down

DEV_PORT ?= 8000
VENV = $(firstword $(wildcard dist/export/python/virtualenvs/k8s_python_default/*))
DEV_ENV = PYTHONPATH=src APP_ENV=local APP_QUEUE_BACKEND=redis APP_REDIS_URL=redis://localhost:$${REDIS_PORT:-6379}/0
# Expanded in recipes, after the venv prerequisite has run.
CHECK_VENV = $(if $(VENV),,$(error No exported venv under dist/export; run: rm -f dist/export/.venv-stamp && make venv))

# Re-export when the lockfile or interpreter constraints (pants.toml) are
# newer than the venv. Remove the old export first so VENV never picks a
# stale interpreter directory.
dist/export/.venv-stamp: src/requirements.lock pants.toml
	rm -rf dist/export/python/virtualenvs/k8s_python_default
	pants export --resolve=k8s_python_default
	@touch $@

venv: dist/export/.venv-stamp

# API + Celery worker on the host (live reload), Redis in Docker. Redis keeps
# running after Ctrl-C; `make down` removes it. If either the API or the
# worker exits, the other is stopped too.
dev: venv
	$(CHECK_VENV)docker compose up -d --wait redis
	@trap 'kill 0' INT TERM; \
	$(DEV_ENV) $(VENV)/bin/python -m uvicorn app.main:app --reload --reload-dir src --port $(DEV_PORT) & \
	api=$$!; \
	$(DEV_ENV) $(VENV)/bin/python -m watchfiles --filter python \
		'$(VENV)/bin/python -m celery --app=app.worker worker --loglevel=INFO --pool=solo --without-gossip --without-mingle' src & \
	worker=$$!; \
	while kill -0 $$api 2>/dev/null && kill -0 $$worker 2>/dev/null; do sleep 1; done; \
	kill $$api $$worker 2>/dev/null; wait; exit 1

tf-fmt:
	terraform fmt -recursive infra/terraform

tf-validate:
	@for d in infra/terraform/live/*; do \
		echo "==> validating $$d"; \
		terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
		terraform -chdir=$$d validate || exit 1; \
	done

helm-lint:
	helm lint infra/k8s/helm/fastapi-service
	helm lint infra/k8s/helm/cluster-secret-store --set region=ap-southeast-2
	@for env in dev prod; do \
		echo "==> template check: $$env"; \
		helm template fastapi-service infra/k8s/helm/fastapi-service \
			-f infra/k8s/helm/fastapi-service/values.yaml \
			-f infra/k8s/helm/fastapi-service/values-$$env.yaml > /dev/null || exit 1; \
	done
	@echo "==> template check: cluster-secret-store"
	@helm template cluster-secret-store infra/k8s/helm/cluster-secret-store \
		--set region=ap-southeast-2 > /dev/null
