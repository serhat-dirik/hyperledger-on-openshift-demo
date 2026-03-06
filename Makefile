SHELL := /bin/bash
.DEFAULT_GOAL := help

.PHONY: all help check-prerequisites deploy install-argocd validate configure-kc lint-helm seed test e2e demo resilience teardown

all: deploy validate ## Full pipeline (deploy + validate)

help: ## Show targets
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-22s\033[0m %s\n", $$1, $$2}'

check-prerequisites: ## Check OpenShift platform readiness
	@bash scripts/check-prerequisites.sh

# ---- Deploy -----------------------------------------------------------------
deploy: ## Deploy CertChain via ArgoCD App-of-Apps
	@bash scripts/deploy-argocd.sh

install-argocd: ## Install ArgoCD operator
	@bash scripts/install-gitops-operator.sh

validate: ## Validate deployment + timing report
	@bash scripts/validate-deployment.sh

configure-kc: ## Configure KC identity brokering (post-deploy)
	@bash scripts/configure-identity-brokering.sh

lint-helm: ## Lint all Helm charts
	@helm lint helm/components/certchain-central && helm lint helm/components/certchain-org && helm lint helm/components/certchain-showroom

# ---- Seed & Test ------------------------------------------------------------
seed: ## Load demo data
	@bash scripts/seed-demo-certificates.sh

test: test-chaincode test-apis test-ui ## All tests

test-chaincode: ## Chaincode tests
	@cd fabric/chaincode/certcontract && go test ./... -v

test-apis: ## Quarkus tests
	@cd apps/cert-admin-api && ./mvnw test && cd ../../apps/verify-api && ./mvnw test

test-ui: ## Frontend tests
	@cd apps/course-manager-ui && npm test && cd ../cert-portal && npm test

e2e: ## End-to-end tests
	@bash scripts/test-end-to-end.sh

demo: ## Interactive demo walkthrough
	@bash scripts/demo-walkthrough.sh

resilience: ## Resilience & self-healing demo
	@bash scripts/resilience-demo.sh

# ---- Cleanup ----------------------------------------------------------------
teardown: ## Remove from cluster
	@bash scripts/teardown-all.sh
