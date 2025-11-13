# Manifesty Kubernetes - PlusWorkflow + PostgreSQL

## Kolejność Wdrożenia

Zastosuj manifesty w następującej kolejności:

```bash
# 1. Namespace
kubectl apply -f 01-namespace.yaml

# 2. Sekrety
kubectl apply -f 02-postgres-secret.yaml
# Uwaga: nexus-registry-secret musi już istnieć w namespace plusworkflow

# 3. PostgreSQL
kubectl apply -f 03-postgres-services.yaml
kubectl apply -f 04-postgres-statefulset.yaml

# Poczekaj aż PostgreSQL będzie gotowy
kubectl wait --for=condition=Ready pod/postgres-0 -n plusworkflow --timeout=180s

# 4. PlusWorkflow
kubectl apply -f 05-tomcat-configmap.yaml
kubectl apply -f 06-plusworkflow-services.yaml
kubectl apply -f 07-plusworkflow-statefulset.yaml

# Sprawdź status
kubectl get pods -n plusworkflow -w
```

## Wdrożenie Wszystkiego Naraz

```bash
kubectl apply -f manifests/
```

**Uwaga**: Kolejność może nie być zachowana, pody PlusWorkflow mogą crashować dopóki PostgreSQL się nie uruchomi (będą auto-restartowane).

## Usunięcie Wdrożenia

**Usuń aplikację i bazę (zachowaj PVC):**
```bash
kubectl delete -f manifests/
```

**Usuń wszystko włącznie z danymi:**
```bash
kubectl delete namespace plusworkflow
```

## Wymagania

### Przed wdrożeniem upewnij się że:

1. **Nexus Registry Secret istnieje:**
```bash
kubectl get secret nexus-registry-secret -n plusworkflow
```

Jeśli nie istnieje, stwórz go:
```bash
kubectl create secret docker-registry nexus-registry-secret \
  --docker-server=docker.nexus.test.plusworkflow.pl \
  --docker-username=YOUR_USERNAME \
  --docker-password=YOUR_PASSWORD \
  --docker-email=YOUR_EMAIL \
  -n plusworkflow
```

2. **Storage Class `local-path` istnieje:**
```bash
kubectl get storageclass local-path
```

3. **MetalLB jest skonfigurowany** (dla LoadBalancer):
```bash
kubectl get pods -n metallb-system
```

## Modyfikacja Manifestów

### Zmiana liczby replik

**PostgreSQL (04-postgres-statefulset.yaml):**
```yaml
spec:
  replicas: 5  # Zmień na żądaną liczbę
```

**PlusWorkflow (07-plusworkflow-statefulset.yaml):**
```yaml
spec:
  replicas: 5  # Zmień na żądaną liczbę
```

### Zmiana rozmiaru storage

**PostgreSQL (04-postgres-statefulset.yaml):**
```yaml
volumeClaimTemplates:
  - metadata:
      name: postgres-storage
    spec:
      resources:
        requests:
          storage: 50Gi  # Zmień rozmiar
```

**PlusWorkflow (07-plusworkflow-statefulset.yaml):**
```yaml
volumeClaimTemplates:
  - metadata:
      name: plusworkflow-storage
    spec:
      resources:
        requests:
          storage: 20Gi  # Zmień rozmiar
```

**Uwaga**: Zmiana storage wymaga usunięcia i ponownego utworzenia StatefulSet + PVC.

### Zmiana limitów zasobów

**PostgreSQL (04-postgres-statefulset.yaml):**
```yaml
resources:
  requests:
    memory: "1Gi"    # Minimum
    cpu: "500m"
  limits:
    memory: "2Gi"    # Maximum
    cpu: "2000m"
```

**PlusWorkflow (07-plusworkflow-statefulset.yaml):**
```yaml
resources:
  requests:
    memory: "4Gi"
    cpu: "1000m"
  limits:
    memory: "8Gi"
    cpu: "4000m"
```

### Zmiana hasła PostgreSQL

Edytuj `02-postgres-secret.yaml`:
```yaml
stringData:
  username: postgres
  password: NOWE_HASLO  # Zmień hasło
  database: plusworkflow
```

Zastosuj zmiany:
```bash
kubectl apply -f 02-postgres-secret.yaml
kubectl rollout restart statefulset postgres -n plusworkflow
kubectl rollout restart statefulset plusworkflow -n plusworkflow
```

### Zmiana image PlusWorkflow

Edytuj `07-plusworkflow-statefulset.yaml`:
```yaml
containers:
  - name: plusworkflow
    image: docker.nexus.test.plusworkflow.pl/redhat:NOWY_TAG
```

Lub użyj kubectl:
```bash
kubectl set image statefulset/plusworkflow \
  plusworkflow=docker.nexus.test.plusworkflow.pl/redhat:NOWY_TAG \
  -n plusworkflow
```

## Troubleshooting

### Pody w stanie Pending

Sprawdź PVC:
```bash
kubectl get pvc -n plusworkflow
kubectl describe pvc plusworkflow-storage-plusworkflow-2 -n plusworkflow
```

Sprawdź eventy:
```bash
kubectl describe pod plusworkflow-2 -n plusworkflow
```

### Aplikacja nie może połączyć się z bazą

Sprawdź czy postgres-0 działa:
```bash
kubectl get pod postgres-0 -n plusworkflow
kubectl logs postgres-0 -n plusworkflow
```

Test połączenia:
```bash
kubectl exec -it plusworkflow-0 -n plusworkflow -- \
  bash -c 'apt-get update && apt-get install -y postgresql-client && \
  psql -h postgres-0.postgres -U postgres -d plusworkflow'
```

### LoadBalancer w stanie Pending

Sprawdź MetalLB:
```bash
kubectl get pods -n metallb-system
kubectl logs -n metallb-system -l component=controller
```

Sprawdź czy masz skonfigurowaną pulę IP:
```bash
kubectl get ipaddresspools -n metallb-system
```
