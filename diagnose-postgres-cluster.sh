#!/bin/bash

# Skrypt diagnostyczny dla problemu z CloudNativePG Cluster

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

echo "=== DIAGNOSTYKA POSTGRES CLUSTER ==="
echo ""

print_info "1. Sprawdzam CloudNativePG Cluster..."
kubectl get cluster postgres-cluster -n plusworkflow -o wide 2>&1 || echo "Cluster nie istnieje!"
echo ""

print_info "2. Sprawdzam pody CloudNativePG..."
kubectl get pods -n plusworkflow | grep postgres-cluster
echo ""

print_info "3. Sprawdzam OSTATNI błędny pod initdb..."
FAILED_POD=$(kubectl get pods -n plusworkflow | grep "postgres-cluster.*initdb.*Error" | tail -1 | awk '{print $1}')
if [ -n "$FAILED_POD" ]; then
    print_warning "Znaleziono błędny pod: $FAILED_POD"
    echo ""
    print_info "Logi z $FAILED_POD:"
    echo "========================================"
    kubectl logs $FAILED_POD -n plusworkflow 2>&1 | tail -50
    echo "========================================"
    echo ""

    print_info "Events dla $FAILED_POD:"
    kubectl describe pod $FAILED_POD -n plusworkflow | grep -A 20 "Events:" | tail -20
else
    print_success "Brak błędnych podów initdb"
fi
echo ""

print_info "4. Sprawdzam secret postgres-secret-cnpg..."
if kubectl get secret postgres-secret-cnpg -n plusworkflow &> /dev/null; then
    print_success "Secret postgres-secret-cnpg istnieje"
    echo "Typ: $(kubectl get secret postgres-secret-cnpg -n plusworkflow -o jsonpath='{.type}')"
    echo "Klucze: $(kubectl get secret postgres-secret-cnpg -n plusworkflow -o jsonpath='{.data}' | grep -o '"[^"]*":' | tr -d '":' | tr '\n' ' ')"
else
    print_error "Secret postgres-secret-cnpg NIE istnieje!"
fi
echo ""

print_info "5. Sprawdzam konflikty z innym PostgreSQL..."
print_warning "Wykryto następujące PostgreSQL deployments/statefulsets:"
kubectl get statefulset -n plusworkflow | grep postgres || echo "Brak"
echo ""

print_info "6. Sprawdzam PVC..."
kubectl get pvc -n plusworkflow | grep postgres-cluster
echo ""

print_info "7. Sprawdzam operator CloudNativePG..."
kubectl get pods -n cnpg-system
echo ""

print_info "8. Sprawdzam logi operatora CloudNativePG (ostatnie 30 linii)..."
echo "========================================"
kubectl logs -n cnpg-system deployment/cnpg-controller-manager --tail=30 2>&1 | tail -30
echo "========================================"
echo ""

print_info "=== ANALIZA ==="
echo ""

# Analiza konfliktu
POSTGRES_STATEFULSET=$(kubectl get statefulset postgres -n plusworkflow 2>&1)
if echo "$POSTGRES_STATEFULSET" | grep -q "postgres"; then
    print_error "PROBLEM: Masz równolegle uruchomiony stary StatefulSet 'postgres'!"
    echo ""
    print_warning "CloudNativePG i stary StatefulSet mogą kolidować (porty, serwisy, PVC)."
    echo ""
    print_info "ROZWIĄZANIE 1: Usuń stary StatefulSet postgres:"
    echo "  kubectl delete statefulset postgres -n plusworkflow"
    echo "  kubectl delete svc postgres postgres-primary -n plusworkflow"
    echo ""
    print_info "ROZWIĄZANIE 2: Usuń CloudNativePG Cluster i użyj starego:"
    echo "  kubectl delete cluster postgres-cluster -n plusworkflow"
    echo ""
fi

# Analiza secret
if ! kubectl get secret postgres-secret-cnpg -n plusworkflow &> /dev/null; then
    print_error "PROBLEM: Brak secret postgres-secret-cnpg!"
    echo ""
    print_info "ROZWIĄZANIE: Utwórz secret:"
    echo "  kubectl apply -f manifest-02-postgres-secret-cnpg.yaml"
    echo ""
fi

# Sprawdź czy initdb używa poprawnego secret
CLUSTER_SECRET=$(kubectl get cluster postgres-cluster -n plusworkflow -o jsonpath='{.spec.bootstrap.initdb.secret.name}' 2>&1)
if [ "$CLUSTER_SECRET" != "postgres-secret-cnpg" ]; then
    print_warning "Cluster używa innego secret: $CLUSTER_SECRET"
fi

echo ""
print_info "=== SUGEROWANE DZIAŁANIA ==="
echo ""
echo "1. Sprawdź logi powyżej, szczególnie z initdb poda"
echo "2. Jeśli widzisz konflikt portów/serwisów, usuń stary StatefulSet postgres"
echo "3. Jeśli widzisz błędy autentykacji, sprawdź secret"
echo "4. Usuń błędne pody initdb (zostaną odtworzone):"
echo "   kubectl delete pod -n plusworkflow -l cnpg.io/cluster=postgres-cluster,cnpg.io/jobRole=initdb"
echo "5. Jeśli to nie pomoże, usuń cały cluster i stwórz od nowa:"
echo "   kubectl delete cluster postgres-cluster -n plusworkflow"
echo "   kubectl apply -f manifest-10-postgres-cloudnativepg.yaml"
echo ""
