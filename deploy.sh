#!/bin/bash

# Skrypt zarządzający deploymentem PlusWorkflow + PostgreSQL w Kubernetes
# Autor: Auto-generated
# Wersja: 1.0

set -e  # Zatrzymaj przy błędzie

# Kolory dla outputu
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Konfiguracja
NAMESPACE="plusworkflow"
TIMEOUT=300  # 5 minut timeout dla operacji

# Funkcje pomocnicze
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

check_kubectl() {
    if ! command -v kubectl &> /dev/null; then
        print_error "kubectl nie jest zainstalowany!"
        exit 1
    fi
    print_success "kubectl jest dostępny"
}

check_requirements() {
    print_info "Sprawdzam wymagania..."
    
    # Sprawdź połączenie z klastrem (dla k3s używamy prostszego sprawdzenia)
    print_info "Sprawdzam połączenie z klastrem (k3s)..."
    
    # Sprawdź czy kubeconfig jest ustawiony
    if [ -z "$KUBECONFIG" ] && [ ! -f "$HOME/.kube/config" ] && [ ! -f "/etc/rancher/k3s/k3s.yaml" ]; then
        print_warning "Kubeconfig nie znaleziony. Dla k3s możesz potrzebować:"
        echo "  export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
        echo "  lub"
        echo "  mkdir -p ~/.kube && sudo cp /etc/rancher/k3s/k3s.yaml ~/.kube/config && sudo chown \$USER ~/.kube/config"
    fi
    
    # Sprawdź połączenie - użyj prostszego polecenia dla k3s
    if kubectl get nodes &> /dev/null; then
        print_success "Połączenie z klastrem OK"
        # Pokaż informacje o klastrze
        CLUSTER_INFO=$(kubectl cluster-info 2>/dev/null || echo "k3s")
        if [ "$CLUSTER_INFO" != "k3s" ]; then
            print_info "Klaster: $(echo "$CLUSTER_INFO" | head -1)"
        else
            print_info "Klaster: k3s"
        fi
    else
        print_error "Nie można połączyć się z klastrem Kubernetes/k3s!"
        print_info "Sprawdź czy:"
        echo "  1. k3s jest uruchomiony: sudo systemctl status k3s"
        echo "  2. KUBECONFIG jest ustawiony: export KUBECONFIG=/etc/rancher/k3s/k3s.yaml"
        echo "  3. Masz uprawnienia: kubectl get nodes"
        exit 1
    fi
    
    # Sprawdź storage class
    if ! kubectl get storageclass local-path &> /dev/null; then
        print_warning "Storage class 'local-path' nie istnieje!"
        print_info "Sprawdzam dostępne storage classes..."
        kubectl get storageclass
    else
        print_success "Storage class 'local-path' istnieje"
    fi
    
    # Sprawdź nexus-registry-secret (opcjonalnie, jeśli namespace już istnieje)
    if kubectl get namespace $NAMESPACE &> /dev/null; then
        if kubectl get secret nexus-registry-secret -n $NAMESPACE &> /dev/null; then
            print_success "Secret 'nexus-registry-secret' istnieje"
        else
            print_warning "Secret 'nexus-registry-secret' nie istnieje w namespace $NAMESPACE"
            print_info "Utwórz go poleceniem:"
            echo "kubectl create secret docker-registry nexus-registry-secret \\"
            echo "  --docker-server=docker.nexus.test.plusworkflow.pl \\"
            echo "  --docker-username=YOUR_USERNAME \\"
            echo "  --docker-password=YOUR_PASSWORD \\"
            echo "  --docker-email=YOUR_EMAIL \\"
            echo "  -n $NAMESPACE"
        fi
    fi
}

