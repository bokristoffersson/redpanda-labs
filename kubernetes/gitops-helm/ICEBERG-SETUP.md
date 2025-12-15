# Iceberg Streaming with GitOps

This directory contains the Iceberg streaming example integrated into the GitOps-Helm setup. This setup pairs Redpanda with MinIO for Tiered Storage and enables writing data in the Iceberg format for seamless analytics workflows using Spark.

## Overview

This integration provides:
- **Redpanda with Iceberg support**: A separate Redpanda instance deployed via the Redpanda Operator with Iceberg and Tiered Storage enabled
- **MinIO**: S3-compatible object storage for Redpanda's Tiered Storage and Iceberg data
- **Iceberg REST Catalog**: Centralized metadata management for Iceberg tables
- **Spark with Jupyter**: Analytics environment for querying Iceberg tables

## Architecture

The setup deploys:
1. **MinIO Operator & Tenant** (via Flux HelmRelease)
2. **Redpanda Operator** (via Flux HelmRelease)
3. **Redpanda Cluster** with Iceberg configuration (via Redpanda CRD)
4. **Iceberg REST Catalog** (Deployment + Service)
5. **Spark Jupyter Notebook** (Deployment + Service)

All components are deployed in the `iceberg-lab` namespace, separate from the main `redpanda` namespace used by the gitops-helm example.

## Prerequisites

- **Flux** installed and configured (from the main gitops-helm setup)
- **k3d cluster** running
- **Docker** for building the Spark image
- **kubectl** for manual resource management

## Deployment Steps

### 1. Let Flux Deploy the GitOps Components

Since you're using Flux, most resources will be deployed automatically when you commit and push to your git repository. However, some resources need to be applied manually because:
- The Spark image needs to be built and loaded first
- Some resources depend on others being ready
- Jobs need to be triggered manually

The following resources will be deployed by Flux automatically:
- `iceberg-ns.yaml` - Namespace
- `minio-operator-ns.yaml` - MinIO operator namespace
- `minio-operator-repo.yaml` - MinIO Helm repository
- `minio-operator-release.yaml` - MinIO operator
- `minio-tenant-release.yaml` - MinIO tenant instance
- `redpanda-operator-release.yaml` - Redpanda Operator

### 2. Apply Configuration Resources

Apply the ConfigMap and Secret (Flux can manage these, but they need to exist before Redpanda starts):

```bash
kubectl apply -f iceberg-configmap.yaml
kubectl apply -f iceberg-secret.yaml
```

### 3. Wait for MinIO to be Ready

Before proceeding, ensure MinIO is fully deployed:

```bash
# Wait for MinIO operator
kubectl wait --for=condition=available deployment --all --namespace minio-operator --timeout=120s

# Wait for MinIO tenant
kubectl wait --for=condition=ready pod -l v1.min.io/tenant=iceberg-minio --namespace iceberg-lab --timeout=300s
```

If you see "error: no matching resources found", wait a few moments for Flux to create the resources.

### 4. Set Up MinIO Bucket

Run the MinIO setup job to create the bucket:

```bash
kubectl apply -f minio-setup-job.yaml
kubectl wait --for=condition=complete job/minio-setup --namespace iceberg-lab --timeout=60s
```

Check the job logs if needed:
```bash
kubectl logs job/minio-setup --namespace iceberg-lab
```

### 5. Deploy Iceberg REST Catalog

```bash
kubectl apply -f iceberg-rest.yaml
kubectl wait --for=condition=available deployment/iceberg-rest --namespace iceberg-lab --timeout=120s
```

### 6. Build and Load Spark Image

The Spark deployment requires a custom Docker image. Build it from the original iceberg example:

```bash
# Navigate to the iceberg directory
cd ../iceberg

# Build the Spark image (it auto-detects your architecture)
docker build -t spark-iceberg-jupyter:latest ./spark

# Load the image into your k3d cluster
# Replace 'k3d-mycluster' with your cluster name
k3d image import spark-iceberg-jupyter:latest -c <your-k3d-cluster-name>

# Return to gitops-helm directory
cd ../gitops-helm
```

To find your k3d cluster name:
```bash
k3d cluster list
```

### 7. Deploy Spark

```bash
kubectl apply -f spark-iceberg.yaml
kubectl wait --for=condition=available deployment/spark-iceberg --namespace iceberg-lab --timeout=120s
```

### 8. Deploy Redpanda with Iceberg Configuration

First, ensure the Redpanda Operator CRDs are installed:

```bash
kubectl kustomize "https://github.com/redpanda-data/redpanda-operator//operator/config/crd?ref=v2.4.4" \
    | kubectl apply --server-side -f -
```

