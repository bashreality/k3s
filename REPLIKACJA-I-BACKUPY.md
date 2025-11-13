# Replikacja PostgreSQL i Współdzielony Volume PlusWorkflow

## 📋 Przegląd Rozwiązań

### 1. PostgreSQL - Replikacja bez Operatora

**Obecna sytuacja:** Masz 3 repliki PostgreSQL, ale wszystkie są `primary` - nie ma prawdziwej replikacji danych.

**Proponowane rozwiązania (od najprostszego):**

#### Opcja A: CloudNativePG Operator (ZALECANE dla produkcji)
- ✅ Prostszy niż Zalando Operator
- ✅ Automatyczny failover
- ✅ Backup i restore wbudowane
- ✅ Streaming replication out-of-the-box
- ⚠️ Wymaga instalacji operatora

**Instalacja:**
```bash
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml
```

**Przykładowy manifest:**
```yaml
apiVersion: postgresql.cnpg.io/v1
kind: Cluster
metadata:
  name: postgres-cluster
  namespace: plusworkflow
spec:
  instances: 3
  postgresql:
    parameters:
      max_connections: "200"
  storage:
    size: 20Gi
    storageClass: local-path
  resources:
    requests:
      memory: "1Gi"
      cpu: "500m"
    limits:
      memory: "2Gi"
      cpu: "2000m"
```

#### Opcja B: Prosty Streaming Replication (manifest-08-postgres-replication-simple.yaml)
- ✅ Bez operatora
- ✅ Prostsza konfiguracja
- ⚠️ Ręczne zarządzanie failover
- ⚠️ Wymaga dodatkowej konfiguracji użytkownika replicator

**Uwaga:** Ten manifest wymaga:
1. Utworzenia użytkownika replicator w PostgreSQL:
```sql
CREATE USER replicator WITH REPLICATION PASSWORD 'replicator_password';
```

2. Aktualizacji secret z hasłem replicator:
```yaml
# W manifest-02-postgres-secret.yaml dodaj:
stringData:
  replicator_password: replicator_password
```

#### Opcja C: Zalando Postgres Operator
- ✅ Pełna funkcjonalność
- ⚠️ Bardzo skomplikowany
- ⚠️ Wymaga dużo zasobów
- ⚠️ Overkill dla małych/średnich środowisk

**Rekomendacja:** CloudNativePG (Opcja A) - najlepszy balans prostoty i funkcjonalności.

---

### 2. PlusWorkflow Home - Współdzielony Volume

**Problem:** Obecnie każda instancja PlusWorkflow ma własny volume (ReadWriteOnce), więc nie współdzielą danych.

**Rozwiązanie:** Zmiana na `ReadWriteMany` (RWX) - już zaktualizowane w `manifest-07-plusworkflow-statefulset.yaml`.

**⚠️ WAŻNE:** Storage class `local-path` **NIE obsługuje** ReadWriteMany!

**Musisz zainstalować NFS provisioner:**

#### Instalacja NFS Client Provisioner (dla k3s)

```bash
# 1. Zainstaluj NFS provisioner
helm repo add nfs-subdir-external-provisioner https://kubernetes-sigs.github.io/nfs-subdir-external-provisioner/
helm install nfs-subdir-external-provisioner nfs-subdir-external-provisioner/nfs-subdir-external-provisioner \
  --set nfs.server=<TWÓJ_NFS_SERVER> \
  --set nfs.path=/exported/path \
  --set storageClass.name=nfs-client \
  --set storageClass.defaultClass=true

# 2. Sprawdź czy storage class został utworzony
kubectl get storageclass nfs-client
```

**Alternatywy dla NFS:**
- **Longhorn** (dla k3s) - obsługuje RWX, łatwa instalacja
- **CephFS** - bardziej skomplikowany, ale bardzo wydajny
- **GlusterFS** - alternatywa dla NFS

**Instalacja Longhorn (najprostsze dla k3s):**
```bash
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.3/deploy/longhorn.yaml

# Po instalacji zmień storageClassName w manifest-07 na: longhorn
```

---

### 3. Ochrona Danych - Backupy

**Utworzony manifest:** `manifest-09-postgres-backup-cronjob.yaml`

