# scripts/install-cni.sh
#!/bin/bash
set -e

echo "Installing Calico CNI..."

# Install Calico operator and custom resource definitions
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/tigera-operator.yaml

# Wait for the operator to be ready
kubectl rollout status deployment/tigera-operator -n tigera-operator --timeout=90s

# Install Calico custom resources
kubectl create -f https://raw.githubusercontent.com/projectcalico/calico/v3.26.1/manifests/custom-resources.yaml

# Wait for Calico pods to be ready
echo "Waiting for Calico pods to be ready..."
kubectl wait --for=condition=ready pod -l k8s-app=calico-node -n calico-system --timeout=300s

echo "Calico CNI installation completed."