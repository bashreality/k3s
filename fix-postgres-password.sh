#!/bin/bash
# Skrypt do naprawy problemu z hasłem PostgreSQL w CloudNativePG

set -e

echo "=== NAPRAWA HASŁA POSTGRESQL ==="
echo ""

# Sprawdź czy k3s działa
if command -v k3s &> /dev/null; then
    export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
    KUBECTL="k3s kubectl"
elif command -v kubectl &> /dev/null; then
    KUBECTL="kubectl"
else
    echo "❌ Nie znaleziono kubectl ani k3s"
    exit 1
fi

echo "✅ Używam: $KUBECTL"
echo ""

# Sprawdź aktualny stan
echo "1. Sprawdzam CloudNativePG cluster..."
$KUBECTL get cluster -n plusworkflow postgres-cluster &>/dev/null
if [ $? -ne 0 ]; then
    echo "❌ CloudNativePG cluster nie istnieje"
    echo "   Uruchom: $KUBECTL apply -f manifest-10-postgres-cloudnativepg.yaml"
    exit 1
fi
echo "✅ CloudNativePG cluster istnieje"
echo ""

# Sprawdź secrety
echo "2. Sprawdzam secrety..."
echo ""
echo "Secret postgres-secret (używany przez aplikację):"
$KUBECTL get secret -n plusworkflow postgres-secret -o jsonpath='{.data.password}' | base64 -d
echo ""
echo ""
echo "Secret postgres-secret-cnpg (używany przez CloudNativePG):"
$KUBECTL get secret -n plusworkflow postgres-secret-cnpg -o jsonpath='{.data.password}' 2>/dev/null | base64 -d || echo "(nie istnieje)"
echo ""
echo ""

# Sprawdź które hasło jest w bazie
echo "3. Sprawdzam hasło w CloudNativePG..."
PRIMARY_POD=$($KUBECTL get pods -n plusworkflow -l cnpg.io/cluster=postgres-cluster,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ -z "$PRIMARY_POD" ]; then
    echo "❌ Nie znaleziono primary poda PostgreSQL"
    exit 1
fi
echo "Primary pod: $PRIMARY_POD"
echo ""

# Test połączenia z różnymi hasłami
echo "4. Testuję połączenie z hasłem 'postgres'..."
$KUBECTL exec -n plusworkflow $PRIMARY_POD -- env PGPASSWORD=postgres psql -U postgres -d plusworkflow -c "SELECT 1;" &>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Hasło 'postgres' działa!"
    echo ""
    echo "Problem jest gdzie indziej - hasło jest OK."
    echo "Sprawdź czy aplikacja używa właściwego secretu."
    exit 0
else
    echo "❌ Hasło 'postgres' NIE działa"
fi
echo ""

# CloudNativePG generuje własne hasło - sprawdźmy
echo "5. Sprawdzam hasło wygenerowane przez CloudNativePG..."
CNPG_SECRET=$($KUBECTL get cluster -n plusworkflow postgres-cluster -o jsonpath='{.status.secretsResourceVersion.superuserSecretVersion}' 2>/dev/null)
if [ ! -z "$CNPG_SECRET" ]; then
    echo "CloudNativePG używa secretu z hasłem..."
    # CloudNativePG tworzy własny secret: postgres-cluster-superuser
    $KUBECTL get secret -n plusworkflow postgres-cluster-superuser &>/dev/null
    if [ $? -eq 0 ]; then
        echo "Secret postgres-cluster-superuser istnieje"
        CNPG_PASSWORD=$($KUBECTL get secret -n plusworkflow postgres-cluster-superuser -o jsonpath='{.data.password}' | base64 -d)
        echo "Hasło z CloudNativePG: $CNPG_PASSWORD"
    fi
fi
echo ""

echo "=== ROZWIĄZANIA ==="
echo ""
echo "Masz 3 opcje:"
echo ""
echo "OPCJA 1: Usuń i utwórz ponownie CloudNativePG cluster z poprawnym hasłem"
echo "  $KUBECTL delete cluster -n plusworkflow postgres-cluster"
echo "  $KUBECTL delete pvc -n plusworkflow -l cnpg.io/cluster=postgres-cluster"
echo "  $KUBECTL apply -f manifest-10-postgres-cloudnativepg.yaml"
echo ""
echo "OPCJA 2: Zmień hasło w PostgreSQL na 'postgres'"
echo "  $KUBECTL exec -n plusworkflow $PRIMARY_POD -- psql -U postgres -c \"ALTER USER postgres WITH PASSWORD 'postgres';\""
echo ""
echo "OPCJA 3: Zaktualizuj secret aplikacji aby używał hasła z CloudNativePG"
echo "  (wymaga poznania faktycznego hasła z bazy)"
echo ""
echo "Która opcja preferujesz? (1/2/3)"
