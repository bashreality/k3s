#!/bin/bash
# Szybka naprawa - zmiana hasła PostgreSQL na 'postgres'

set -e

if command -v k3s &> /dev/null; then
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    KUBECTL="k3s kubectl"
elif command -v kubectl &> /dev/null; then
    KUBECTL="kubectl"
else
    echo "❌ Nie znaleziono kubectl ani k3s"
    exit 1
fi

echo "=== SZYBKA NAPRAWA HASŁA ==="
echo ""

# Znajdź primary pod
PRIMARY_POD=$($KUBECTL get pods -n plusworkflow -l cnpg.io/cluster=postgres-cluster,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)

if [ -z "$PRIMARY_POD" ]; then
    echo "❌ Nie znaleziono primary poda PostgreSQL"
    exit 1
fi

echo "Primary pod: $PRIMARY_POD"
echo ""

# Pobierz aktualne hasło z CloudNativePG
echo "1. Sprawdzam aktualne hasło CloudNativePG..."
CNPG_PASSWORD=$($KUBECTL get secret -n plusworkflow postgres-cluster-superuser -o jsonpath='{.data.password}' 2>/dev/null | base64 -d)

if [ -z "$CNPG_PASSWORD" ]; then
    echo "⚠️  Nie znaleziono hasła w postgres-cluster-superuser"
    echo "   Próbuję bez hasła (trust authentication)..."

    # Zmień hasło bez podawania starego
    echo ""
    echo "2. Zmieniam hasło na 'postgres'..."
    $KUBECTL exec -n plusworkflow $PRIMARY_POD -- psql -U postgres -c "ALTER USER postgres WITH PASSWORD 'postgres';"

    if [ $? -eq 0 ]; then
        echo "✅ Hasło zmienione!"
    else
        echo "❌ Nie udało się zmienić hasła"
        exit 1
    fi
else
    echo "Aktualne hasło: $CNPG_PASSWORD"
    echo ""
    echo "2. Zmieniam hasło na 'postgres'..."
    $KUBECTL exec -n plusworkflow $PRIMARY_POD -- env PGPASSWORD="$CNPG_PASSWORD" psql -U postgres -c "ALTER USER postgres WITH PASSWORD 'postgres';"

    if [ $? -eq 0 ]; then
        echo "✅ Hasło zmienione!"
    else
        echo "❌ Nie udało się zmienić hasła"
        exit 1
    fi
fi

echo ""
echo "3. Testuję nowe hasło..."
$KUBECTL exec -n plusworkflow $PRIMARY_POD -- env PGPASSWORD=postgres psql -U postgres -d plusworkflow -c "SELECT version();"

if [ $? -eq 0 ]; then
    echo ""
    echo "✅ SUKCES! Hasło działa."
    echo ""
    echo "Teraz zrestartuj pody PlusWorkflow:"
    echo "  $KUBECTL rollout restart statefulset -n plusworkflow plusworkflow"
else
    echo ""
    echo "❌ Hasło nadal nie działa"
    exit 1
fi
