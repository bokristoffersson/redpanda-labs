# Redpanda Console Monitoring Guide

This guide explains how to set up and use Redpanda Console for monitoring your Redpanda cluster deployed via GitOps Helm.

## Table of Contents

- [Overview](#overview)
- [Deploying Redpanda Console](#deploying-redpanda-console)
- [Accessing the Console](#accessing-the-console)
- [Key Monitoring Features](#key-monitoring-features)
- [Common Monitoring Tasks](#common-monitoring-tasks)
- [Troubleshooting](#troubleshooting)

## Overview

Redpanda Console is a web-based UI for managing and monitoring Redpanda clusters. It provides:

- **Topic Management**: Create, view, and manage topics
- **Message Inspection**: Browse and search messages in topics
- **Broker Health**: Monitor cluster health and broker status
- **Consumer Groups**: Track consumer group lag and offsets
- **Schema Registry**: View and manage schemas
- **Performance Metrics**: Monitor throughput, latency, and resource usage

## Deploying Redpanda Console

### Option 1: Add Console to HelmRelease (Recommended)

Edit your `redpanda-helm-release.yaml` file to include Console in the Helm values:

```yaml
apiVersion: helm.toolkit.fluxcd.io/v2beta1
kind: HelmRelease
metadata:
  name: redpanda
  namespace: redpanda
spec:
  dependsOn:
    - name: cert-manager
      namespace: cert-manager
  interval: 5m
  chart:
    spec:
      chart: redpanda
      version: "5.7.*"
      sourceRef:
        kind: HelmRepository
        name: redpanda
        namespace: redpanda
      interval: 1m
  values:
    statefulset:
      initContainers:
        setDataDirOwnership:
          enabled: true
    console:
      enabled: true
      config:
        kafka:
          brokers:
            - redpanda.redpanda.svc.cluster.local:9092
        redpanda:
          adminApi:
            enabled: true
            urls:
              - http://redpanda.redpanda.svc.cluster.local:9644
      service:
        type: ClusterIP
        port: 8080
```

After updating the file, commit and push to your Git repository. Flux will automatically sync and deploy Console.

### Option 2: Deploy Console Separately

If you prefer to deploy Console separately, you can create a standalone deployment:

```yaml
apiVersion: apps/v1
kind: Deployment
metadata:
  name: redpanda-console
  namespace: redpanda
spec:
  replicas: 1
  selector:
    matchLabels:
      app: redpanda-console
  template:
    metadata:
      labels:
        app: redpanda-console
    spec:
      containers:
      - name: console
        image: docker.redpanda.com/redpandadata/console:latest
        ports:
        - containerPort: 8080
        env:
        - name: CONFIG_FILEPATH
          value: /tmp/config.yml
        volumeMounts:
        - name: config
          mountPath: /tmp/config.yml
          subPath: config.yml
      volumes:
      - name: config
        configMap:
          name: redpanda-console-config
---
apiVersion: v1
kind: ConfigMap
metadata:
  name: redpanda-console-config
  namespace: redpanda
data:
  config.yml: |
    kafka:
      brokers:
        - redpanda.redpanda.svc.cluster.local:9092
    redpanda:
      adminApi:
        enabled: true
        urls:
          - http://redpanda.redpanda.svc.cluster.local:9644
---
apiVersion: v1
kind: Service
metadata:
  name: redpanda-console
  namespace: redpanda
spec:
  selector:
    app: redpanda-console
  ports:
  - port: 8080
    targetPort: 8080
  type: ClusterIP
```

## Accessing the Console

### Method 1: Port Forwarding (Recommended for Local Development)

Port forwarding is the simplest way to access Console in a local Kubernetes cluster:

```bash
# Forward Console service to localhost
kubectl port-forward svc/redpanda-console 8080:8080 -n redpanda
```

Then open your browser and navigate to: `http://localhost:8080`

**Note**: Keep the terminal session running while using Console. Press `Ctrl+C` to stop port forwarding.

### Method 2: NodePort Service

For easier access without keeping a terminal session open, you can expose Console via NodePort:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: redpanda-console-nodeport
  namespace: redpanda
spec:
  type: NodePort
  selector:
    app.kubernetes.io/name: redpanda-console
  ports:
  - port: 8080
    targetPort: 8080
    nodePort: 30080
```

Access Console at: `http://localhost:30080` (or `http://<node-ip>:30080`)

### Method 3: LoadBalancer (Cloud Environments)

In cloud environments (AWS, GCP, Azure), you can use a LoadBalancer service:

```yaml
apiVersion: v1
kind: Service
metadata:
  name: redpanda-console-lb
  namespace: redpanda
spec:
  type: LoadBalancer
  selector:
    app.kubernetes.io/name: redpanda-console
  ports:
  - port: 8080
    targetPort: 8080
```

The cloud provider will assign an external IP address that you can use to access Console.

## Key Monitoring Features

### 1. Topics Overview

**Location**: Main dashboard → Topics

**What to Monitor**:
- **Topic Count**: Total number of topics in your cluster
- **Partition Count**: Total partitions across all topics
- **Message Rate**: Messages per second being produced/consumed
- **Storage Usage**: Total disk space used by topics

**Key Metrics**:
- Messages per second (in/out)
- Bytes per second (in/out)
- Partition count per topic
- Replication factor

### 2. Individual Topic Details

**Location**: Topics → Select a topic

**What to Monitor**:
- **Partitions**: Number of partitions and their leaders
- **Messages**: Total message count and size
- **Consumer Groups**: Groups consuming from this topic
- **Configuration**: Topic-level settings (retention, compression, etc.)

**Actions Available**:
- View messages (with filtering and search)
- Produce test messages
- Edit topic configuration
- Delete topic (with confirmation)

### 3. Broker Health

**Location**: Brokers section

**What to Monitor**:
- **Cluster Status**: Overall cluster health
- **Broker Status**: Individual broker health and uptime
- **Resource Usage**: CPU, memory, and disk usage per broker
- **Network**: Network I/O and latency

**Key Metrics**:
- Broker count and status
- CPU utilization
- Memory usage
- Disk usage and available space
- Network throughput

### 4. Consumer Groups

**Location**: Consumer Groups section

**What to Monitor**:
- **Group Status**: Active, empty, or dead groups
- **Lag**: Messages behind the latest offset
- **Members**: Number of consumers in each group
- **Partition Assignment**: Which partitions are assigned to which consumers

**Key Metrics**:
- Consumer lag (messages behind)
- Messages per second consumed
- Number of active members
- Partition assignment distribution

### 5. Message Inspection

**Location**: Topics → Select topic → Messages tab

**Features**:
- **Browse Messages**: Scroll through messages in a topic
- **Search**: Filter messages by key, value, headers, or timestamp
- **Format Detection**: Automatic detection of JSON, Avro, Protobuf, etc.
- **Export**: Download messages for analysis

**Use Cases**:
- Debugging message format issues
- Verifying data correctness
- Inspecting message headers
- Understanding message flow

### 6. Schema Registry Integration

**Location**: Schema Registry section (if enabled)

**What to Monitor**:
- **Schemas**: Registered schemas and their versions
- **Compatibility**: Schema compatibility settings
- **Subjects**: Topics with associated schemas

**Actions Available**:
- View schema definitions
- Check schema versions
- Validate schema compatibility
- Register new schemas

### 7. Performance Metrics

**Location**: Metrics/Dashboard section

**Key Metrics**:
- **Throughput**: Messages/bytes per second
- **Latency**: P50, P95, P99 latencies
- **Error Rates**: Failed requests per second
- **Resource Metrics**: CPU, memory, disk I/O

**Time Ranges**:
- Real-time (last few minutes)
- Last hour
- Last 24 hours
- Custom time range

## Common Monitoring Tasks

### Task 1: Check Cluster Health

1. Open Redpanda Console
2. Navigate to **Brokers** section
3. Check the **Cluster Status** indicator:
   - Green: All brokers healthy
   - Yellow: Some brokers have warnings
   - Red: Critical issues detected
4. Review individual broker status and resource usage

**What to Look For**:
- All brokers showing "Healthy" status
- CPU usage below 80%
- Memory usage within limits
- Disk space available (>20% free)

### Task 2: Monitor Topic Throughput

1. Navigate to **Topics** section
2. View the main dashboard for overall metrics
3. Click on a specific topic to see detailed metrics
4. Check the **Messages** tab for:
   - Messages per second (in/out)
   - Bytes per second
   - Partition distribution

**What to Look For**:
- Consistent message rates (no sudden drops)
- Balanced partition distribution
- No error messages in the logs

### Task 3: Check Consumer Lag

1. Navigate to **Consumer Groups** section
2. Review the list of consumer groups
3. Check the **Lag** column for each group
4. Click on a group to see detailed partition-level lag

**What to Look For**:
- Lag should be low or zero for real-time consumers
- Sudden increases in lag may indicate consumer issues
- Check partition-level lag distribution (should be balanced)

### Task 4: Inspect Messages

1. Navigate to **Topics** → Select your topic
2. Click on the **Messages** tab
3. Use filters to find specific messages:
   - **Key Filter**: Search by message key
   - **Value Filter**: Search by message content
   - **Time Range**: Filter by timestamp
4. Click on a message to view full details

**Use Cases**:
- Verify message format and content
- Debug data quality issues
- Understand message flow patterns

### Task 5: Monitor Resource Usage

1. Navigate to **Brokers** section
2. Review resource metrics for each broker:
   - **CPU**: Should be below 80% under normal load
   - **Memory**: Monitor for memory leaks or high usage
   - **Disk**: Check available space and I/O rates
3. Use the metrics dashboard for historical trends

**What to Look For**:
- Consistent resource usage patterns
- No sudden spikes or drops
- Disk space trending downward (normal with data retention)
- Network I/O matching expected throughput

### Task 6: Create and Test Topics

1. Navigate to **Topics** section
2. Click **Create Topic** button
3. Fill in topic details:
   - **Topic Name**: Choose a descriptive name
   - **Partitions**: Number of partitions (consider throughput needs)
   - **Replication Factor**: Usually 3 for production
   - **Configuration**: Set retention, compression, etc.
4. Click **Create**
5. Use the **Produce** tab to send test messages
6. Use the **Messages** tab to verify messages were written

### Task 7: Monitor Schema Registry

1. Navigate to **Schema Registry** section (if enabled)
2. Review registered schemas
3. Check schema versions and compatibility
4. View schema definitions

**What to Look For**:
- Schemas are properly versioned
- Compatibility settings are appropriate
- No schema evolution conflicts

## Troubleshooting

### Console Not Accessible

**Problem**: Cannot access Console via port-forward or service

**Solutions**:
1. Check if Console pod is running:
   ```bash
   kubectl get pods -n redpanda -l app.kubernetes.io/name=redpanda-console
   ```

2. Check Console logs:
   ```bash
   kubectl logs -n redpanda -l app.kubernetes.io/name=redpanda-console
   ```

3. Verify service exists:
   ```bash
   kubectl get svc -n redpanda redpanda-console
   ```

4. Test connectivity from within cluster:
   ```bash
   kubectl run -it --rm debug --image=curlimages/curl --restart=Never -- \
     curl http://redpanda-console.redpanda.svc.cluster.local:8080
   ```

### Console Shows "Cannot Connect to Broker"

**Problem**: Console cannot connect to Redpanda brokers

**Solutions**:
1. Verify broker service name in Console config matches actual service:
   ```bash
   kubectl get svc -n redpanda
   ```

2. Check if brokers are accessible:
   ```bash
   kubectl exec -n redpanda <console-pod> -- \
     nc -zv redpanda.redpanda.svc.cluster.local 9092
   ```

3. Verify Admin API is enabled and accessible:
   ```bash
   kubectl exec -n redpanda <console-pod> -- \
     curl http://redpanda.redpanda.svc.cluster.local:9644/v1/status
   ```

### Topics Not Appearing

**Problem**: Topics created via CLI don't appear in Console

**Solutions**:
1. Refresh the browser page
2. Check if topics exist via CLI:
   ```bash
   kubectl exec -n redpanda <redpanda-pod> -c redpanda -- \
     rpk topic list
   ```

3. Verify Console is connected to the correct cluster
4. Check Console logs for connection errors

### Performance Issues

**Problem**: Console is slow or unresponsive

**Solutions**:
1. Check Console pod resources:
   ```bash
   kubectl top pod -n redpanda -l app.kubernetes.io/name=redpanda-console
   ```

2. Increase Console resources if needed (edit HelmRelease values)
3. Reduce the number of topics/messages being displayed
4. Use filters to narrow down the data being queried

### Schema Registry Not Working

**Problem**: Schema Registry features not available

**Solutions**:
1. Verify Schema Registry is enabled in Redpanda cluster
2. Check Console configuration includes Schema Registry URL
3. Verify Schema Registry service is accessible:
   ```bash
   kubectl get svc -n redpanda | grep schema
   ```

## Additional Resources

- [Redpanda Console Documentation](https://docs.redpanda.com/current/manage/console/)
- [Redpanda Helm Chart Reference](https://docs.redpanda.com/current/reference/k-redpanda-helm-spec/)
- [Flux GitOps Documentation](https://fluxcd.io/flux/)

## Quick Reference Commands

```bash
# Port forward Console
kubectl port-forward svc/redpanda-console 8080:8080 -n redpanda

# Check Console pod status
kubectl get pods -n redpanda -l app.kubernetes.io/name=redpanda-console

# View Console logs
kubectl logs -n redpanda -l app.kubernetes.io/name=redpanda-console -f

# Check Console service
kubectl get svc -n redpanda redpanda-console

# Describe Console pod (for debugging)
kubectl describe pod -n redpanda -l app.kubernetes.io/name=redpanda-console
```

