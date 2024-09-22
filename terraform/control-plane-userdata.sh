#!/bin/bash
set -e

# Redirect output to both console and log file
exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting control plane setup..."

# Function to check network connectivity
check_network() {
    for i in {1..30}; do
        if ping -c 1 amazon.com &> /dev/null; then
            echo "Network is up"
            return 0
        fi
        echo "Waiting for network... attempt $i"
        sleep 10
    done
    echo "Network is down"
    return 1
}

# Function to retry commands
retry_command() {
    local -r cmd="$1"
    local -r max_attempts=5
    local attempt=1

    until $cmd; do
        if ((attempt == max_attempts)); then
            echo "Command '$cmd' failed after $max_attempts attempts"
            return 1
        fi
        echo "Command '$cmd' failed. Retrying in 10 seconds... (Attempt $attempt of $max_attempts)"
        sleep 10
        ((attempt++))
    done
}

# Check network connectivity
check_network || exit 1

echo "Disabling Docker CE repository if present..."
yum-config-manager --disable docker-ce-stable || true

echo "Updating the system..."
retry_command "yum update -y"

echo "Installing necessary dependencies..."
retry_command "yum install -y yum-utils device-mapper-persistent-data lvm2 ebtables socat tc awscli wget git"

echo "Installing containerd from Amazon Linux Extras..."
retry_command "amazon-linux-extras enable docker"
retry_command "yum install -y containerd"

echo "Configuring containerd..."
mkdir -p /etc/containerd
containerd config default | sudo tee /etc/containerd/config.toml
sed -i 's/SystemdCgroup = false/SystemdCgroup = true/' /etc/containerd/config.toml

echo "Restarting and enabling containerd..."
systemctl restart containerd
systemctl enable containerd

echo "Checking if cri-tools 1.30 is already installed..."
if rpm -q cri-tools | grep -q '1.30'; then
    echo "cri-tools 1.30 is already installed. Skipping installation."
else
    echo "Installing cri-tools 1.30..."
    retry_command "wget https://pkgs.k8s.io/core:/stable:/v1.30/rpm/x86_64/cri-tools-1.30.0-150500.1.1.x86_64.rpm"
    retry_command "rpm -Uvh cri-tools-1.30.0-150500.1.1.x86_64.rpm"
fi

echo "Verifying cri-tools version..."
crictl --version

echo "Adding Kubernetes repo..."
cat <<EOF | sudo tee /etc/yum.repos.d/kubernetes.repo
[kubernetes]
name=Kubernetes
baseurl=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/
enabled=1
gpgcheck=1
gpgkey=https://pkgs.k8s.io/core:/stable:/v1.30/rpm/repodata/repomd.xml.key
exclude=kubelet kubeadm kubectl cri-tools kubernetes-cni
EOF

echo "Installing kubelet, kubeadm, and kubectl..."
retry_command "yum install -y kubelet-1.30.4 kubeadm-1.30.4 kubectl-1.30.4 --disableexcludes=kubernetes"

echo "Enabling kubelet..."
systemctl enable kubelet

echo "Disabling SELinux..."
if [ "$(getenforce)" != "Disabled" ]; then
    echo "SELinux is enabled. Disabling it now..."
    setenforce 0
    sed -i 's/^SELINUX=enforcing$/SELINUX=permissive/' /etc/selinux/config
else
    echo "SELinux is already disabled. Skipping this step."
fi

echo "Disabling swap..."
swapoff -a
sed -i '/ swap / s/^\(.*\)$/#\1/g' /etc/fstab

echo "Setting up required sysctl params..."
cat <<EOF | sudo tee /etc/sysctl.d/k8s.conf
net.bridge.bridge-nf-call-ip6tables = 1
net.bridge.bridge-nf-call-iptables = 1
net.ipv4.ip_forward = 1
EOF
sysctl --system

echo "Configuring containerd modules..."
cat <<EOF | sudo tee /etc/modules-load.d/containerd.conf
overlay
br_netfilter
EOF

modprobe overlay
modprobe br_netfilter

echo "Retrieving instance metadata..."
INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
AZ=$(curl -s http://169.254.169.254/latest/meta-data/placement/availability-zone)

# Get the private IP address
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

echo "Control plane setup completed."