wait_for_pod() {
    local pod_name=$1
    local timeout=${2:-$TIMEOUT}
    
    print_info "Czekam na pod: $pod_name (timeout: ${timeout}s)..."
    
    if kubectl wait --for=condition=Ready pod/$pod_name -n $NAMESPACE --timeout=${timeout}s &> /dev/null; then
        print_success "Pod $pod_name jest gotowy"
        return 0
    else
        print_error "Pod $pod_name nie jest gotowy w czasie ${timeout}s"
        return 1
    fi
}

wait_for_statefulset() {
    local statefulset_name=$1
    local replicas=${2:-1}
    local timeout=${3:-$TIMEOUT}
    
    print_info "Czekam na StatefulSet: $statefulset_name (replicas: $replicas)..."
    
    local elapsed=0
    while [ $elapsed -lt $timeout ]; do
        local ready=$(kubectl get statefulset $statefulset_name -n $NAMESPACE -o jsonpath='{.status.readyReplicas}' 2>/dev/null || echo "0")
        if [ "$ready" = "$replicas" ]; then
            print_success "StatefulSet $statefulset_name jest gotowy ($ready/$replicas replik)"
            return 0
        fi
        sleep 5
        elapsed=$((elapsed + 5))
        echo -n "."
    done
    
    echo ""
    print_error "StatefulSet $statefulset_name nie jest gotowy w czasie ${timeout}s"
    return 1
}

