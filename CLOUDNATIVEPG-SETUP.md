# CloudNativePG Operator - Instalacja i Konfiguracja

## 📋 Przegląd

CloudNativePG Operator to nowoczesne rozwiązanie do zarządzania PostgreSQL w Kubernetes:
- ✅ Automatyczna replikacja (streaming replication)
- ✅ Automatyczny failover
- ✅ Backup i restore (wbudowane)
- ✅ Monitoring i health checks
- ✅ Prostszy niż Zalando Operator

## 🚀 Instalacja

### Krok 1: Zainstaluj CloudNativePG Operator

```bash
# Opcja A: Użyj skryptu (najprostsze)
chmod +x install-cloudnativepg.sh
./install-cloudnativepg.sh

# Opcja B: Ręcznie
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml
```

Sprawdź status:
```bash
kubectl get pods -n cnpg-system
kubectl get crd | grep cnpg
```

### Krok 2: Utwórz CloudNativePG Cluster

```bash
# Zastosuj manifest
kubectl apply -f manifest-10-postgres-cloudnativepg.yaml

# Sprawdź status
kubectl get cluster -n plusworkflow
kubectl get pods -n plusworkflow -l cnpg.io/cluster=postgres-cluster
```

### Krok 3: Migracja z istniejącego StatefulSet (opcjonalne)

Jeśli masz już działający StatefulSet PostgreSQL:

```bash
# 1. Backup danych (jeśli jeszcze nie masz)
./deploy.sh backup-create

# 2. Usuń StatefulSet (zachowaj PVC)
kubectl delete statefulset postgres -n plusworkflow --cascade=orphan

# 3. Utwórz CloudNativePG Cluster
kubectl apply -f manifest-10-postgres-cloudnativepg.yaml

# 4. Przywróć dane z backupu (jeśli potrzeba)
# CloudNativePG ma własne narzędzia do restore
```

## 🔧 Konfiguracja

### Zmiana liczby replik

Edytuj `manifest-10-postgres-cloudnativepg.yaml`:
```yaml
spec:
  instances: 5  # Zmień na żądaną liczbę
```

### Zmiana rozmiaru storage

```yaml
spec:
  storage:
    size: 50Gi  # Zmień rozmiar
    storageClass: longhorn  # Zmień storage class
```

### Zmiana zasobów

```yaml
spec:
  resources:
    requests:
      memory: "2Gi"
      cpu: "1000m"
    limits:
      memory: "4Gi"
      cpu: "4000m"
```

## 📊 Monitoring

### Sprawdź status Cluster

```bash
# Status Cluster
kubectl get cluster postgres-cluster -n plusworkflow -o yaml

# Status podów
kubectl get pods -n plusworkflow -l cnpg.io/cluster=postgres-cluster

# Logi
kubectl logs -n plusworkflow -l cnpg.io/cluster=postgres-cluster,role=primary
```

### Sprawdź replikację

```bash
# Lista wszystkich instancji
kubectl get pods -n plusworkflow -l cnpg.io/cluster=postgres-cluster

# Sprawdź role (primary/replica)
kubectl get pods -n plusworkflow -l cnpg.io/cluster=postgres-cluster -o jsonpath='{range .items[*]}{.metadata.name}{"\t"}{.metadata.labels.role}{"\n"}{end}'
```

## 💾 Backupy

### Konfiguracja backupów (S3)

1. Utwórz secret z credentials S3:
```bash
kubectl create secret generic backup-credentials \
  --from-literal=ACCESS_KEY_ID=your_key \
  --from-literal=SECRET_ACCESS_KEY=your_secret \
  -n plusworkflow
```

2. Zastosuj manifest backup:
```bash
kubectl apply -f manifest-11-postgres-cloudnativepg-backup.yaml
```

### Ręczny backup

```bash
# Utwórz backup
kubectl apply -f - <<EOF
apiVersion: postgresql.cnpg.io/v1
kind: Backup
metadata:
  name: postgres-cluster-backup-manual
  namespace: plusworkflow
spec:
  cluster:
    name: postgres-cluster
  method: barmanObjectStore
EOF

# Sprawdź status
kubectl get backup -n plusworkflow
```