Wait for the Redpanda Operator to be ready (deployed by Flux):

```bash
kubectl --namespace iceberg-lab rollout status --watch deployment/redpanda-controller-operator
```

Then deploy the Redpanda cluster:

```bash
kubectl apply -f iceberg-redpanda.yaml
kubectl get redpanda --namespace iceberg-lab --watch
```

Wait until you see:
```
NAME              READY   STATUS
redpanda-iceberg  True    Redpanda reconciliation succeeded
```

### 9. Expose Services

Apply the MinIO NodePort service:

```bash
kubectl apply -f minio-nodeport.yaml
```

Set up port forwarding for Spark and Redpanda Console:

```bash
# Spark Jupyter Notebook
kubectl port-forward deploy/spark-iceberg 8888:8888 --namespace iceberg-lab &

# Redpanda Console (if you want to access the iceberg Redpanda instance)
kubectl port-forward svc/redpanda-iceberg 8080:8080 --namespace iceberg-lab &
```

## Testing the Setup

### 1. Create an Iceberg Topic

```bash
# Create an alias for rpk in the iceberg Redpanda instance
alias iceberg-rpk="kubectl --namespace iceberg-lab exec -i -t redpanda-iceberg-0 -c redpanda -- rpk"

# Create an Iceberg-enabled topic
iceberg-rpk topic create key_value --topic-config=redpanda.iceberg.mode=key_value
```

### 2. Produce Data

```bash
echo "hello world" | iceberg-rpk topic produce key_value --format='%k %v\n'
```

### 3. Access Services

- **MinIO Console**: http://localhost:32090
  - Username: `minio`
  - Password: `minio123`

- **Spark Jupyter Notebook**: http://localhost:8888
  - No password required

- **Redpanda Console**: http://localhost:8080 (if port-forwarded)

### 4. Query Data with Spark

Open the Jupyter notebook at http://localhost:8888 and navigate to the notebook at:
`notebooks/Iceberg - Query Redpanda Table.ipynb`

Follow the notebook to query your Iceberg tables using Spark SQL.

## Differences from Original Setup

1. **Cluster Type**: This setup is adapted for **k3d** instead of **kind**
   - Node selectors have been removed/made optional
   - Image loading uses `k3d image import` instead of `kind load`

2. **GitOps Approach**:
   - MinIO and Redpanda Operator deployed via Flux HelmReleases
   - Automatic reconciliation and drift detection
   - Version controlled configuration

3. **Namespace Separation**:
   - Iceberg components in `iceberg-lab` namespace
   - Original gitops-helm Redpanda in `redpanda` namespace
   - Both instances can run concurrently

4. **Manual Steps**: Some resources still need manual application:
   - Spark deployment (requires image to be built first)
   - MinIO setup job (one-time initialization)
   - Redpanda CRD (needs operator ready first)

## Cleanup

To remove just the Iceberg setup:

```bash
# Delete the namespace (removes most resources)
kubectl delete namespace iceberg-lab

# Delete the MinIO operator namespace
kubectl delete namespace minio-operator

# Stop port forwarding
pkill -f "kubectl port-forward"
```

To remove everything including the cluster:

```bash
k3d cluster delete <your-cluster-name>
```

## Troubleshooting

### MinIO Console WebSocket Issues

If the MinIO console doesn't load properly, verify the NodePort service is running:

```bash
kubectl get svc minio-nodeport -n iceberg-lab
```

### Spark Image Not Found

If Spark pod shows `ImagePullBackOff`, verify the image was loaded:

```bash
# For k3d, check on the node
kubectl get pods -n iceberg-lab
kubectl describe pod <spark-pod-name> -n iceberg-lab
```

Rebuild and reload the image:

```bash
docker build -t spark-iceberg-jupyter:latest ../iceberg/spark
k3d image import spark-iceberg-jupyter:latest -c <cluster-name>
kubectl rollout restart deployment/spark-iceberg -n iceberg-lab
```

### Redpanda Bucket Access Errors

If Redpanda logs show "bucket not found":

```bash
# Verify bucket exists
kubectl exec -n iceberg-lab iceberg-minio-pool-0-0 -c minio -- mc ls local/

# Check Redpanda can reach MinIO
kubectl exec -n iceberg-lab redpanda-iceberg-0 -c redpanda -- curl -I http://iceberg-minio-hl.iceberg-lab.svc.cluster.local:9000/redpanda
```

## Additional Resources

- [Original Iceberg Example](../iceberg/README.adoc)
- [Redpanda Iceberg Documentation](https://docs.redpanda.com/current/manage/iceberg/)
- [Flux Documentation](https://fluxcd.io/flux/)
