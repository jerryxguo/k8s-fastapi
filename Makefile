.PHONY: install lock test lint fmt build run tf-fmt tf-validate helm-lint

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

run: build
	docker run --rm -p 8080:8080 -e APP_ENV=local k8s-demo-shared/service-api:latest

tf-fmt:
	terraform fmt -recursive infra/terraform

tf-validate:
	@for d in infra/terraform/live/*; do \
		echo "==> validating $$d"; \
		terraform -chdir=$$d init -backend=false -input=false >/dev/null && \
		terraform -chdir=$$d validate; \
	done

helm-lint:
	helm lint infra/k8s/helm/fastapi-service
	@for env in dev prod; do \
		echo "==> template check: $$env"; \
		helm template fastapi-service infra/k8s/helm/fastapi-service \
			-f infra/k8s/helm/fastapi-service/values.yaml \
			-f infra/k8s/helm/fastapi-service/values-$$env.yaml > /dev/null; \
	done
