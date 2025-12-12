#!/bin/bash
# Test Flux GitOps synchronization

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

test_flux_gitrepository() {
    print_info "Checking Flux GitRepository..."
    local gitrepo=$(kubectl get gitrepository -n "$FLUX_NAMESPACE" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null)
    
    if [ -z "$gitrepo" ]; then
        print_warning "No GitRepository found (Flux may be using different source)"
        return 0
    fi
    
    local status=$(kubectl get gitrepository "$gitrepo" -n "$FLUX_NAMESPACE" \
        -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
    
    if [ "$status" = "True" ]; then
        local url=$(kubectl get gitrepository "$gitrepo" -n "$FLUX_NAMESPACE" \
            -o jsonpath='{.spec.url}' 2>/dev/null)
        print_success "GitRepository '$gitrepo' is synced (URL: $url)"
        return 0
    else
        print_error "GitRepository '$gitrepo' is not synced"
        print_info "Check status with: kubectl describe gitrepository $gitrepo -n $FLUX_NAMESPACE"
        return 1
    fi
}

test_helm_release_sync() {
    print_info "Checking HelmRelease sync status..."
    local last_applied=$(kubectl get helmrelease redpanda -n "$NAMESPACE" \
        -o jsonpath='{.status.lastAppliedRevision}' 2>/dev/null)
    
    if [ -n "$last_applied" ]; then
        print_success "HelmRelease last applied revision: $last_applied"
        return 0
    else
        print_warning "HelmRelease has no last applied revision (may still be syncing)"
        return 0
    fi
}

test_helm_release_conditions() {
    print_info "Checking HelmRelease conditions..."
    local conditions=$(kubectl get helmrelease redpanda -n "$NAMESPACE" \
        -o jsonpath='{.status.conditions[*].type}' 2>/dev/null)
    
    if [ -z "$conditions" ]; then
        print_warning "No conditions found on HelmRelease"
        return 0
    fi
    
    local all_ready=true
    for condition in $conditions; do
        local status=$(kubectl get helmrelease redpanda -n "$NAMESPACE" \
            -o jsonpath="{.status.conditions[?(@.type==\"$condition\")].status}" 2>/dev/null)
        
        if [ "$status" = "True" ]; then
            print_success "Condition $condition is True"
        else
            local reason=$(kubectl get helmrelease redpanda -n "$NAMESPACE" \
                -o jsonpath="{.status.conditions[?(@.type==\"$condition\")].reason}" 2>/dev/null)
            print_warning "Condition $condition is $status (Reason: $reason)"
            if [ "$condition" = "Ready" ]; then
                all_ready=false
            fi
        fi
    done
    
    if [ "$all_ready" = true ]; then
        return 0
    else
        return 1
    fi
}

test_flux_kustomization() {
    print_info "Checking Flux Kustomization..."
    local kustomizations=$(kubectl get kustomization -n "$FLUX_NAMESPACE" \
        -o jsonpath='{.items[*].metadata.name}' 2>/dev/null)
    
    if [ -z "$kustomizations" ]; then
        print_warning "No Kustomization found (Flux may be using HelmRelease directly)"
        return 0
    fi
    
    local all_ready=true
    for kustomization in $kustomizations; do
        local status=$(kubectl get kustomization "$kustomization" -n "$FLUX_NAMESPACE" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        
        if [ "$status" = "True" ]; then
            print_success "Kustomization '$kustomization' is ready"
        else
            print_error "Kustomization '$kustomization' is not ready"
            all_ready=false
        fi
    done
    
    if [ "$all_ready" = true ]; then
        return 0
    else
        return 1
    fi
}

test_helm_release_reconciliation() {
    print_info "Checking HelmRelease reconciliation interval..."
    local interval=$(kubectl get helmrelease redpanda -n "$NAMESPACE" \
        -o jsonpath='{.spec.interval}' 2>/dev/null)
    
    if [ -n "$interval" ]; then
        print_success "HelmRelease reconciliation interval: $interval"
        return 0
    else
        print_warning "No reconciliation interval set"
        return 0
    fi
}

test_flux_source_status() {
    print_info "Checking Flux source status..."
    local sources=("helmrepository/redpanda" "helmrepository/jetstack")
    local all_ready=true
    
    for source in "${sources[@]}"; do
        local name=$(echo "$source" | cut -d'/' -f2)
        local namespace="$NAMESPACE"
        if [ "$name" = "jetstack" ]; then
            namespace="$FLUX_NAMESPACE"
        fi
        
        local status=$(kubectl get "$source" -n "$namespace" \
            -o jsonpath='{.status.conditions[?(@.type=="Ready")].status}' 2>/dev/null)
        
        if [ "$status" = "True" ]; then
            print_success "Source $source is ready"
        else
            print_error "Source $source is not ready"
            all_ready=false
        fi
    done
    
    if [ "$all_ready" = true ]; then
        return 0
    else
        return 1
    fi
}

main() {
    echo "=========================================="
    echo "GitOps Sync Tests"
    echo "=========================================="
    
    local failed=0
    
    run_test "Flux GitRepository sync" test_flux_gitrepository || failed=$((failed + 1))
    run_test "Flux source status" test_flux_source_status || failed=$((failed + 1))
    run_test "Flux Kustomization" test_flux_kustomization || failed=$((failed + 1))
    run_test "HelmRelease sync status" test_helm_release_sync || failed=$((failed + 1))
    run_test "HelmRelease conditions" test_helm_release_conditions || failed=$((failed + 1))
    run_test "HelmRelease reconciliation" test_helm_release_reconciliation || failed=$((failed + 1))
    
    if [ $failed -eq 0 ]; then
        print_success "All GitOps sync tests passed"
        return 0
    else
        print_error "Some GitOps sync tests failed"
        return 1
    fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    check_prerequisites || exit 1
    main "$@"
fi