# Funkcje główne
deploy_all() {
    print_info "Rozpoczynam wdrożenie PlusWorkflow + PostgreSQL..."
    
    # 1. Namespace
    print_info "1/8 Tworzenie namespace..."
    kubectl apply -f manifest-01-namespace.yaml
    print_success "Namespace utworzony"
    
    # 2. Sekrety
    print_info "2/8 Tworzenie secretów PostgreSQL..."
    kubectl apply -f manifest-02-postgres-secret.yaml
    
    # Jeśli używamy CloudNativePG, potrzebujemy dodatkowego secret
    if [ -f "manifest-10-postgres-cloudnativepg.yaml" ] && kubectl get crd clusters.postgresql.cnpg.io &> /dev/null 2>&1; then
        if [ -f "manifest-02-postgres-secret-cnpg.yaml" ]; then
            print_info "Tworzenie secret dla CloudNativePG..."
            kubectl apply -f manifest-02-postgres-secret-cnpg.yaml
        fi
    fi
    print_success "Sekrety utworzone"
    
    # 3. PostgreSQL Services
    print_info "3/8 Tworzenie serwisów PostgreSQL..."
    kubectl apply -f manifest-03-postgres-services.yaml
    print_success "Serwisy PostgreSQL utworzone"
    
    # 4. PostgreSQL - sprawdź czy używać CloudNativePG czy StatefulSet
    if [ -f "manifest-10-postgres-cloudnativepg.yaml" ] && kubectl get crd clusters.postgresql.cnpg.io &> /dev/null 2>&1; then
        print_info "4/8 Tworzenie CloudNativePG Cluster PostgreSQL..."
        
        # Sprawdź czy webhook jest gotowy
        if ! kubectl get svc cnpg-webhook-service -n cnpg-system &> /dev/null; then
            print_warning "Webhook CloudNativePG nie jest jeszcze gotowy, czekam..."
            WEBHOOK_READY=0
            for i in {1..30}; do
                if kubectl get svc cnpg-webhook-service -n cnpg-system &> /dev/null; then
                    print_success "Webhook jest gotowy"
                    WEBHOOK_READY=1
                    break
                fi
                echo -n "."
                sleep 2
            done
            echo ""
            if [ $WEBHOOK_READY -eq 0 ]; then
                print_warning "Webhook jeszcze nie jest gotowy, próbuję utworzyć Cluster..."
            fi
        fi
        
        # Próbuj utworzyć Cluster
        if kubectl apply -f manifest-10-postgres-cloudnativepg.yaml 2>&1 | grep -q "webhook.*not found"; then
            print_error "Webhook CloudNativePG nie jest jeszcze gotowy!"
            print_info "Poczekaj 1-2 minuty i uruchom ponownie:"
            echo "  kubectl apply -f manifest-10-postgres-cloudnativepg.yaml"
            print_info "Lub sprawdź status webhook:"
            echo "  kubectl get svc -n cnpg-system | grep webhook"
            echo "  kubectl get pods -n cnpg-system"
            return 1
        fi
        print_success "CloudNativePG Cluster utworzony"
        
        # 5. Czekaj na PostgreSQL (CloudNativePG)
        print_info "5/8 Czekam na gotowość PostgreSQL (CloudNativePG)..."
        print_info "Czekam na Cluster postgres-cluster..."
        kubectl wait --for=condition=Ready cluster/postgres-cluster -n $NAMESPACE --timeout=300s 2>/dev/null || {
            print_warning "Cluster może nie być jeszcze gotowy, sprawdzam pody..."
            sleep 10
        }
        # Sprawdź pierwszy pod
        PRIMARY_POD=$(kubectl get pod -n $NAMESPACE -l cnpg.io/cluster=postgres-cluster,role=primary -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
        if [ -n "$PRIMARY_POD" ]; then
            if wait_for_pod "$PRIMARY_POD" 180; then
                print_success "PostgreSQL (CloudNativePG) jest gotowy"
            else
                print_warning "PostgreSQL może nie być jeszcze gotowy, kontynuuję..."
            fi
        fi
    else
        print_info "4/8 Tworzenie StatefulSet PostgreSQL..."
        kubectl apply -f manifest-04-postgres-statefulset.yaml
        print_success "StatefulSet PostgreSQL utworzony"
        
        # 5. Czekaj na PostgreSQL
        print_info "5/8 Czekam na gotowość PostgreSQL..."
        if wait_for_pod "postgres-0" 180; then
            print_success "PostgreSQL jest gotowy"
        else
            print_warning "PostgreSQL może nie być jeszcze gotowy, kontynuuję..."
        fi
    fi
    
    # 6. PlusWorkflow ConfigMap
    print_info "6/8 Tworzenie ConfigMap Tomcat..."
    kubectl apply -f manifest-05-tomcat-configmap.yaml
    print_success "ConfigMap utworzony"
    
    # 7. PlusWorkflow Services
    print_info "7/8 Tworzenie serwisów PlusWorkflow..."
    kubectl apply -f manifest-06-plusworkflow-services.yaml
    print_success "Serwisy PlusWorkflow utworzone"
    
    # 8. PlusWorkflow StatefulSet
    print_info "8/8 Tworzenie StatefulSet PlusWorkflow..."
    
    # Sprawdź czy StatefulSet już istnieje
    if kubectl get statefulset plusworkflow -n $NAMESPACE &> /dev/null; then
        print_warning "StatefulSet 'plusworkflow' już istnieje!"
        print_info "Jeśli zmieniłeś volumeClaimTemplates (storageClassName/accessModes),"
        print_info "musisz najpierw usunąć StatefulSet (PVC zostaną zachowane):"
        echo ""
        print_warning "Czy chcesz usunąć istniejący StatefulSet i utworzyć go ponownie?"
        read -p "Wpisz 'TAK' aby kontynuować (PVC zostaną zachowane): " confirm
        
        if [ "$confirm" = "TAK" ]; then
            print_info "Usuwam StatefulSet (zachowuję PVC)..."
            kubectl delete statefulset plusworkflow -n $NAMESPACE --cascade=orphan
            print_success "StatefulSet usunięty, PVC zachowane"
            sleep 3
        else
            print_info "Pomijam aktualizację StatefulSet"
            print_info "Aby zaktualizować później, użyj: $0 migrate-statefulset"
            return 0
        fi
    fi
    
    # Zastosuj StatefulSet
    APPLY_OUTPUT=$(kubectl apply -f manifest-07-plusworkflow-statefulset.yaml 2>&1)
    APPLY_EXIT=$?
    
    if [ $APPLY_EXIT -ne 0 ]; then
        if echo "$APPLY_OUTPUT" | grep -q "Forbidden.*volumeClaimTemplates"; then
            print_error "Nie można zaktualizować volumeClaimTemplates w istniejącym StatefulSet!"
            print_info "Użyj komendy: $0 migrate-statefulset plusworkflow"
            return 1
        else
            print_error "Błąd podczas tworzenia StatefulSet:"
            echo "$APPLY_OUTPUT"
            return 1
        fi
    fi
    print_success "StatefulSet PlusWorkflow utworzony"
    
    print_success "Wdrożenie zakończone!"
    print_info "Sprawdzam status..."
    show_status
}

deploy_backups() {
    print_info "Wdrażam system backupów PostgreSQL..."
    
    if [ ! -f "manifest-09-postgres-backup-cronjob.yaml" ]; then
        print_error "Plik manifest-09-postgres-backup-cronjob.yaml nie istnieje!"
        return 1
    fi
    
    kubectl apply -f manifest-09-postgres-backup-cronjob.yaml
    print_success "System backupów wdrożony"
    
    print_info "Status CronJob:"
    kubectl get cronjob -n $NAMESPACE
}

undeploy_all() {
    print_warning "Czy na pewno chcesz usunąć całe wdrożenie? (zachowam PVC z danymi)"
    read -p "Wpisz 'TAK' aby kontynuować: " confirm
    
    if [ "$confirm" != "TAK" ]; then
        print_info "Anulowano"
        return
    fi
    
    print_info "Usuwam wdrożenie (zachowuję PVC)..."
    
    # Usuń w odwrotnej kolejności
    kubectl delete -f manifest-07-plusworkflow-statefulset.yaml --ignore-not-found=true
    kubectl delete -f manifest-06-plusworkflow-services.yaml --ignore-not-found=true
    kubectl delete -f manifest-05-tomcat-configmap.yaml --ignore-not-found=true
    kubectl delete -f manifest-04-postgres-statefulset.yaml --ignore-not-found=true
    kubectl delete -f manifest-03-postgres-services.yaml --ignore-not-found=true
    kubectl delete -f manifest-02-postgres-secret.yaml --ignore-not-found=true
    kubectl delete -f manifest-01-namespace.yaml --ignore-not-found=true
    
    print_success "Wdrożenie usunięte (PVC zachowane)"
    print_info "Aby usunąć również PVC i dane, użyj: $0 destroy"
}

destroy_all() {
    print_error "UWAGA: To usunie WSZYSTKO włącznie z danymi!"
    read -p "Wpisz 'USUŃ' aby potwierdzić: " confirm
    
    if [ "$confirm" != "USUŃ" ]; then
        print_info "Anulowano"
        return
    fi
    
    print_info "Usuwam namespace $NAMESPACE (wszystko włącznie z danymi)..."
    kubectl delete namespace $NAMESPACE --ignore-not-found=true
    
    print_success "Wszystko usunięte"
}

restart_all() {
    print_info "Restartuję wszystkie komponenty..."
    
    if kubectl get statefulset plusworkflow -n $NAMESPACE &> /dev/null; then
        print_info "Restartuję PlusWorkflow..."
        kubectl rollout restart statefulset plusworkflow -n $NAMESPACE
        print_success "PlusWorkflow restartowany"
    fi
    
    if kubectl get statefulset postgres -n $NAMESPACE &> /dev/null; then
        print_info "Restartuję PostgreSQL..."
        kubectl rollout restart statefulset postgres -n $NAMESPACE
        print_success "PostgreSQL restartowany"
    fi
    
    print_info "Czekam na gotowość..."
    sleep 10
    show_status
}

show_status() {
    echo ""
    print_info "=== STATUS WDROŻENIA ==="
    echo ""
    
    print_info "Pody:"
    kubectl get pods -n $NAMESPACE -o wide
    echo ""
    
    print_info "StatefulSets:"
    kubectl get statefulset -n $NAMESPACE
    echo ""
    
    print_info "Serwisy:"
    kubectl get svc -n $NAMESPACE
    echo ""
    
    print_info "PVC (volumes):"
    kubectl get pvc -n $NAMESPACE
    echo ""
    
    # Sprawdź LoadBalancer IP
    LB_IP=$(kubectl get svc plusworkflow-lb -n $NAMESPACE -o jsonpath='{.status.loadBalancer.ingress[0].ip}' 2>/dev/null || echo "")
    if [ -n "$LB_IP" ]; then
        print_success "LoadBalancer IP: http://$LB_IP"
    else
        print_warning "LoadBalancer IP jeszcze nie przypisane"
    fi
    echo ""
}

show_logs() {
    local component=$1
    local pod_name=""
    
    case $component in
        postgres|pg|db)
            pod_name="postgres-0"
            ;;
        plusworkflow|pwfl|app)
            pod_name="plusworkflow-0"
            ;;
        *)
            print_error "Nieznany komponent: $component"
            print_info "Użyj: postgres, plusworkflow"
            return 1
            ;;
    esac
    
    if ! kubectl get pod $pod_name -n $NAMESPACE &> /dev/null; then
        print_error "Pod $pod_name nie istnieje!"
        return 1
    fi
    
    print_info "Logi z $pod_name (Ctrl+C aby wyjść):"
    kubectl logs -f $pod_name -n $NAMESPACE
}

