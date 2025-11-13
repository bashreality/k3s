#!/bin/bash

# Skrypt instalacji Longhorn dla k3s
# Longhorn obsługuje ReadWriteMany (RWX) volumes

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

print_info() {
    echo -e "${BLUE}[INFO]${NC} $1"
}

print_success() {
    echo -e "${GREEN}[OK]${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}[UWAGA]${NC} $1"
}

print_error() {
    echo -e "${RED}[BŁĄD]${NC} $1"
}

print_info "Instalacja Longhorn dla k3s..."
print_info "Longhorn obsługuje ReadWriteMany (RWX) volumes"

# Sprawdź czy kubectl działa
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl nie jest zainstalowany!"
    exit 1
fi

# Sprawdź czy Longhorn już jest zainstalowany
if kubectl get storageclass longhorn &> /dev/null; then
    print_warning "Longhorn już jest zainstalowany!"
    kubectl get storageclass longhorn
    exit 0
fi

print_info "1. Instaluję Longhorn..."
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.3/deploy/longhorn.yaml

print_info "2. Czekam na gotowość Longhorn (może zająć 2-3 minuty)..."
kubectl wait --for=condition=ready pod -l app=longhorn-manager -n longhorn-system --timeout=300s

print_info "3. Sprawdzam status..."
kubectl get pods -n longhorn-system

print_info "4. Sprawdzam storage class..."
sleep 10
if kubectl get storageclass longhorn &> /dev/null; then
    print_success "Longhorn zainstalowany pomyślnie!"
    kubectl get storageclass longhorn
    echo ""
    print_info "Longhorn UI będzie dostępne przez:"
    echo "  kubectl port-forward -n longhorn-system svc/longhorn-frontend 8080:80"
    echo "  Następnie otwórz: http://localhost:8080"
else
    print_warning "Storage class jeszcze nie jest gotowy, poczekaj chwilę..."
    print_info "Sprawdź status: kubectl get storageclass longhorn"
fi

