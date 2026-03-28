.PHONY: install update status clean argocd-password port-forward-grafana port-forward-argocd

KUBECONFIG ?= /etc/rancher/k3s/k3s.yaml
export KUBECONFIG

# ============================================================================
# K3s Homelab Makefile
# ============================================================================

install: ## Bootstrap the entire cluster
	@echo ">>> Bootstrapping K3s homelab..."
	@sudo bash bootstrap/install.sh
	@echo ">>> Done!"

update: ## Update all ArgoCD applications
	@echo ">>> Syncing all ArgoCD applications..."
	@kubectl -n argocd get applications -o name | xargs -I {} kubectl -n argocd patch {} --type merge -p '{"operation":{"initiatedBy":{"username":"admin"},"sync":{"revision":"HEAD"}}}'
	@echo ">>> Sync triggered for all applications"

status: ## Show cluster status
	@echo "\n=== Nodes ==="
	@kubectl get nodes -o wide
	@echo "\n=== Pods (all namespaces) ==="
	@kubectl get pods -A --sort-by=.metadata.namespace
	@echo "\n=== Services ==="
	@kubectl get svc -A | grep -v ClusterIP
	@echo "\n=== ArgoCD Applications ==="
	@kubectl -n argocd get applications 2>/dev/null || echo "ArgoCD not installed"
	@echo "\n=== PVCs ==="
	@kubectl get pvc -A
	@echo ""

argocd-password: ## Get ArgoCD admin password
	@kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d && echo

port-forward-grafana: ## Port-forward Grafana to localhost:3000
	@echo ">>> Grafana available at http://localhost:3000"
	@kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80

port-forward-argocd: ## Port-forward ArgoCD to localhost:8443
	@echo ">>> ArgoCD available at https://localhost:8443"
	@kubectl -n argocd port-forward svc/argocd-server 8443:443

clean: ## Remove K3s and all data (DESTRUCTIVE)
	@echo ">>> WARNING: This will destroy the entire cluster!"
	@read -p "Are you sure? [y/N] " confirm && [ "$$confirm" = "y" ] || exit 1
	@/usr/local/bin/k3s-uninstall.sh
	@echo ">>> Cluster removed"

help: ## Show this help
	@grep -E '^[a-zA-Z_-]+:.*?## .*$$' $(MAKEFILE_LIST) | sort | awk 'BEGIN {FS = ":.*?## "}; {printf "\033[36m%-25s\033[0m %s\n", $$1, $$2}'

.DEFAULT_GOAL := help