create_backup() {
    print_info "Tworzę ręczny backup PostgreSQL..."
    
    if ! kubectl get cronjob postgres-backup -n $NAMESPACE &> /dev/null; then
        print_error "CronJob backup nie istnieje! Najpierw uruchom: $0 backup-deploy"
        return 1
    fi
    
    JOB_NAME="postgres-backup-manual-$(date +%s)"
    kubectl create job --from=cronjob/postgres-backup $JOB_NAME -n $NAMESPACE
    
    print_success "Backup job utworzony: $JOB_NAME"
    print_info "Sprawdzam status..."
    
    sleep 5
    kubectl get job $JOB_NAME -n $NAMESPACE
    
    print_info "Aby zobaczyć logi:"
    echo "kubectl logs job/$JOB_NAME -n $NAMESPACE"
}

list_backups() {
    print_info "Lista backupów PostgreSQL..."
    
    # Znajdź pod z backupami
    BACKUP_POD=$(kubectl get pod -n $NAMESPACE -l job-name=postgres-backup-manual -o jsonpath='{.items[0].metadata.name}' 2>/dev/null || echo "")
    
    if [ -z "$BACKUP_POD" ]; then
        # Spróbuj znaleźć przez PVC
        BACKUP_PVC="postgres-backup-storage"
        if kubectl get pvc $BACKUP_PVC -n $NAMESPACE &> /dev/null; then
            print_info "PVC backup istnieje, ale nie ma aktywnego poda"
            print_info "Aby zobaczyć backupy, uruchom:"
            echo "kubectl run backup-list --image=postgres:15-alpine --rm -it --restart=Never -n $NAMESPACE -- sh -c 'ls -lh /backups'"
        else
            print_error "PVC backup nie istnieje! Najpierw uruchom: $0 backup-deploy"
        fi
    else
        kubectl exec $BACKUP_POD -n $NAMESPACE -- ls -lh /backups 2>/dev/null || print_warning "Nie można odczytać backupów"
    fi
}

