#!/bin/bash

# Skrypt instalacji CloudNativePG Operator
# CloudNativePG zapewnia automatyczną replikację PostgreSQL z failover

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

print_info "Instalacja CloudNativePG Operator..."
print_info "CloudNativePG zapewnia automatyczną replikację PostgreSQL z failover"

# Sprawdź czy kubectl działa
if ! command -v kubectl &> /dev/null; then
    print_error "kubectl nie jest zainstalowany!"
    exit 1
fi

# Sprawdź połączenie z klastrem
print_info "Sprawdzam połączenie z klastrem..."
if ! kubectl cluster-info &> /dev/null && ! kubectl get nodes &> /dev/null; then
    print_error "Nie można połączyć się z klastrem Kubernetes!"
    print_info "Dla k3s upewnij się że:"
    echo "  1. k3s jest uruchomiony: sudo systemctl status k3s"
    echo "  2. KUBECONFIG jest ustawiony: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
    echo "  3. Lub skopiuj: sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && sudo chown \$USER ~/.kube/config"
    exit 1
fi
print_success "Połączenie z klastrem OK"

# Sprawdź czy operator już jest zainstalowany
if kubectl get crd clusters.postgresql.cnpg.io &> /dev/null; then
    print_warning "CloudNativePG Operator już jest zainstalowany!"
    kubectl get crd clusters.postgresql.cnpg.io
    exit 0
fi

# Sprawdź wersję Kubernetes (CloudNativePG wymaga >= 1.23)
K8S_VERSION=$(kubectl version --client -o json 2>/dev/null | grep -oP '"gitVersion": "\K[^"]+' | cut -d. -f2 || echo "0")
if [ "$K8S_VERSION" -lt 23 ]; then
    print_warning "CloudNativePG wymaga Kubernetes >= 1.23"
    print_info "Sprawdzam wersję klastra..."
    kubectl version
fi

print_info "1. Instaluję CloudNativePG Operator (wersja 1.22.0)..."
print_info "Pobieram manifest..."

# Dla k3s często trzeba wyłączyć walidację (problem z OpenAPI validation)
# Używamy --validate=false aby uniknąć problemów z walidacją
print_info "Instaluję z wyłączoną walidacją (wymagane dla k3s)..."
kubectl apply --validate=false -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml || {
    print_warning "Instalacja przez URL nie powiodła się, pobieram lokalnie..."
    # Alternatywa: pobierz i zastosuj lokalnie
    if command -v curl &> /dev/null; then
        print_info "Pobieram manifest do /tmp..."
        curl -L -o /tmp/cnpg-1.22.0.yaml https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml
        print_info "Zastosowuję manifest..."
        kubectl apply --validate=false -f /tmp/cnpg-1.22.0.yaml
        rm -f /tmp/cnpg-1.22.0.yaml
    elif command -v wget &> /dev/null; then
        print_info "Pobieram manifest do /tmp..."
        wget -O /tmp/cnpg-1.22.0.yaml https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml
        print_info "Zastosowuję manifest..."
        kubectl apply --validate=false -f /tmp/cnpg-1.22.0.yaml
        rm -f /tmp/cnpg-1.22.0.yaml
    else
        print_error "curl i wget nie są zainstalowane. Zainstaluj ręcznie:"
        echo ""
        echo "  kubectl apply --validate=false -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml"
        echo ""
        exit 1
    fi
}

print_info "2. Czekam na gotowość operatora (może zająć 1-2 minuty)..."
kubectl wait --for=condition=available deployment/cnpg-controller-manager -n cnpg-system --timeout=180s 2>/dev/null || \
kubectl wait --for=condition=ready pod -l control-plane=controller-manager -n cnpg-system --timeout=180s

print_info "3. Czekam na webhook service (wymagane dla Cluster)..."
# Czekaj na webhook service - może zająć dodatkowe 30-60 sekund
WEBHOOK_READY=0
for i in {1..30}; do
    if kubectl get svc cnpg-webhook-service -n cnpg-system &> /dev/null; then
        print_success "Webhook service jest gotowy"
        WEBHOOK_READY=1
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

if [ $WEBHOOK_READY -eq 0 ]; then
    print_warning "Webhook service jeszcze nie jest gotowy, ale kontynuuję..."
    print_info "Jeśli wystąpi błąd 'webhook service not found', poczekaj 1-2 minuty i spróbuj ponownie"
fi

print_info "4. Sprawdzam status..."
kubectl get pods -n cnpg-system
kubectl get svc -n cnpg-system | grep cnpg || print_warning "Serwisy webhook mogą jeszcze się inicjalizować"

print_info "5. Sprawdzam CRD..."
if kubectl get crd clusters.postgresql.cnpg.io &> /dev/null; then
    print_success "CloudNativePG Operator zainstalowany pomyślnie!"
    kubectl get crd | grep cnpg
    echo ""
    print_info "Następny krok: Utwórz Cluster używając manifest-10-postgres-cloudnativepg.yaml"
    print_info "  kubectl apply -f manifest-10-postgres-cloudnativepg.yaml"
    echo ""
    if [ $WEBHOOK_READY -eq 0 ]; then
        print_warning "UWAGA: Poczekaj 1-2 minuty przed utworzeniem Cluster, aby webhook był gotowy"
    fi
else
    print_warning "CRD jeszcze nie jest gotowy, poczekaj chwilę..."
    print_info "Sprawdź status: kubectl get crd clusters.postgresql.cnpg.io"
fi

