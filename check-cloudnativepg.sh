#!/bin/bash

# Skrypt diagnostyczny dla CloudNativePG

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

echo "=== DIAGNOSTYKA CLOUDNATIVEPG ==="
echo ""

print_info "1. Sprawdzam CRD CloudNativePG..."
if kubectl get crd clusters.postgresql.cnpg.io &> /dev/null; then
    print_success "CRD CloudNativePG istnieje"
    kubectl get crd | grep cnpg
else
    print_error "CRD CloudNativePG NIE istnieje!"
    print_info "Operator może nie być zainstalowany lub używa innej nazwy"
fi
echo ""

print_info "2. Szukam podów CloudNativePG we wszystkich namespace..."
CNPG_PODS=$(kubectl get pods --all-namespaces -o json | jq -r '.items[] | select(.metadata.name | contains("cnpg") or contains("cloudnative")) | "\(.metadata.namespace)/\(.metadata.name)"' 2>/dev/null || echo "")
if [ -n "$CNPG_PODS" ]; then
    print_success "Znaleziono pody CloudNativePG:"
    echo "$CNPG_PODS"
else
    print_warning "Nie znaleziono podów CloudNativePG"
fi
echo ""

print_info "3. Sprawdzam namespace cnpg-system..."
if kubectl get namespace cnpg-system &> /dev/null; then
    print_success "Namespace cnpg-system istnieje"
    kubectl get all -n cnpg-system
else
    print_warning "Namespace cnpg-system nie istnieje"
fi
echo ""

print_info "4. Sprawdzam wszystkie deploymenty z 'postgres' w nazwie..."
kubectl get deployment --all-namespaces | grep -i postgres || print_warning "Nie znaleziono deploymentów postgres"
echo ""

print_info "5. Sprawdzam wszystkie pody z 'postgres' lub 'cnpg' w nazwie..."
kubectl get pods --all-namespaces | grep -E "postgres|cnpg|cloudnative" || print_warning "Nie znaleziono podów"
echo ""

print_info "6. Sprawdzam serwisy webhook..."
kubectl get svc --all-namespaces | grep -E "webhook|cnpg" || print_warning "Nie znaleziono serwisów webhook"
echo ""

print_info "7. Sprawdzam MutatingWebhookConfiguration..."
kubectl get mutatingwebhookconfiguration | grep -i cnpg || print_warning "Nie znaleziono MutatingWebhookConfiguration dla CNPG"
echo ""

print_info "8. Sprawdzam ValidatingWebhookConfiguration..."
kubectl get validatingwebhookconfiguration | grep -i cnpg || print_warning "Nie znaleziono ValidatingWebhookConfiguration dla CNPG"
echo ""

print_info "9. Sprawdzam co to za 'postgres-operator' w default namespace..."
if kubectl get deployment postgres-operator -n default &> /dev/null 2>&1; then
    print_warning "Znaleziono deployment 'postgres-operator' w default namespace"
    echo ""
    kubectl get deployment postgres-operator -n default -o yaml | grep -A 3 "image:" || \
    kubectl describe deployment postgres-operator -n default | grep -A 3 "Image:"
    echo ""
    print_info "To może być Zalando Postgres Operator, nie CloudNativePG!"
    print_info "CloudNativePG powinien być w namespace 'cnpg-system'"
fi
echo ""

print_info "10. Sprawdzam logi instalacji (jeśli były błędy)..."
if kubectl get events --all-namespaces --sort-by='.lastTimestamp' | grep -i "cnpg\|cloudnative" | tail -10; then
    echo ""
else
    print_warning "Nie znaleziono eventów związanych z CloudNativePG"
fi

echo ""
print_info "=== PODSUMOWANIE ==="
if kubectl get crd clusters.postgresql.cnpg.io &> /dev/null; then
    print_success "CRD CloudNativePG jest zainstalowany"
    print_info "Ale operator może nie być uruchomiony"
    print_info "Spróbuj: kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml"
else
    print_error "CloudNativePG Operator NIE jest zainstalowany!"
    print_info "Zainstaluj: ./install-cloudnativepg.sh"
fi

