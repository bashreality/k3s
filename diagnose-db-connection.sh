#!/bin/bash
# Skrypt diagnostyczny dla problemu z połączeniem do bazy danych

echo "=== DIAGNOZA POŁĄCZENIA Z BAZĄ DANYCH ==="
echo ""

# Sprawdź czy k3s działa
echo "1. Sprawdzam czy k3s działa..."
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

# Sprawdź namespace
echo "2. Sprawdzam namespace plusworkflow..."
$KUBECTL get namespace plusworkflow &>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Namespace plusworkflow istnieje"
else
    echo "❌ Namespace plusworkflow NIE istnieje"
    echo "   Uruchom: $KUBECTL apply -f manifest-01-namespace.yaml"
    exit 1
fi
echo ""

# Sprawdź CloudNativePG operator
echo "3. Sprawdzam CloudNativePG operator..."
$KUBECTL get deployment -n cnpg-system cnpg-controller-manager &>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ CloudNativePG operator zainstalowany"
    $KUBECTL get pods -n cnpg-system
else
    echo "⚠️  CloudNativePG operator NIE jest zainstalowany"
    echo "   Uruchom: ./install-cloudnativepg.sh"
fi
echo ""

# Sprawdź postgres-cluster
echo "4. Sprawdzam CloudNativePG cluster..."
$KUBECTL get cluster -n plusworkflow postgres-cluster &>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ CloudNativePG cluster istnieje"
    echo ""
    echo "Status klastra:"
    $KUBECTL get cluster -n plusworkflow postgres-cluster
    echo ""
    echo "Pody klastra:"
    $KUBECTL get pods -n plusworkflow -l cnpg.io/cluster=postgres-cluster
else
    echo "❌ CloudNativePG cluster NIE istnieje"
    echo "   Uruchom: $KUBECTL apply -f manifest-10-postgres-cloudnativepg.yaml"
    exit 1
fi
echo ""

# Sprawdź serwisy
echo "5. Sprawdzam serwisy PostgreSQL..."
$KUBECTL get svc -n plusworkflow postgres-cluster-rw &>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Service postgres-cluster-rw istnieje"
    $KUBECTL get svc -n plusworkflow | grep postgres-cluster
else
    echo "❌ Service postgres-cluster-rw NIE istnieje"
    echo "   CloudNativePG cluster prawdopodobnie nie jest gotowy"
fi
echo ""

# Sprawdź secret
echo "6. Sprawdzam secrety..."
$KUBECTL get secret -n plusworkflow postgres-secret &>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Secret postgres-secret istnieje"
else
    echo "❌ Secret postgres-secret NIE istnieje"
    echo "   Uruchom: $KUBECTL apply -f manifest-02-postgres-secret.yaml"
fi

$KUBECTL get secret -n plusworkflow postgres-secret-cnpg &>/dev/null
if [ $? -eq 0 ]; then
    echo "✅ Secret postgres-secret-cnpg istnieje"
else
    echo "❌ Secret postgres-secret-cnpg NIE istnieje"
    echo "   Uruchom: $KUBECTL apply -f manifest-02-postgres-secret-cnpg.yaml"
fi
echo ""

# Sprawdź pody PlusWorkflow
echo "7. Sprawdzam pody PlusWorkflow..."
$KUBECTL get pods -n plusworkflow -l app=plusworkflow
echo ""

# Test połączenia z wewnątrz klastra
echo "8. Test połączenia z bazą danych..."
POD=$($KUBECTL get pods -n plusworkflow -l cnpg.io/cluster=postgres-cluster,cnpg.io/instanceRole=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$POD" ]; then
    echo "Testuję połączenie z podem: $POD"
    $KUBECTL exec -n plusworkflow $POD -- psql -U postgres -d plusworkflow -c "SELECT version();" 2>/dev/null
    if [ $? -eq 0 ]; then
        echo "✅ Połączenie z bazą działa"
    else
        echo "❌ Nie można połączyć się z bazą"
    fi
else
    echo "⚠️  Nie znaleziono primary poda PostgreSQL"
fi
echo ""

# Sprawdź logi init container
echo "9. Sprawdzam logi init container (wait-for-db)..."
PLUSWORKFLOW_POD=$($KUBECTL get pods -n plusworkflow -l app=plusworkflow -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
if [ ! -z "$PLUSWORKFLOW_POD" ]; then
    echo "Pod: $PLUSWORKFLOW_POD"
    echo "Logi init container:"
    $KUBECTL logs -n plusworkflow $PLUSWORKFLOW_POD -c wait-for-db --tail=20
fi
echo ""

echo "=== KONIEC DIAGNOZY ==="
