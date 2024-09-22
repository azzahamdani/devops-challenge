# scripts/configure-control-plane.sh
#!/bin/bash
set -e

echo "Starting control plane configuration..."

# Retrieve instance metadata
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)

echo "Initializing single-node Kubernetes cluster..."
kubeadm init --pod-network-cidr=192.168.0.0/16 --kubernetes-version=1.30.4 --apiserver-advertise-address=$PRIVATE_IP

echo "Setting up kubectl for the root user..."
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

echo "Checking status of core components..."
crictl pods

echo "Checking kubelet status..."
systemctl status kubelet

echo "Checking kubelet logs..."
journalctl -xeu kubelet --no-pager | tail -n 50

echo "Attempting to get node status..."
kubectl get nodes -o wide || echo "Failed to get node status"

echo "Attempting to get pod status..."
kubectl get pods --all-namespaces || echo "Failed to get pod status"

# Generate the join command and store it in SSM Parameter Store
echo "Generating join command and storing in SSM..."
JOIN_COMMAND=$(kubeadm token create --print-join-command)
aws ssm put-parameter --name "/k8s/worker-join-command" --value "$JOIN_COMMAND" --type SecureString --overwrite --region $REGION

# Verify the parameter was created
aws ssm get-parameter --name "/k8s/worker-join-command" --with-decryption --region $REGION

echo "Join command stored in SSM Parameter Store"

# Patch the control plane node with provider ID
echo "Patching control plane node with provider ID..."
NODE_NAME=$(hostname)
kubectl patch node ${NODE_NAME} -p "{\"spec\":{\"providerID\":\"aws:///${AZ}/${INSTANCE_ID}\"}}"

echo "Control plane configuration completed."

