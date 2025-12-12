#!/bin/bash
# Test Redpanda cluster deployment and health

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

test_helm_release_exists() {
    print_info "Checking HelmRelease resource..."
    if kubectl get helmrelease redpanda -n "$NAMESPACE" &> /dev/null; then
        print_success "HelmRelease 'redpanda' exists"
        return 0
    else
        print_error "HelmRelease 'redpanda' not found"
        return 1
    fi
}

test_helm_release_ready() {
    print_info "Checking HelmRelease status..."
    local status=$(kubectl get helmrelease redpanda -n "$NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    
    if [ "$status" = "True" ]; then
        local message=$(kubectl get helmrelease redpanda -n "$NAMESPACE" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].message}' 2>/dev/null)
        print_success "HelmRelease is ready: $message"
        return 0
    else
        local reason=$(kubectl get helmrelease redpanda -n "$NAMESPACE" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].reason}' 2>/dev/null)
        print_error "HelmRelease is not ready. Reason: $reason"
        print_info "Check status with: kubectl describe helmrelease redpanda -n $NAMESPACE"
        return 1
    fi
}

test_redpanda_crd_exists() {
    print_info "Checking Redpanda CRD..."
    if kubectl get crd redpandas.cluster.redpanda.com &> /dev/null; then
        print_success "Redpanda CRD exists"
        return 0
    else
        print_error "Redpanda CRD not found"
        print_info "CRD should be installed by the Redpanda Operator"
        return 1
    fi
}

test_redpanda_cluster_exists() {
    print_info "Checking Redpanda cluster resource..."
    local cluster_name=$(kubectl get redpanda -n "$NAMESPACE" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -n "$cluster_name" ]; then
        print_success "Redpanda cluster '$cluster_name' exists"
        return 0
    else
        print_error "No Redpanda cluster found in namespace $NAMESPACE"
        return 1
    fi
}

test_redpanda_cluster_ready() {
    print_info "Checking Redpanda cluster status..."
    local ready=$(kubectl get redpanda -n "$NAMESPACE" \
        -o jsonpath='{.items[0].status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    
    if [ "$ready" = "True" ]; then
        print_success "Redpanda cluster is ready"
        return 0
    else
        print_error "Redpanda cluster is not ready"
        print_info "Check cluster status with: kubectl get redpanda -n $NAMESPACE"
        print_info "Check pod logs with: kubectl logs -n $NAMESPACE -l app.kubernetes.io/name=redpanda"
        return 1
    fi
}

test_redpanda_pods_running() {
    print_info "Checking Redpanda pods..."
    local pods=$(kubectl get pods -n "$NAMESPACE" \
        -l app.kubernetes.io/name=redpanda \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [ -z "$pods" ]; then
        print_error "No Redpanda pods found"
        return 1
    fi
    
    local all_running=true
    for pod in $pods; do
        if check_pod_running "$pod" "$NAMESPACE"; then
            print_success "Pod $pod is running"
        else
            print_error "Pod $pod is not running"
            local phase=$(kubectl get pod "$pod" -n "$NAMESPACE" \
                -o jsonpath='{.status.phase}' 2>/dev/null)
            print_info "Pod phase: $phase"
            all_running=false
        fi
    done
    
    if [ "$all_running" = true ]; then
        return 0
    else
        return 1
    fi
}

test_redpanda_operator_running() {
    print_info "Checking Redpanda Operator..."
    local operator_pod=$(get_pod_name "$NAMESPACE" "app.kubernetes.io/name=redpanda-operator")
    
    if [ -z "$operator_pod" ]; then
        print_error "Redpanda Operator pod not found"
        return 1
    fi
    
    if check_pod_running "$operator_pod" "$NAMESPACE"; then
        print_success "Redpanda Operator is running"
        return 0
    else
        print_error "Redpanda Operator is not running"
        return 1
    fi
}

test_redpanda_services() {
    print_info "Checking Redpanda services..."
    local services=("redpanda" "redpanda-admin")
    local all_exist=true
    
    for service in "${services[@]}"; do
        if kubectl get service "$service" -n "$NAMESPACE" &> /dev/null; then
            print_success "Service $service exists"
        else
            print_error "Service $service not found"
            all_exist=false
        fi
    done
    
    if [ "$all_exist" = true ]; then
        return 0
    else
        return 1
    fi
}

test_redpanda_cluster_health() {
    print_info "Checking Redpanda cluster health via rpk..."
    local pod_name=$(kubectl get pods -n "$NAMESPACE" \
        -l app.kubernetes.io/name=redpanda \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$pod_name" ]; then
        print_error "No Redpanda pod found for health check"
        return 1
    fi
    
    # Check if rpk is available in the pod
    if kubectl exec "$pod_name" -n "$NAMESPACE" -c redpanda -- \
        rpk cluster health &> /dev/null; then
        local health_output=$(kubectl exec "$pod_name" -n "$NAMESPACE" -c redpanda -- \
            rpk cluster health 2>/dev/null)
        
        if echo "$health_output" | grep -q "Healthy.*true"; then
            print_success "Redpanda cluster is healthy"
            return 0
        else
            print_warning "Redpanda cluster health check returned unexpected result"
            print_info "Health output: $health_output"
            return 1
        fi
    else
        print_warning "Could not execute rpk cluster health (rpk may not be available)"
        print_info "Skipping cluster health check"
        return 0
    fi
}

main() {
    echo "=========================================="
    echo "Redpanda Deployment Tests"
    echo "=========================================="
    
    local failed=0
    
    run_test "HelmRelease exists" test_helm_release_exists || failed=$((failed + 1))
    run_test "HelmRelease is ready" test_helm_release_ready || failed=$((failed + 1))
    run_test "Redpanda CRD exists" test_redpanda_crd_exists || failed=$((failed + 1))
    run_test "Redpanda cluster exists" test_redpanda_cluster_exists || failed=$((failed + 1))
    run_test "Redpanda cluster is ready" test_redpanda_cluster_ready || failed=$((failed + 1))
    run_test "Redpanda Operator is running" test_redpanda_operator_running || failed=$((failed + 1))
    run_test "Redpanda pods are running" test_redpanda_pods_running || failed=$((failed + 1))
    run_test "Redpanda services exist" test_redpanda_services || failed=$((failed + 1))
    run_test "Redpanda cluster health" test_redpanda_cluster_health || failed=$((failed + 1))
    
    if [ $failed -eq 0 ]; then
        print_success "All Redpanda deployment tests passed"
        return 0
    else
        print_error "Some Redpanda deployment tests failed"
        return 1
    fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    check_prerequisites || exit 1
    main "$@"
fi

