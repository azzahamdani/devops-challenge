#!/bin/bash

set -e

# Function to check if a command exists
command_exists() {
    command -v "$1" >/dev/null 2>&1
}

# Check for required commands
for cmd in kubectl aws curl; do
    if ! command_exists $cmd; then
        echo "Error: $cmd is not installed. Please install it and try again."
        exit 1
    fi
done

echo "Authenticating with Amazon ECR..."
if ! AWS_ACCOUNT_ID=$(aws sts get-caller-identity --query "Account" --output text); then
    echo "Error: Failed to get AWS account ID. Make sure you have the correct AWS credentials configured."
    exit 1
fi

if ! REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region); then
    echo "Error: Failed to get AWS region. Are you running this on an EC2 instance?"
    exit 1
fi

if ! TOKEN=$(aws ecr get-login-password --region $REGION); then
    echo "Error: Failed to get ECR token. Check your AWS credentials and permissions."
    exit 1
fi

echo "Creating ECR secret in kube-system namespace..."
kubectl create secret docker-registry ecr-secret \
  --docker-server=602401143452.dkr.ecr.$REGION.amazonaws.com \
  --docker-username=AWS \
  --docker-password=$TOKEN \
  --namespace=kube-system \
  --dry-run=client -o yaml | kubectl apply -f -

echo "Removing existing CoreDNS deployment..."
kubectl delete deployment coredns -n kube-system --ignore-not-found=true

echo "Creating CoreDNS ConfigMap..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: ConfigMap
metadata:
  name: coredns
  namespace: kube-system
  labels:
    eks.amazonaws.com/component: coredns
    k8s-app: kube-dns
data:
  Corefile: |
    .:53 {
        errors
        health {
            lameduck 5s
        }
        ready
        kubernetes cluster.local in-addr.arpa ip6.arpa {
            pods insecure
            fallthrough in-addr.arpa ip6.arpa
        }
        prometheus :9153
        forward . /etc/resolv.conf
        cache 30
        loop
        reload
        loadbalance
    }
EOF

echo "Creating CoreDNS Deployment..."
cat <<EOF | kubectl apply -f -
apiVersion: apps/v1
kind: Deployment
metadata:
  name: coredns
  namespace: kube-system
  labels:
    eks.amazonaws.com/component: coredns
    k8s-app: kube-dns
    kubernetes.io/name: CoreDNS
spec:
  replicas: 2
  selector:
    matchLabels:
      eks.amazonaws.com/component: coredns
      k8s-app: kube-dns
  strategy:
    type: RollingUpdate
    rollingUpdate:
      maxUnavailable: 1
  template:
    metadata:
      labels:
        eks.amazonaws.com/component: coredns
        k8s-app: kube-dns
    spec:
      priorityClassName: system-cluster-critical
      serviceAccountName: coredns
      affinity:
        nodeAffinity:
          requiredDuringSchedulingIgnoredDuringExecution:
            nodeSelectorTerms:
            - matchExpressions:
              - key: kubernetes.io/os
                operator: In
                values:
                - linux
              - key: kubernetes.io/arch
                operator: In
                values:
                - amd64
                - arm64
        podAntiAffinity:
          preferredDuringSchedulingIgnoredDuringExecution:
          - weight: 100
            podAffinityTerm:
              labelSelector:
                matchExpressions:
                - key: k8s-app
                  operator: In
                  values:
                  - kube-dns
              topologyKey: kubernetes.io/hostname
      containers:
      - name: coredns
        image: 602401143452.dkr.ecr.$REGION.amazonaws.com/eks/coredns:v1.11.1-eksbuild.8
        imagePullPolicy: IfNotPresent
        resources:
          limits:
            memory: 170Mi
          requests:
            cpu: 100m
            memory: 70Mi
        args: [ "-conf", "/etc/coredns/Corefile" ]
        volumeMounts:
        - name: config-volume
          mountPath: /etc/coredns
          readOnly: true
        ports:
        - containerPort: 53
          name: dns
          protocol: UDP
        - containerPort: 53
          name: dns-tcp
          protocol: TCP
        - containerPort: 9153
          name: metrics
          protocol: TCP
        securityContext:
          allowPrivilegeEscalation: false
          capabilities:
            add:
            - NET_BIND_SERVICE
            drop:
            - all
          readOnlyRootFilesystem: true
        livenessProbe:
          httpGet:
            path: /health
            port: 8080
            scheme: HTTP
          initialDelaySeconds: 60
          timeoutSeconds: 5
          successThreshold: 1
          failureThreshold: 5
        readinessProbe:
          httpGet:
            path: /ready
            port: 8181
            scheme: HTTP
          initialDelaySeconds: 0
          periodSeconds: 10
          timeoutSeconds: 1
          successThreshold: 1
          failureThreshold: 3
      dnsPolicy: Default
      volumes:
        - name: config-volume
          configMap:
            name: coredns
            items:
            - key: Corefile
              path: Corefile
      nodeSelector:
        kubernetes.io/os: linux
      tolerations:
        - key: "CriticalAddonsOnly"
          operator: "Exists"
      imagePullSecrets:
        - name: ecr-secret
EOF

echo "Creating CoreDNS Service..."
cat <<EOF | kubectl apply -f -
apiVersion: v1
kind: Service
metadata:
  name: kube-dns
  namespace: kube-system
  annotations:
    prometheus.io/port: "9153"
    prometheus.io/scrape: "true"
  labels:
    eks.amazonaws.com/component: kube-dns
    k8s-app: kube-dns
    kubernetes.io/cluster-service: "true"
    kubernetes.io/name: CoreDNS
spec:
  selector:
    k8s-app: kube-dns
  clusterIP: 10.96.0.10
  ports:
  - name: dns
    port: 53
    protocol: UDP
  - name: dns-tcp
    port: 53
    protocol: TCP
  - name: metrics
    port: 9153
    protocol: TCP
EOF

echo "Waiting for CoreDNS pods to be ready..."
kubectl wait --for=condition=Ready pods -l k8s-app=kube-dns -n kube-system --timeout=300s

echo "Verifying CoreDNS deployment..."
kubectl get pods -n kube-system -l k8s-app=kube-dns
kubectl get svc -n kube-system kube-dns

echo "CoreDNS installation complete."