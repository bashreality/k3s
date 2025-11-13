#!/bin/bash

# Szybkie naprawienie problemu z CloudNativePG initdb

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

NAMESPACE="plusworkflow"

echo "=== NAPRAWIANIE CLOUDNATIVEPG INITDB ==="
echo ""

# 1. Sprawdź ostatni błędny pod
print_info "Sprawdzam błędne pody initdb..."
FAILED_POD=$(kubectl get pods -n $NAMESPACE | grep "postgres-cluster.*initdb.*Error" | tail -1 | awk '{print $1}')

if [ -z "$FAILED_POD" ]; then
    print_success "Brak błędnych podów initdb!"
    kubectl get pods -n $NAMESPACE | grep postgres-cluster
    exit 0
fi

print_warning "Znaleziono błędny pod: $FAILED_POD"
echo ""

# 2. Pokaż logi
print_info "Logi z $FAILED_POD:"
echo "========================================"
kubectl logs $FAILED_POD -n $NAMESPACE 2>&1 | tail -50
echo "========================================"
echo ""

# 3. Analiza problemu
print_info "Analizuję problem..."
LOGS=$(kubectl logs $FAILED_POD -n $NAMESPACE 2>&1)

if echo "$LOGS" | grep -qi "permission denied\|cannot access"; then
    print_error "PROBLEM: Brak uprawnień do PVC!"
    echo ""
    print_info "ROZWIĄZANIE: Usuń PVC i pozwól CloudNativePG utworzyć nowe:"
    echo "  kubectl delete pvc postgres-cluster-1 -n $NAMESPACE"
    echo "  kubectl delete cluster postgres-cluster -n $NAMESPACE"
    echo "  kubectl apply -f manifest-10-postgres-cloudnativepg.yaml"

elif echo "$LOGS" | grep -qi "database.*already exists\|directory.*not empty"; then
    print_error "PROBLEM: Baza danych już istnieje na PVC!"
    echo ""
    print_info "ROZWIĄZANIE: Usuń PVC i zacznij od nowa:"
    echo "  kubectl delete cluster postgres-cluster -n $NAMESPACE"
    echo "  kubectl delete pvc postgres-cluster-1 -n $NAMESPACE"
    echo "  kubectl apply -f manifest-10-postgres-cloudnativepg.yaml"

elif echo "$LOGS" | grep -qi "secret.*not found"; then
    print_error "PROBLEM: Secret nie istnieje!"
    echo ""
    print_info "ROZWIĄZANIE: Utwórz secret:"
    echo "  kubectl apply -f manifest-02-postgres-secret-cnpg.yaml"

elif echo "$LOGS" | grep -qi "cannot mount\|attach"; then
    print_error "PROBLEM: Nie można zamontować PVC!"
    echo ""
    print_info "ROZWIĄZANIE: Sprawdź czy PVC jest dostępne:"
    echo "  kubectl get pvc postgres-cluster-1 -n $NAMESPACE"
    echo "  kubectl describe pvc postgres-cluster-1 -n $NAMESPACE"

else
    print_warning "Nieznany problem, sprawdź logi powyżej"
fi

echo ""
print_info "=== AUTOMATYCZNE NAPRAWIANIE ==="
echo ""
echo "Mogę automatycznie:"
echo "1. Usunąć cluster i PVC, zacząć od nowa (CZYSTE ŚRODOWISKO)"
echo "2. Tylko usunąć błędne pody initdb (ZACHOWAĆ DANE)"
echo "3. Anulować"
echo ""

read -p "Wybierz opcję (1/2/3): " choice

case $choice in
    1)
        print_warning "To usunie cluster i PVC - WSZYSTKIE DANE ZOSTANĄ UTRACONE!"
        read -p "Wpisz 'TAK' aby kontynuować: " confirm

        if [ "$confirm" != "TAK" ]; then
            print_info "Anulowano"
            exit 0
        fi

        print_info "1/3 Usuwam cluster..."
        kubectl delete cluster postgres-cluster -n $NAMESPACE --ignore-not-found=true

        print_info "2/3 Usuwam PVC..."
        kubectl delete pvc postgres-cluster-1 -n $NAMESPACE --ignore-not-found=true

        print_info "3/3 Czekam 10 sekund..."
        sleep 10

        print_info "Tworzę nowy cluster..."
        kubectl apply -f manifest-10-postgres-cloudnativepg.yaml

        print_success "Gotowe! Sprawdź status:"
        echo "  kubectl get cluster postgres-cluster -n $NAMESPACE"
        echo "  kubectl get pods -n $NAMESPACE | grep postgres-cluster"
        ;;

    2)
        print_info "Usuwam tylko błędne pody initdb..."
        kubectl delete pod -n $NAMESPACE -l cnpg.io/cluster=postgres-cluster,cnpg.io/jobRole=initdb --ignore-not-found=true

        print_success "Gotowe! Nowe pody initdb zostaną utworzone automatycznie"
        print_info "Sprawdź status za 30 sekund:"
        echo "  kubectl get pods -n $NAMESPACE | grep postgres-cluster"
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