### Przywracanie z backupu

```bash
# Lista backupów
kubectl get backup -n plusworkflow

# Przywróć z backupu (wymaga konfiguracji restore)
# Zobacz dokumentację CloudNativePG: https://cloudnative-pg.io/documentation/
```

## 🔄 Failover

CloudNativePG automatycznie zarządza failover. Jeśli primary padnie, automatycznie promuje jedną z replic do primary.

Sprawdź status failover:
```bash
# Sprawdź obecny primary
kubectl get pods -n plusworkflow -l cnpg.io/cluster=postgres-cluster,role=primary

# Sprawdź eventy
kubectl get events -n plusworkflow --sort-by='.lastTimestamp' | grep postgres-cluster
```

## 🔌 Połączenie z aplikacją

CloudNativePG tworzy automatycznie serwisy:
- `postgres-cluster-rw` - Read-Write (primary)
- `postgres-cluster-ro` - Read-Only (replicas)
- `postgres-cluster-r` - Read (wszystkie instancje)

### Aktualizacja PlusWorkflow

W `manifest-07-plusworkflow-statefulset.yaml` zmień:
```yaml
- name: PWFL_DB_HOST
  value: "postgres-cluster-rw"  # CloudNativePG service
```

Lub użyj istniejącego serwisu `postgres-primary` (zaktualizowany w manifest-10).

## 🆚 Porównanie z StatefulSet

| Funkcja | StatefulSet | CloudNativePG |
|---------|-------------|---------------|
| Replikacja | Ręczna konfiguracja | Automatyczna |
| Failover | Ręczny | Automatyczny |
| Backupy | Zewnętrzne (CronJob) | Wbudowane |
| Monitoring | Podstawowy | Zaawansowany |
| Złożoność | Prosta | Średnia |
| Zasoby | Niskie | Średnie |

## 🐛 Troubleshooting

### Cluster nie startuje

```bash
# Sprawdź logi operatora
kubectl logs -n cnpg-system -l control-plane=controller-manager

# Sprawdź status Cluster
kubectl describe cluster postgres-cluster -n plusworkflow

# Sprawdź pody
kubectl describe pod -n plusworkflow -l cnpg.io/cluster=postgres-cluster
```

### Problem z replikacją

```bash
# Sprawdź logi primary
kubectl logs -n plusworkflow -l cnpg.io/cluster=postgres-cluster,role=primary

# Sprawdź logi replica
kubectl logs -n plusworkflow -l cnpg.io/cluster=postgres-cluster,role=replica
```

### Problem z backupami

```bash
# Sprawdź status backupów
kubectl get backup -n plusworkflow
kubectl describe backup <backup-name> -n plusworkflow

# Sprawdź ScheduledBackup
kubectl get scheduledbackup -n plusworkflow
```

## 📚 Przydatne Linki

- **CloudNativePG Dokumentacja:** https://cloudnative-pg.io/documentation/
- **CloudNativePG GitHub:** https://github.com/cloudnative-pg/cloudnative-pg
- **Przykłady:** https://github.com/cloudnative-pg/cloudnative-pg/tree/main/docs/src/samples

## 🔄 Migracja z StatefulSet do CloudNativePG

Pełna instrukcja migracji:

1. **Backup danych:**
   ```bash
   ./deploy.sh backup-create
   ```

2. **Zainstaluj CloudNativePG Operator:**
   ```bash
   ./install-cloudnativepg.sh
   ```

3. **Utwórz nowy Cluster (bez danych):**
   ```bash
   kubectl apply -f manifest-10-postgres-cloudnativepg.yaml
   ```

4. **Przywróć dane:**
   - Użyj `pg_dump` / `pg_restore`
   - Lub użyj CloudNativePG restore (jeśli masz backup w formacie Barman)

5. **Zaktualizuj PlusWorkflow:**
   - Zmień `PWFL_DB_HOST` na `postgres-cluster-rw`
   - Restart aplikacji

6. **Usuń stary StatefulSet:**
   ```bash
   kubectl delete statefulset postgres -n plusworkflow
   ```

