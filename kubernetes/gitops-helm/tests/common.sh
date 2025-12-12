#!/bin/bash
# Common utilities for Kubernetes GitOps Helm tests

# Color codes for output
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Default configuration
NAMESPACE="${REDPANDA_NAMESPACE:-redpanda}"
CERT_MANAGER_NAMESPACE="${CERT_MANAGER_NAMESPACE:-cert-manager}"
FLUX_NAMESPACE="${FLUX_NAMESPACE:-flux-system}"
TIMEOUT="${TEST_TIMEOUT:-300}" # 5 minutes default

# Test counters
TESTS_PASSED=0
TESTS_FAILED=0
TESTS_TOTAL=0

# Print colored output
print_success() {
    echo -e "${GREEN}✓${NC} $1"
}

print_error() {
    echo -e "${RED}✗${NC} $1"
}

print_warning() {
    echo -e "${YELLOW}⚠${NC} $1"
}

print_info() {
    echo -e "  ${NC}→ $1"
}

# Check if a command exists
check_command() {
    if ! command -v "$1" &> /dev/null; then
        print_error "$1 is not installed or not in PATH"
        return 1
    fi
    return 0
}

# Check if kubectl can connect to cluster
check_kubectl() {
    if ! kubectl cluster-info &> /dev/null; then
        print_error "Cannot connect to Kubernetes cluster"
        print_info "Make sure kubectl is configured correctly"
        return 1
    fi
    return 0
}

# Wait for a resource to be ready
wait_for_resource() {
    local resource_type=$1
    local resource_name=$2
    local namespace=$3
    local timeout=${4:-$TIMEOUT}
    local condition=${5:-condition=ready}
    
    print_info "Waiting for $resource_type/$resource_name in namespace $namespace..."
    
    if kubectl wait --for="$condition" "$resource_type/$resource_name" \
        -n "$namespace" --timeout="${timeout}s" &> /dev/null; then
        print_success "$resource_type/$resource_name is ready"
        return 0
    else
        print_error "$resource_type/$resource_name failed to become ready within ${timeout}s"
        return 1
    fi
}

# Check if a pod is running
check_pod_running() {
    local pod_name=$1
    local namespace=$2
    
    local phase=$(kubectl get pod "$pod_name" -n "$namespace" \
        -o jsonpath='{.status.phase}' 2>/dev/null)
    
    if [ "$phase" = "Running" ]; then
        return 0
    else
        return 1
    fi
}

# Check if all pods in a deployment are ready
check_deployment_ready() {
    local deployment_name=$1
    local namespace=$2
    
    local ready=$(kubectl get deployment "$deployment_name" -n "$namespace" \
        -o jsonpath='{.status.readyReplicas}' 2>/dev/null)
    local desired=$(kubectl get deployment "$deployment_name" -n "$namespace" \
        -o jsonpath='{.spec.replicas}' 2>/dev/null)
    
    if [ "$ready" = "$desired" ] && [ -n "$ready" ] && [ "$ready" != "0" ]; then
        return 0
    else
        return 1
    fi
}

# Check if a namespace exists
check_namespace() {
    local namespace=$1
    
    if kubectl get namespace "$namespace" &> /dev/null; then
        return 0
    else
        return 1
    fi
}

# Get pod name by label selector
get_pod_name() {
    local namespace=$1
    local selector=$2
    
    kubectl get pods -n "$namespace" -l "$selector" \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

# Run a test and track results
run_test() {
    local test_name=$1
    shift
    
    TESTS_TOTAL=$((TESTS_TOTAL + 1))
    echo ""
    echo "Running: $test_name"
    
    if "$@"; then
        TESTS_PASSED=$((TESTS_PASSED + 1))
        print_success "$test_name passed"
        return 0
    else
        TESTS_FAILED=$((TESTS_FAILED + 1))
        print_error "$test_name failed"
        return 1
    fi
}

# Print test summary
print_summary() {
    echo ""
    echo "=========================================="
    echo "Test Summary"
    echo "=========================================="
    echo "Total tests: $TESTS_TOTAL"
    echo -e "${GREEN}Passed: $TESTS_PASSED${NC}"
    echo -e "${RED}Failed: $TESTS_FAILED${NC}"
    echo "=========================================="
    
    if [ $TESTS_FAILED -eq 0 ]; then
        echo -e "${GREEN}All tests passed!${NC}"
        return 0
    else
        echo -e "${RED}Some tests failed${NC}"
        return 1
    fi
}

# Check prerequisites
check_prerequisites() {
    local missing=0
    
    echo "Checking prerequisites..."
    
    if ! check_command kubectl; then
        missing=$((missing + 1))
    fi
    
    if ! check_command helm; then
        missing=$((missing + 1))
    fi
    
    if ! check_kubectl; then
        missing=$((missing + 1))
    fi
    
    if [ $missing -gt 0 ]; then
        print_error "Prerequisites check failed"
        return 1
    fi
    
    print_success "All prerequisites met"
    return 0
}