migrate_statefulset() {
    local statefulset_name=${1:-plusworkflow}
    
    print_warning "Migracja StatefulSet '$statefulset_name' (zmiana volumeClaimTemplates)"
    print_info "To usunie StatefulSet, ale zachowa PVC z danymi"
    echo ""
    print_warning "UWAGA: Pody będą niedostępne podczas migracji!"
    read -p "Wpisz 'MIGRUJ' aby kontynuować: " confirm
    
    if [ "$confirm" != "MIGRUJ" ]; then
        print_info "Anulowano"
        return
    fi
    
    if ! kubectl get statefulset $statefulset_name -n $NAMESPACE &> /dev/null; then
        print_error "StatefulSet '$statefulset_name' nie istnieje!"
        return 1
    fi
    
    print_info "1. Usuwam StatefulSet (zachowuję PVC)..."
    kubectl delete statefulset $statefulset_name -n $NAMESPACE --cascade=orphan
    
    print_info "2. Czekam na usunięcie podów..."
    sleep 5
    
    print_info "3. Tworzę StatefulSet z nową konfiguracją..."
    if [ "$statefulset_name" = "plusworkflow" ]; then
        kubectl apply -f manifest-07-plusworkflow-statefulset.yaml
    elif [ "$statefulset_name" = "postgres" ]; then
        kubectl apply -f manifest-04-postgres-statefulset.yaml
    else
        print_error "Nieznany StatefulSet: $statefulset_name"
        return 1
    fi
    
    print_success "Migracja zakończona!"
    print_info "StatefulSet zostanie utworzony ponownie z nową konfiguracją volume"
    print_info "Sprawdzam status..."
    sleep 3
    show_status
}

