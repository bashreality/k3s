#!/bin/bash

# Skrypt do migracji ze starego PostgreSQL StatefulSet na CloudNativePG Cluster

set -e

RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

NAMESPACE="plusworkflow"

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

echo "=== MIGRACJA DO CLOUDNATIVEPG ==="
echo ""
print_warning "Ten skrypt pomoże ci przejść ze starego PostgreSQL StatefulSet na CloudNativePG"
echo ""

# Sprawdź co jest aktualnie zainstalowane
print_info "Sprawdzam aktualny stan..."
echo ""

OLD_STATEFULSET=$(kubectl get statefulset postgres -n $NAMESPACE 2>&1 || echo "")
OLD_SERVICES=$(kubectl get svc postgres postgres-primary -n $NAMESPACE 2>&1 || echo "")
CNPG_CLUSTER=$(kubectl get cluster postgres-cluster -n $NAMESPACE 2>&1 || echo "")

if echo "$OLD_STATEFULSET" | grep -q "postgres"; then
    print_warning "Znaleziono STARY StatefulSet 'postgres'"
    kubectl get statefulset postgres -n $NAMESPACE
    echo ""
fi

if echo "$OLD_SERVICES" | grep -q "postgres"; then
    print_warning "Znaleziono STARE serwisy 'postgres' i 'postgres-primary'"
    kubectl get svc postgres postgres-primary -n $NAMESPACE 2>&1 || true
    echo ""
fi

if echo "$CNPG_CLUSTER" | grep -q "postgres-cluster"; then
    print_info "Znaleziono CloudNativePG Cluster 'postgres-cluster'"
    kubectl get cluster postgres-cluster -n $NAMESPACE
    echo ""
fi

# Analiza
print_info "=== ANALIZA ==="
echo ""

CONFLICT=0
if echo "$OLD_STATEFULSET" | grep -q "postgres" && echo "$CNPG_CLUSTER" | grep -q "postgres-cluster"; then
    print_error "KONFLIKT: Masz jednocześnie stary StatefulSet i CloudNativePG Cluster!"
    print_warning "To powoduje konflikty nazw, portów i serwisów."
    CONFLICT=1
fi

if echo "$OLD_SERVICES" | grep -q "postgres"; then
    print_warning "Stare serwisy 'postgres' i 'postgres-primary' mogą kolidować z CloudNativePG"
    CONFLICT=1
fi

if [ $CONFLICT -eq 0 ]; then
    print_success "Nie wykryto konfliktów"
    exit 0
fi

echo ""
print_info "=== OPCJE MIGRACJI ==="
echo ""
echo "1. Usuń stary StatefulSet i zostaw CloudNativePG (ZALECANE)"
echo "2. Usuń CloudNativePG i zostaw stary StatefulSet"
echo "3. Anuluj"
echo ""

read -p "Wybierz opcję (1/2/3): " choice

case $choice in
    1)
        print_info "Opcja 1: Przejście na CloudNativePG"
        echo ""
        print_warning "To usunie stary StatefulSet 'postgres' i jego serwisy"
        print_warning "Dane NIE zostaną usunięte (PVC zachowane)"
        echo ""
        read -p "Wpisz 'TAK' aby kontynuować: " confirm

        if [ "$confirm" != "TAK" ]; then
            print_info "Anulowano"
            exit 0
        fi

        print_info "1/4 Usuwam stare serwisy postgres i postgres-primary..."
        kubectl delete svc postgres postgres-primary -n $NAMESPACE --ignore-not-found=true
        print_success "Serwisy usunięte"

        print_info "2/4 Usuwam stary StatefulSet postgres (zachowuję PVC)..."
        kubectl delete statefulset postgres -n $NAMESPACE --cascade=orphan --ignore-not-found=true
        print_success "StatefulSet usunięty"

        print_info "3/4 Czekam 10 sekund..."
        sleep 10

        print_info "4/4 Sprawdzam CloudNativePG Cluster..."
        if kubectl get cluster postgres-cluster -n $NAMESPACE &> /dev/null; then
            print_success "CloudNativePG Cluster istnieje"
            kubectl get cluster postgres-cluster -n $NAMESPACE

            # Usuń błędne pody initdb jeśli istnieją
            FAILED_PODS=$(kubectl get pods -n $NAMESPACE | grep "postgres-cluster.*initdb.*Error" || echo "")
            if [ -n "$FAILED_PODS" ]; then
                print_info "Usuwam błędne pody initdb..."
                kubectl delete pod -n $NAMESPACE -l cnpg.io/cluster=postgres-cluster,cnpg.io/jobRole=initdb --ignore-not-found=true
                print_success "Błędne pody usunięte, nowe zostaną utworzone automatycznie"
            fi
        else
            print_warning "CloudNativePG Cluster nie istnieje, tworzę..."
            kubectl apply -f manifest-10-postgres-cloudnativepg.yaml
        fi

        echo ""
        print_success "Migracja zakończona!"
        print_info "CloudNativePG tworzy automatycznie serwisy:"
        echo "  - postgres-cluster-rw   (read-write, primary)"
        echo "  - postgres-cluster-ro   (read-only, replicas)"
        echo "  - postgres-cluster-r    (read, dla replikacji)"
        echo ""
        print_info "Połącz się używając:"
        echo "  Host: postgres-cluster-rw.plusworkflow.svc.cluster.local"
        echo "  Port: 5432"
        echo ""
        print_info "Sprawdź status:"
        echo "  kubectl get cluster postgres-cluster -n $NAMESPACE"
        echo "  kubectl get pods -n $NAMESPACE | grep postgres-cluster"
        ;;

    2)
        print_info "Opcja 2: Zostaw stary StatefulSet"
        echo ""
        print_warning "To usunie CloudNativePG Cluster"
        echo ""
        read -p "Wpisz 'TAK' aby kontynuować: " confirm

        if [ "$confirm" != "TAK" ]; then
            print_info "Anulowano"
            exit 0
        fi

        print_info "Usuwam CloudNativePG Cluster..."
        kubectl delete cluster postgres-cluster -n $NAMESPACE --ignore-not-found=true
        print_success "CloudNativePG Cluster usunięty"

        print_info "Stary StatefulSet pozostaje aktywny"
        kubectl get statefulset postgres -n $NAMESPACE
        ;;

    3)
        print_info "Anulowano"
        exit 0
        ;;

    *)
        print_error "Nieprawidłowa opcja"
        exit 1
        ;;
esac
