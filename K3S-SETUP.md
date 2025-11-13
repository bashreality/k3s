# Konfiguracja k3s dla PlusWorkflow

## Problem z połączeniem do klastra

Jeśli widzisz błąd: `[BŁĄD] Nie można połączyć się z klastrem Kubernetes!`

To oznacza, że `kubectl` nie może połączyć się z k3s. Oto jak to naprawić:

## Rozwiązanie

### 1. Sprawdź czy k3s działa

```bash
# Linux
sudo systemctl status k3s

# Windows (WSL)
sudo service k3s status
```

Jeśli nie działa, uruchom:
```bash
sudo systemctl start k3s
# lub
sudo service k3s start
```

### 2. Skonfiguruj kubeconfig

K3s przechowuje konfigurację w `/etc/rancher/k3s/k3s.yaml`. Musisz skopiować ją do `~/.kube/config`:

**Linux:**
```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER ~/.kube/config
chmod 600 ~/.kube/config
```

**Windows (WSL/Git Bash):**
```bash
mkdir -p ~/.kube
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
chmod 600 ~/.kube/config
```

**Lub ustaw zmienną środowiskową:**
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
```

Aby ustawić na stałe, dodaj do `~/.bashrc` lub `~/.zshrc`:
```bash
echo 'export KUBECONFIG=/etc/rancher/k3s/k3s.yaml' >> ~/.bashrc
source ~/.bashrc
```

### 3. Sprawdź połączenie

```bash
kubectl get nodes
```

Powinieneś zobaczyć coś w stylu:
```
NAME           STATUS   ROLES                  AGE   VERSION
k3s-server     Ready    control-plane,master   1d    v1.28.x+k3s1
```

### 4. Sprawdź czy masz uprawnienia

Jeśli widzisz błąd uprawnień:
```bash
# Sprawdź czy możesz wykonać podstawowe polecenia
kubectl get pods --all-namespaces
```

Jeśli nie działa, może być potrzebne:
```bash
sudo chmod 644 /etc/rancher/k3s/k3s.yaml
```

## Użycie skryptu deploy.sh z k3s

Po skonfigurowaniu kubeconfig, skrypt `deploy.sh` powinien działać normalnie:

```bash
./deploy.sh deploy
```

Skrypt automatycznie wykryje k3s i użyje odpowiednich sprawdzeń.

## Troubleshooting

### Problem: "The connection to the server localhost:6443 was refused"

**Rozwiązanie:**
```bash
# Sprawdź czy k3s działa
sudo systemctl status k3s

# Jeśli nie działa, uruchom
sudo systemctl start k3s

# Sprawdź porty
sudo netstat -tlnp | grep 6443
```

### Problem: "permission denied" przy kopiowaniu k3s.yaml

**Rozwiązanie:**
```bash
# Użyj sudo
sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config
sudo chown $USER:$USER ~/.kube/config
```

### Problem: Skrypt działa, ale kubectl nie działa w terminalu

**Rozwiązanie:**
Upewnij się, że zmienna KUBECONFIG jest ustawiona w tym samym terminalu:
```bash
export KUBECONFIG=/etc/rancher/k3s/k3s.yaml
kubectl get nodes
```

## Weryfikacja instalacji k3s

Sprawdź czy wszystkie komponenty k3s działają:

```bash
# Sprawdź pody systemowe
kubectl get pods -n kube-system

# Sprawdź storage class (powinien być local-path)
kubectl get storageclass

# Sprawdź serwisy systemowe
kubectl get svc -n kube-system
```

## Następne kroki

Po skonfigurowaniu k3s:

1. **Zainstaluj storage class dla RWX** (jeśli potrzebujesz współdzielonych volumes):
   ```bash
   # Longhorn (najprostsze dla k3s)
   kubectl apply -f https://raw.githubusercontent.com/longhorn/longhorn/v1.5.3/deploy/longhorn.yaml
   ```

2. **Uruchom deployment:**
   ```bash
   ./deploy.sh deploy
   ```

3. **Sprawdź status:**
   ```bash
   ./deploy.sh status
   ```

