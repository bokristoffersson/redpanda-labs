#!/bin/bash
# Test cluster health and Flux components

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

test_flux_namespace() {
    print_info "Checking Flux namespace..."
    if check_namespace "$FLUX_NAMESPACE"; then
        print_success "Flux namespace exists"
        return 0
    else
        print_error "Flux namespace not found"
        print_info "Flux may not be installed. Run: flux bootstrap github ..."
        return 1
    fi
}

test_flux_controllers() {
    print_info "Checking Flux controllers..."
    local controllers=("source-controller" "kustomize-controller" "helm-controller" "notification-controller")
    local all_ready=true
    
    for controller in "${controllers[@]}"; do
        local deployment_name="$controller"
        if check_deployment_ready "$deployment_name" "$FLUX_NAMESPACE"; then
            print_success "Flux $controller is ready"
        else
            print_error "Flux $controller is not ready"
            all_ready=false
        fi
    done
    
    if [ "$all_ready" = true ]; then
        return 0
    else
        print_info "Check controller status with: kubectl get pods -n $FLUX_NAMESPACE"
        return 1
    fi
}

test_redpanda_namespace() {
    print_info "Checking Redpanda namespace..."
    if check_namespace "$NAMESPACE"; then
        print_success "Redpanda namespace exists"
        return 0
    else
        print_error "Redpanda namespace not found"
        return 1
    fi
}

test_cert_manager_namespace() {
    print_info "Checking cert-manager namespace..."
    if check_namespace "$CERT_MANAGER_NAMESPACE"; then
        print_success "cert-manager namespace exists"
        return 0
    else
        print_error "cert-manager namespace not found"
        return 1
    fi
}

test_cert_manager_deployment() {
    print_info "Checking cert-manager deployment..."
    local deployments=("cert-manager" "cert-manager-webhook" "cert-manager-cainjector")
    local all_ready=true
    
    for deployment in "${deployments[@]}"; do
        if check_deployment_ready "$deployment" "$CERT_MANAGER_NAMESPACE"; then
            print_success "cert-manager $deployment is ready"
        else
            print_error "cert-manager $deployment is not ready"
            all_ready=false
        fi
    done
    
    if [ "$all_ready" = true ]; then
        return 0
    else
        print_info "Check cert-manager status with: kubectl get pods -n $CERT_MANAGER_NAMESPACE"
        return 1
    fi
}

test_helm_repositories() {
    print_info "Checking Helm repositories..."
    local repos=("redpanda" "jetstack")
    local all_synced=true
    
    for repo in "${repos[@]}"; do
        local namespace="$NAMESPACE"
        if [ "$repo" = "jetstack" ]; then
            namespace="$FLUX_NAMESPACE"
        fi
        
        local status=$(kubectl get helmrepository "$repo" -n "$namespace" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        
        if [ "$status" = "True" ]; then
            print_success "Helm repository $repo is synced"
        else
            print_error "Helm repository $repo is not synced"
            all_synced=false
        fi
    done
    
    if [ "$all_synced" = true ]; then
        return 0
    else
        print_info "Check repository status with: kubectl get helmrepository -n $NAMESPACE"
        return 1
    fi
}

main() {
    echo "=========================================="
    echo "Cluster Health Tests"
    echo "=========================================="
    
    local failed=0
    
    run_test "Flux namespace exists" test_flux_namespace || failed=$((failed + 1))
    run_test "Flux controllers are ready" test_flux_controllers || failed=$((failed + 1))
    run_test "Redpanda namespace exists" test_redpanda_namespace || failed=$((failed + 1))
    run_test "cert-manager namespace exists" test_cert_manager_namespace || failed=$((failed + 1))
    run_test "cert-manager deployments are ready" test_cert_manager_deployment || failed=$((failed + 1))
    run_test "Helm repositories are synced" test_helm_repositories || failed=$((failed + 1))
    
    if [ $failed -eq 0 ]; then
        print_success "All cluster health tests passed"
        return 0
    else
        print_error "Some cluster health tests failed"
        return 1
    fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    check_prerequisites || exit 1
    main "$@"
fi

