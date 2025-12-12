#!/bin/bash
# Test Redpanda basic functionality (topics, produce, consume)

set -euo pipefail

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
source "$SCRIPT_DIR/common.sh"

TEST_TOPIC="test-topic-$(date +%s)"
TEST_MESSAGE="Hello from Kubernetes test"

get_redpanda_pod() {
    kubectl get pods -n "$NAMESPACE" \
        -l app.kubernetes.io/name=redpanda \
        -o jsonpath='{.items[0].metadata.name}' 2>/dev/null
}

check_rpk_available() {
    local pod_name=$1
    if kubectl exec "$pod_name" -n "$NAMESPACE" -c redpanda -- \
        which rpk &> /dev/null; then
        return 0
    else
        return 1
    fi
}

test_topic_creation() {
    print_info "Testing topic creation..."
    local pod_name=$(get_redpanda_pod)
    
    if [ -z "$pod_name" ]; then
        print_error "No Redpanda pod found"
        return 1
    fi
    
    if ! check_rpk_available "$pod_name"; then
        print_warning "rpk not available in pod, skipping topic tests"
        return 0
    fi
    
    # Create topic
    if kubectl exec "$pod_name" -n "$NAMESPACE" -c redpanda -- \
        rpk topic create "$TEST_TOPIC" &> /dev/null; then
        print_success "Topic '$TEST_TOPIC' created successfully"
        return 0
    else
        print_error "Failed to create topic '$TEST_TOPIC'"
        return 1
    fi
}

test_topic_list() {
    print_info "Testing topic listing..."
    local pod_name=$(get_redpanda_pod)
    
    if [ -z "$pod_name" ]; then
        print_error "No Redpanda pod found"
        return 1
    fi
    
    if ! check_rpk_available "$pod_name"; then
        return 0
    fi
    
    local topics=$(kubectl exec "$pod_name" -n "$NAMESPACE" -c redpanda -- \
        rpk topic list 2>/dev/null)
    
    if echo "$topics" | grep -q "$TEST_TOPIC"; then
        print_success "Topic '$TEST_TOPIC' found in topic list"
        return 0
    else
        print_error "Topic '$TEST_TOPIC' not found in topic list"
        print_info "Available topics: $topics"
        return 1
    fi
}

test_produce_message() {
    print_info "Testing message production..."
    local pod_name=$(get_redpanda_pod)
    
    if [ -z "$pod_name" ]; then
        print_error "No Redpanda pod found"
        return 1
    fi
    
    if ! check_rpk_available "$pod_name"; then
        return 0
    fi
    
    # Produce a message
    if echo "$TEST_MESSAGE" | kubectl exec -i "$pod_name" -n "$NAMESPACE" -c redpanda -- \
        rpk topic produce "$TEST_TOPIC" &> /dev/null; then
        print_success "Message produced to topic '$TEST_TOPIC'"
        return 0
    else
        print_error "Failed to produce message to topic '$TEST_TOPIC'"
        return 1
    fi
}

test_consume_message() {
    print_info "Testing message consumption..."
    local pod_name=$(get_redpanda_pod)
    
    if [ -z "$pod_name" ]; then
        print_error "No Redpanda pod found"
        return 1
    fi
    
    if ! check_rpk_available "$pod_name"; then
        return 0
    fi
    
    # Consume messages with timeout
    local consumed=$(timeout 10 kubectl exec "$pod_name" -n "$NAMESPACE" -c redpanda -- \
        rpk topic consume "$TEST_TOPIC" --num 1 --format '%v' 2>/dev/null || true)
    
    if echo "$consumed" | grep -q "$TEST_MESSAGE"; then
        print_success "Message consumed from topic '$TEST_TOPIC'"
        return 0
    else
        print_error "Failed to consume expected message from topic '$TEST_TOPIC'"
        print_info "Consumed: $consumed"
        print_info "Expected: $TEST_MESSAGE"
        return 1
    fi
}

test_topic_delete() {
    print_info "Cleaning up test topic..."
    local pod_name=$(get_redpanda_pod)
    
    if [ -z "$pod_name" ]; then
        return 0
    fi
    
    if ! check_rpk_available "$pod_name"; then
        return 0
    fi
    
    # Delete the test topic
    if kubectl exec "$pod_name" -n "$NAMESPACE" -c redpanda -- \
        rpk topic delete "$TEST_TOPIC" &> /dev/null; then
        print_success "Test topic '$TEST_TOPIC' deleted"
        return 0
    else
        print_warning "Failed to delete test topic (non-critical)"
        return 0
    fi
}

test_broker_info() {
    print_info "Testing broker information retrieval..."
    local pod_name=$(get_redpanda_pod)
    
    if [ -z "$pod_name" ]; then
        print_error "No Redpanda pod found"
        return 1
    fi
    
    if ! check_rpk_available "$pod_name"; then
        return 0
    fi
    
    # Get broker info
    local broker_info=$(kubectl exec "$pod_name" -n "$NAMESPACE" -c redpanda -- \
        rpk cluster info 2>/dev/null)
    
    if [ -n "$broker_info" ]; then
        print_success "Broker information retrieved successfully"
        print_info "Broker info: $(echo "$broker_info" | head -5)"
        return 0
    else
        print_error "Failed to retrieve broker information"
        return 1
    fi
}

main() {
    echo "=========================================="
    echo "Redpanda Functionality Tests"
    echo "=========================================="
    
    local failed=0
    
    run_test "Broker info retrieval" test_broker_info || failed=$((failed + 1))
    run_test "Topic creation" test_topic_creation || failed=$((failed + 1))
    run_test "Topic listing" test_topic_list || failed=$((failed + 1))
    run_test "Message production" test_produce_message || failed=$((failed + 1))
    run_test "Message consumption" test_consume_message || failed=$((failed + 1))
    run_test "Topic cleanup" test_topic_delete || failed=$((failed + 1))
    
    if [ $failed -eq 0 ]; then
        print_success "All Redpanda functionality tests passed"
        return 0
    else
        print_error "Some Redpanda functionality tests failed"
        return 1
    fi
}

if [ "${BASH_SOURCE[0]}" = "${0}" ]; then
    check_prerequisites || exit 1
    main "$@"
fi

