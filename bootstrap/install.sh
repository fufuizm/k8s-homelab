#!/usr/bin/env bash
set -euo pipefail

# ============================================================================
# K3s Homelab Bootstrap Script
# Installs K3s, MetalLB, cert-manager, and ArgoCD on a single-node cluster
# ============================================================================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
REPO_ROOT="$(dirname "$SCRIPT_DIR")"

# --------------- Configuration ---------------
K3S_VERSION="${K3S_VERSION:-v1.29.2+k3s1}"
METALLB_VERSION="${METALLB_VERSION:-v0.14.3}"
CERTMANAGER_VERSION="${CERTMANAGER_VERSION:-v1.14.3}"
ARGOCD_VERSION="${ARGOCD_VERSION:-v2.10.2}"
ARGOCD_NAMESPACE="argocd"
METALLB_NAMESPACE="metallb-system"
CERTMANAGER_NAMESPACE="cert-manager"

# --------------- Colors ---------------
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

log()  { echo -e "${BLUE}[INFO]${NC}  $*"; }
warn() { echo -e "${YELLOW}[WARN]${NC}  $*"; }
err()  { echo -e "${RED}[ERROR]${NC} $*" >&2; }
ok()   { echo -e "${GREEN}[OK]${NC}    $*"; }

# --------------- Pre-flight checks ---------------
preflight() {
  log "Running pre-flight checks..."
  if [[ $EUID -ne 0 ]]; then
    err "This script must be run as root (or with sudo)"
    exit 1
  fi
  for cmd in curl jq; do
    if ! command -v "$cmd" &>/dev/null; then
      warn "$cmd not found, installing..."
      apt-get update -qq && apt-get install -y -qq "$cmd"
    fi
  done
  ok "Pre-flight checks passed"
}

# --------------- Install K3s ---------------
install_k3s() {
  if command -v k3s &>/dev/null; then
    warn "K3s already installed, skipping..."
    return
  fi
  log "Installing K3s ${K3S_VERSION}..."
  curl -sfL https://get.k3s.io | \
    INSTALL_K3S_VERSION="${K3S_VERSION}" \
    INSTALL_K3S_EXEC="server \
      --disable traefik \
      --disable servicelb \
      --write-kubeconfig-mode 644 \
      --tls-san $(hostname -I | awk '{print $1}') \
      --tls-san $(hostname)" \
    sh -
  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
  log "Waiting for K3s to be ready..."
  until kubectl get nodes | grep -q " Ready"; do
    sleep 2
  done
  ok "K3s installed and ready"
}

# --------------- Install MetalLB ---------------
install_metallb() {
  log "Installing MetalLB ${METALLB_VERSION}..."
  kubectl apply -f "https://raw.githubusercontent.com/metallb/metallb/${METALLB_VERSION}/config/manifests/metallb-native.yaml"
  log "Waiting for MetalLB pods..."
  kubectl -n "${METALLB_NAMESPACE}" wait --for=condition=ready pod -l app=metallb --timeout=120s 2>/dev/null || true
  sleep 10
  if [[ -f "${SCRIPT_DIR}/metallb-config.yaml" ]]; then
    log "Applying MetalLB configuration..."
    kubectl apply -f "${SCRIPT_DIR}/metallb-config.yaml"
  fi
  ok "MetalLB installed"
}

# --------------- Install cert-manager ---------------
install_certmanager() {
  log "Installing cert-manager ${CERTMANAGER_VERSION}..."
  kubectl apply -f "https://github.com/cert-manager/cert-manager/releases/download/${CERTMANAGER_VERSION}/cert-manager.yaml"
  log "Waiting for cert-manager pods..."
  kubectl -n "${CERTMANAGER_NAMESPACE}" wait --for=condition=ready pod -l app.kubernetes.io/instance=cert-manager --timeout=120s
  ok "cert-manager installed"
}

# --------------- Install ArgoCD ---------------
install_argocd() {
  log "Installing ArgoCD ${ARGOCD_VERSION}..."
  kubectl create namespace "${ARGOCD_NAMESPACE}" --dry-run=client -o yaml | kubectl apply -f -
  kubectl apply -n "${ARGOCD_NAMESPACE}" -f "https://raw.githubusercontent.com/argoproj/argo-cd/${ARGOCD_VERSION}/manifests/install.yaml"
  log "Waiting for ArgoCD pods..."
  kubectl -n "${ARGOCD_NAMESPACE}" wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server --timeout=180s
  ARGOCD_PASS=$(kubectl -n "${ARGOCD_NAMESPACE}" get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
  ok "ArgoCD installed"
  log "ArgoCD admin password: ${ARGOCD_PASS}"
  log "Access ArgoCD at: https://$(hostname -I | awk '{print $1}'):443"
}

# --------------- Bootstrap App-of-Apps ---------------
bootstrap_gitops() {
  log "Bootstrapping GitOps with App-of-Apps pattern..."
  if [[ -f "${REPO_ROOT}/gitops/app-of-apps.yaml" ]]; then
    kubectl apply -f "${REPO_ROOT}/gitops/app-of-apps.yaml"
    ok "App-of-Apps deployed"
  else
    warn "gitops/app-of-apps.yaml not found, skipping GitOps bootstrap"
  fi
}

# --------------- Main ---------------
main() {
  echo ""
  echo "========================================="
  echo "  K3s Homelab Bootstrap"
  echo "========================================="
  echo ""
  preflight
  install_k3s
  install_metallb
  install_certmanager
  install_argocd
  bootstrap_gitops
  echo ""
  ok "Homelab bootstrap complete!"
  echo ""
  log "Next steps:"
  log "  1. export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
  log "  2. kubectl get nodes"
  log "  3. kubectl -n argocd get applications"
  echo ""
}

main "$@"
