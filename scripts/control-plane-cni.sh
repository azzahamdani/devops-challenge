#!/bin/bash
set -e

echo "Starting Calico installation..."

# Ensure kubectl is configured
export KUBECONFIG=/etc/kubernetes/admin.conf

echo "Applying Calico manifest..."
kubectl apply -f https://docs.projectcalico.org/manifests/calico.yaml --validate=false

echo "Waiting for 60 seconds to allow Calico to initialize..."
sleep 60

echo "Checking pod status..."
kubectl get pods --all-namespaces

echo "Removing control-plane taint..."
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || echo "Failed to remove control-plane taint"

echo "Calico installation completed."