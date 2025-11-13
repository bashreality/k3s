#!/bin/bash

# Skrypt do ponownej instalacji CloudNativePG (usuwa stare i instaluje nowe)

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

print_warning "To usunie istniejącą instalację CloudNativePG i zainstaluje ją ponownie"
read -p "Wpisz 'TAK' aby kontynuować: " confirm

if [ "$confirm" != "TAK" ]; then
    print_info "Anulowano"
    exit 0
fi

print_info "1. Usuwam istniejącą instalację CloudNativePG..."
kubectl delete -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml --ignore-not-found=true 2>/dev/null || true

print_info "2. Czekam 10 sekund..."
sleep 10

print_info "3. Sprawdzam czy namespace cnpg-system istnieje..."
if kubectl get namespace cnpg-system &> /dev/null; then
    print_warning "Namespace cnpg-system istnieje, sprawdzam zawartość..."
    kubectl get all -n cnpg-system
    read -p "Usunąć namespace cnpg-system? (TAK/NIE): " delete_ns
    if [ "$delete_ns" = "TAK" ]; then
        kubectl delete namespace cnpg-system --ignore-not-found=true
        sleep 5
    fi
fi

print_info "4. Instaluję CloudNativePG Operator ponownie..."
kubectl apply --validate=false -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml

print_info "5. Czekam na gotowość operatora (może zająć 2-3 minuty)..."
sleep 10

# Czekaj na namespace
for i in {1..30}; do
    if kubectl get namespace cnpg-system &> /dev/null; then
        break
    fi
    echo -n "."
    sleep 2
done
echo ""

# Czekaj na pody
print_info "Czekam na pody operatora..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=cloudnative-pg -n cnpg-system --timeout=300s 2>/dev/null || {
    print_warning "Pody mogą jeszcze się uruchamiać..."
    kubectl get pods -n cnpg-system
}

print_info "6. Sprawdzam status..."
kubectl get pods -n cnpg-system
kubectl get svc -n cnpg-system

print_info "7. Sprawdzam CRD..."
if kubectl get crd clusters.postgresql.cnpg.io &> /dev/null; then
    print_success "CloudNativePG Operator zainstalowany!"
    print_info "Poczekaj 1-2 minuty na webhook, potem uruchom:"
    echo "  kubectl apply -f manifest-10-postgres-cloudnativepg.yaml"
else
    print_error "CRD nie został utworzony. Sprawdź logi:"
    echo "  kubectl logs -n cnpg-system -l app.kubernetes.io/name=cloudnative-pg"
fi

