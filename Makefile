# kube-foundation — developer entry points.
#
# Everything is driven by scripts/devbox.sh (a single script). The Makefile is a
# thin, ergonomic wrapper.
#
SHELL := /bin/bash
DEBOX := ./scripts/devbox.sh

.PHONY: help devbox registry build cluster bootstrap openbao test down clean

help: ## Show available targets
	@echo "kube-foundation"
	@echo ""
	@echo "  make devbox       Full local loop: registry + build + cluster + bootstrap + test"
	@echo "  make registry     Start the local OCI registry (zot)"
	@echo "  make build        Build container images + OCI artifacts"
	@echo "  make cluster      Create the kind cluster"
	@echo "  make bootstrap    Install Flux Operator + FluxInstance + sync"
	@echo "  make openbao      Initialize + unseal + configure OpenBao"
	@echo "  make test         Run reconciliation smoke tests"
	@echo "  make down         Tear down kind + registry"
	@echo "  make clean        Remove local build state (.devbox)"

devbox: registry build cluster bootstrap openbao test ## Full local loop
	@$(DEBOX) registry start
	@$(DEBOX) build
	@$(DEBOX) cluster up
	@$(DEBOX) bootstrap
	@$(DEBOX) openbao
	@$(DEBOX) test

registry: ## Start the local OCI registry (zot)
	@$(DEBOX) registry start

build: ## Build container images and OCI artifacts
	@$(DEBOX) build

cluster: ## Create the kind cluster
	@$(DEBOX) cluster up

bootstrap: ## Install Flux Operator + FluxInstance + sync
	@$(DEBOX) bootstrap

openbao: ## Initialize + unseal + configure OpenBao
	@$(DEBOX) openbao

test: ## Run smoke tests
	@$(DEBOX) test

down: ## Tear down kind cluster + registry
	@$(DEBOX) down

clean: ## Remove local build state
	@$(DEBOX) clean