**Funkcjonalności:**
- ✅ Automatyczne backupy codziennie o 2:00
- ✅ Kompresja (gzip)
- ✅ Automatyczne usuwanie backupów starszych niż 30 dni
- ✅ Ręczny backup na żądanie (Job)

**Użycie:**

```bash
# Zastosuj backupy
kubectl apply -f manifest-09-postgres-backup-cronjob.yaml

# Sprawdź status CronJob
kubectl get cronjob -n plusworkflow

# Zobacz historię backupów
kubectl get jobs -n plusworkflow | grep postgres-backup

# Ręczny backup
kubectl create job --from=cronjob/postgres-backup postgres-backup-now -n plusworkflow

# Lista backupów (w podzie)
kubectl exec -it $(kubectl get pod -n plusworkflow -l job-name=postgres-backup-manual -o jsonpath='{.items[0].metadata.name}') -- ls -lh /backups
```

**Przywracanie z backupu:**
```bash
# Skopiuj backup z poda
kubectl cp <pod-name>:/backups/plusworkflow_20240101_020000.sql.gz ./backup.sql.gz -n plusworkflow

# Przywróć
kubectl exec -it postgres-0 -n plusworkflow -- \
  sh -c 'gunzip < /path/to/backup.sql.gz | psql -U postgres -d plusworkflow'
```

---

### 4. Sticky Sessions - LoadBalancer

**Status:** ✅ Już skonfigurowane!

W `manifest-06-plusworkflow-services.yaml` masz:
```yaml
sessionAffinity: ClientIP
```

To zapewnia, że ten sam klient zawsze trafia do tej samej instancji PlusWorkflow, co jest wymagane dla cache.

**Sprawdzenie:**
```bash
kubectl get svc plusworkflow-lb -n plusworkflow -o yaml | grep sessionAffinity
```

---

## 🚀 Plan Wdrożenia

### Krok 1: Backup Obecnych Danych
```bash
# Ręczny backup przed zmianami
kubectl apply -f manifest-09-postgres-backup-cronjob.yaml
kubectl create job --from=cronjob/postgres-backup postgres-backup-before-migration -n plusworkflow
```

### Krok 2: Instalacja Storage Class dla RWX
```bash
# Wybierz jedną opcję:
# A) Longhorn (najprostsze)
kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.3/deploy/longhorn.yaml

# B) NFS Provisioner (jeśli masz NFS server)
helm install nfs-subdir-external-provisioner ...
```

### Krok 3: Zmiana PlusWorkflow na RWX
```bash
# Edytuj manifest-07-plusworkflow-statefulset.yaml
# Zmień storageClassName na: longhorn (lub nfs-client)

# Usuń obecny StatefulSet (zachowaj PVC jeśli chcesz zachować dane)
kubectl delete statefulset plusworkflow -n plusworkflow

# Zastosuj nowy manifest
kubectl apply -f manifest-07-plusworkflow-statefulset.yaml
```

### Krok 4: Replikacja PostgreSQL (opcjonalne)
```bash
# Opcja A: CloudNativePG (ZALECANE)
kubectl apply -f https://raw.githubusercontent.com/cloudnative-pg/cloudnative-pg/release-1.22/releases/cnpg-1.22.0.yaml
# Następnie utwórz Cluster manifest (zobacz przykład powyżej)

# Opcja B: Prosty streaming replication
# 1. Utwórz użytkownika replicator w PostgreSQL
# 2. Zastosuj manifest-08-postgres-replication-simple.yaml
```

---

## ⚠️ Uwagi i Ostrzeżenia

1. **ReadWriteMany wymaga odpowiedniego storage class** - `local-path` nie działa!
2. **Replikacja PostgreSQL** - CloudNativePG jest prostszy niż Zalando Operator
3. **Backupy** - Regularnie sprawdzaj czy działają: `kubectl get cronjob -n plusworkflow`
4. **Sticky sessions** - Już skonfigurowane, nie wymaga zmian
5. **Testowanie** - Przetestuj failover i restore w środowisku testowym przed produkcją

---

## 📚 Przydatne Linki

- **CloudNativePG:** https://cloudnative-pg.io/
- **Longhorn:** https://longhorn.io/
- **NFS Provisioner:** https://github.com/kubernetes-sigs/nfs-subdir-external-provisioner
- **PostgreSQL Streaming Replication:** https://www.postgresql.org/docs/current/high-availability.html

