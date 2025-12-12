#!/bin/bash
# Test runner that executes all tests in sequence

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

# Test scripts to run
TESTS=(
    "test-cluster-health.sh"
    "test-gitops-sync.sh"
    "test-redpanda-deployment.sh"
    "test-redpanda-functionality.sh"
)

main() {
    echo "=========================================="
    echo "Redpanda GitOps Helm Test Suite"
    echo "=========================================="
    echo ""
    echo "Configuration:"
    echo "  Namespace: $NAMESPACE"
    echo "  Flux Namespace: $FLUX_NAMESPACE"
    echo "  cert-manager Namespace: $CERT_MANAGER_NAMESPACE"
    echo "  Timeout: ${TIMEOUT}s"
    echo ""
    
    # Check prerequisites
    if ! check_prerequisites; then
        print_error "Prerequisites check failed. Please install required tools."
        exit 1
    fi
    
    # Run all tests
    local overall_failed=0
    
    for test_script in "${TESTS[@]}"; do
        local test_path="$SCRIPT_DIR/$test_script"
        
        if [ ! -f "$test_path" ]; then
            print_error "Test script not found: $test_path"
            overall_failed=$((overall_failed + 1))
            continue
        fi
        
        if [ ! -x "$test_path" ]; then
            print_warning "Making $test_script executable..."
            chmod +x "$test_path"
        fi
        
        echo ""
        echo "=========================================="
        echo "Running: $test_script"
        echo "=========================================="
        
        if bash "$test_path"; then
            print_success "$test_script completed successfully"
        else
            print_error "$test_script failed"
            overall_failed=$((overall_failed + 1))
        fi
    done
    
    # Print final summary
    echo ""
    echo "=========================================="
    echo "Final Test Summary"
    echo "=========================================="
    print_summary
    
    if [ $overall_failed -eq 0 ]; then
        exit 0
    else
        exit 1
    fi
}

# Handle script arguments
case "${1:-}" in
    --help|-h)
        echo "Usage: $0 [options]"
        echo ""
        echo "Options:"
        echo "  --help, -h     Show this help message"
        echo "  --namespace    Set Redpanda namespace (default: redpanda)"
        echo "  --timeout      Set test timeout in seconds (default: 300)"
        echo ""
        echo "Environment variables:"
        echo "  REDPANDA_NAMESPACE       Redpanda namespace (default: redpanda)"
        echo "  CERT_MANAGER_NAMESPACE   cert-manager namespace (default: cert-manager)"
        echo "  FLUX_NAMESPACE           Flux namespace (default: flux-system)"
        echo "  TEST_TIMEOUT             Test timeout in seconds (default: 300)"
        exit 0
        ;;
    --namespace)
        export REDPANDA_NAMESPACE="${2:-redpanda}"
        shift 2
        ;;
    --timeout)
        export TEST_TIMEOUT="${2:-300}"
        shift 2
        ;;
esac

main "$@"