# Menu główne
show_help() {
    echo "Skrypt zarządzający deploymentem PlusWorkflow + PostgreSQL"
    echo ""
    echo "Użycie: $0 [KOMENDA] [OPCJE]"
    echo ""
    echo "KOMENDY:"
    echo "  deploy          - Wdróż wszystko (namespace, PostgreSQL, PlusWorkflow)"
    echo "  undeploy        - Usuń wdrożenie (zachowaj PVC z danymi)"
    echo "  destroy         - Usuń wszystko włącznie z danymi (UWAGA!)"
    echo "  restart         - Restartuj wszystkie komponenty"
    echo "  status          - Pokaż status wdrożenia"
    echo "  logs [komponent] - Pokaż logi (postgres|plusworkflow)"
    echo ""
    echo "BACKUPY:"
    echo "  backup-deploy   - Wdróż system backupów"
    echo "  backup-create   - Utwórz ręczny backup"
    echo "  backup-list     - Pokaż listę backupów"
    echo ""
    echo "MIGRACJA:"
    echo "  migrate-statefulset [nazwa] - Migruj StatefulSet (zmiana volumeClaimTemplates)"
    echo "                              Użycie: $0 migrate-statefulset plusworkflow"
    echo ""
    echo "PRZYKŁADY:"
    echo "  $0 deploy                    # Wdróż wszystko"
    echo "  $0 status                    # Sprawdź status"
    echo "  $0 logs postgres             # Logi PostgreSQL"
    echo "  $0 logs plusworkflow         # Logi PlusWorkflow"
    echo "  $0 backup-deploy             # Wdróż backupy"
    echo "  $0 backup-create             # Ręczny backup"
    echo "  $0 migrate-statefulset plusworkflow  # Migruj StatefulSet (zmiana storage)"
    echo ""
}

# Główna logika
main() {
    check_kubectl
    
    case "${1:-help}" in
        deploy)
            check_requirements
            deploy_all
            ;;
        backup-deploy)
            deploy_backups
            ;;
        undeploy)
            undeploy_all
            ;;
        destroy)
            destroy_all
            ;;
        restart)
            restart_all
            ;;
        status)
            show_status
            ;;
        logs)
            if [ -z "$2" ]; then
                print_error "Podaj komponent (postgres|plusworkflow)"
                show_help
                exit 1
            fi
            show_logs "$2"
            ;;
        backup-create)
            create_backup
            ;;
        backup-list)
            list_backups
            ;;
        migrate-statefulset)
            migrate_statefulset "$2"
            ;;
        help|--help|-h)
            show_help
            ;;
        *)
            print_error "Nieznana komenda: $1"
            echo ""
            show_help
            exit 1
            ;;
    esac
}

# Uruchom
main "$@"

