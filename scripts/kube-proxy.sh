#!/bin/bash
set -e

echo "Starting kube-proxy update process for EKS compatibility while preserving kubeadm kubeconfig..."

# Backup existing kube-proxy configuration
echo "Backing up existing kube-proxy configuration..."
kubectl get configmap kube-proxy -n kube-system -o yaml > kube-proxy-configmap-backup.yaml
kubectl get daemonset kube-proxy -n kube-system -o yaml > kube-proxy-daemonset-backup.yaml

# Extract kubeconfig from existing ConfigMap
echo "Extracting kubeconfig from existing ConfigMap..."
KUBECONFIG=$(kubectl get configmap kube-proxy -n kube-system -o jsonpath='{.data.kubeconfig\.conf}')

# Update kube-proxy ConfigMap
echo "Updating kube-proxy ConfigMap..."
kubectl create -f - <<EOF
apiVersion: v1
kind: ConfigMap
metadata:
  name: kube-proxy
  namespace: kube-system
  labels:
    app: kube-proxy
data:
  config.conf: |
    apiVersion: kubeproxy.config.k8s.io/v1alpha1
    bindAddress: 0.0.0.0
    clientConnection:
      acceptContentTypes: ""
      burst: 10
      contentType: application/vnd.kubernetes.protobuf
      kubeconfig: /var/lib/kube-proxy/kubeconfig.conf
      qps: 5
    clusterCIDR: ""
    configSyncPeriod: 15m0s
    conntrack:
      maxPerCore: 32768
      min: 131072
      tcpCloseWaitTimeout: 1h0m0s
      tcpEstablishedTimeout: 24h0m0s
    enableProfiling: false
    healthzBindAddress: 0.0.0.0:10256
    hostnameOverride: ""
    iptables:
      masqueradeAll: false
      masqueradeBit: 14
      minSyncPeriod: 0s
      syncPeriod: 30s
    ipvs:
      excludeCIDRs: null
      minSyncPeriod: 0s
      scheduler: ""
      syncPeriod: 30s
    kind: KubeProxyConfiguration
    metricsBindAddress: 0.0.0.0:10249
    mode: "iptables"
    nodePortAddresses: null
    oomScoreAdj: -998
    portRange: ""
  kubeconfig.conf: |
$KUBECONFIG
EOF

# Update kube-proxy DaemonSet
echo "Updating kube-proxy DaemonSet..."
kubectl apply -f - <<EOF
apiVersion: apps/v1
kind: DaemonSet
metadata:
  labels:
    k8s-app: kube-proxy
  name: kube-proxy
  namespace: kube-system
spec:
  selector:
    matchLabels:
      k8s-app: kube-proxy
  template:
    metadata:
      labels:
        k8s-app: kube-proxy
    spec:
      containers:
      - command:
        - kube-proxy
        - --config=/var/lib/kube-proxy/config.conf
        - --hostname-override=$(NODE_NAME)
        env:
        - name: NODE_NAME
          valueFrom:
            fieldRef:
              apiVersion: v1
              fieldPath: spec.nodeName
        image: 602401143452.dkr.ecr.us-east-1.amazonaws.com/eks/kube-proxy:v1.30.0-minimal-eksbuild.3
        imagePullPolicy: IfNotPresent
        name: kube-proxy
        resources:
          requests:
            cpu: 100m
        securityContext:
          privileged: true
        volumeMounts:
        - mountPath: /var/lib/kube-proxy
          name: kube-proxy
        - mountPath: /run/xtables.lock
          name: xtables-lock
        - mountPath: /lib/modules
          name: lib-modules
          readOnly: true
      dnsPolicy: ClusterFirst
      hostNetwork: true
      nodeSelector:
        kubernetes.io/os: linux
      priorityClassName: system-node-critical
      restartPolicy: Always
      schedulerName: default-scheduler
      serviceAccount: kube-proxy
      serviceAccountName: kube-proxy
      terminationGracePeriodSeconds: 30
      tolerations:
      - operator: Exists
      volumes:
      - configMap:
          name: kube-proxy
        name: kube-proxy
      - hostPath:
          path: /run/xtables.lock
          type: FileOrCreate
        name: xtables-lock
      - hostPath:
          path: /lib/modules
          type: ""
        name: lib-modules
  updateStrategy:
    rollingUpdate:
      maxSurge: 0
      maxUnavailable: 1
    type: RollingUpdate
EOF

# Wait for kube-proxy pods to be updated
echo "Waiting for kube-proxy pods to be updated..."
kubectl rollout status daemonset kube-proxy -n kube-system --timeout=300s

echo "kube-proxy pods status:"
kubectl get pods -n kube-system -l k8s-app=kube-proxy

echo "kube-proxy logs:"
kubectl logs -n kube-system -l k8s-app=kube-proxy --tail=20

echo "kube-proxy update completed successfully."