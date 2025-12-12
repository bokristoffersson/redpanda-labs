# Kubernetes GitOps Helm Test Suite

This directory contains automated tests for validating the Redpanda GitOps Helm deployment.

## Overview

The test suite validates:

- **Cluster Health**: Flux components, namespaces, and cert-manager
- **GitOps Sync**: Flux synchronization and HelmRelease status
- **Redpanda Deployment**: Cluster creation, pod health, and services
- **Redpanda Functionality**: Topic operations, produce/consume, and broker info

## Prerequisites

- `kubectl` configured to access your Kubernetes cluster
- `helm` installed (for some checks)
- Access to the `redpanda` namespace
- Redpanda cluster deployed via GitOps Helm

## Quick Start

Run all tests:

```bash
./run-all-tests.sh
```

Run individual test suites:

```bash
./test-cluster-health.sh
./test-gitops-sync.sh
./test-redpanda-deployment.sh
./test-redpanda-functionality.sh
```

## Configuration

Tests can be configured via environment variables:

```bash
# Set custom namespace
export REDPANDA_NAMESPACE=redpanda
export CERT_MANAGER_NAMESPACE=cert-manager
export FLUX_NAMESPACE=flux-system

# Set test timeout (seconds)
export TEST_TIMEOUT=300

# Run tests
./run-all-tests.sh
```

Or use command-line options:

```bash
./run-all-tests.sh --namespace my-namespace --timeout 600
```

## Test Scripts

### `test-cluster-health.sh`

Validates cluster infrastructure:
- Flux namespace and controllers
- Redpanda and cert-manager namespaces
- cert-manager deployments
- Helm repository synchronization

### `test-gitops-sync.sh`

Validates GitOps synchronization:
- Flux GitRepository status
- HelmRelease sync status
- Flux Kustomization (if used)
- Source repository status

### `test-redpanda-deployment.sh`

Validates Redpanda deployment:
- HelmRelease resource and status
- Redpanda CRD existence
- Redpanda cluster resource and readiness
- Pod status and health
- Service creation
- Cluster health via rpk

### `test-redpanda-functionality.sh`

Tests Redpanda operations:
- Broker information retrieval
- Topic creation and listing
- Message production and consumption
- Topic cleanup

### `run-all-tests.sh`

Test runner that executes all test suites in sequence and provides a summary.

## Output

Tests provide color-coded output:
- ✓ Green: Test passed
- ✗ Red: Test failed
- ⚠ Yellow: Warning (non-critical)

Each test provides detailed information about what it's checking and troubleshooting hints if tests fail.

## Exit Codes

- `0`: All tests passed
- `1`: One or more tests failed

This makes the test suite suitable for CI/CD integration.

## Troubleshooting

### Tests Fail with "Cannot connect to cluster"

Ensure `kubectl` is configured correctly:

```bash
kubectl cluster-info
kubectl get nodes
```

### Tests Fail with "Namespace not found"

Verify the namespaces exist:

```bash
kubectl get namespace redpanda
kubectl get namespace cert-manager
kubectl get namespace flux-system
```

### Redpanda Functionality Tests Fail

Check if Redpanda pods are running:

```bash
kubectl get pods -n redpanda
kubectl logs -n redpanda <pod-name> -c redpanda
```

### HelmRelease Not Ready

Check HelmRelease status:

```bash
kubectl get helmrelease -n redpanda
kubectl describe helmrelease redpanda -n redpanda
```

Check Flux logs:

```bash
kubectl logs -n flux-system -l app=helm-controller
```

## Integration with CI/CD

Example GitHub Actions workflow:

```yaml
name: Test Redpanda Deployment

on: [push, pull_request]

jobs:
  test:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v3
      - uses: actions/setup-node@v3
      - name: Install kubectl
        run: |
          curl -LO "https://dl.k8s.io/release/$(curl -L -s https://dl.k8s.io/release/stable.txt)/bin/linux/amd64/kubectl"
          chmod +x kubectl
          sudo mv kubectl /usr/local/bin/
      - name: Configure kubectl
        run: |
          # Configure kubectl for your cluster
      - name: Run tests
        run: |
          cd kubernetes/gitops-helm/tests
          chmod +x *.sh
          ./run-all-tests.sh
```

## Contributing

When adding new tests:

1. Follow the existing test structure
2. Use functions from `common.sh` for shared functionality
3. Provide clear error messages with troubleshooting hints
4. Update this README if adding new test categories

## See Also

- [Console Monitoring Guide](../CONSOLE-MONITORING.md) - How to use Redpanda Console
- [GitOps Helm README](../README.adoc) - Deployment instructions

