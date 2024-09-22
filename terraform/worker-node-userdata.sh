#!/bin/bash
set -e

exec > >(tee /var/log/user-data.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting worker node setup..."

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
retry_command "yum install -y yum-utils device-mapper-persistent-data lvm2 ebtables socat tc"

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

echo "Installing kubelet and kubeadm..."
retry_command "yum install -y kubelet-1.30.4 kubeadm-1.30.4 --disableexcludes=kubernetes"

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

# Function to retrieve join command from SSM with retries
get_join_command() {
    local retries=10
    local wait_time=30
    local counter=0
    while [ $counter -lt $retries ]; do
        REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
        JOIN_COMMAND=$(aws ssm get-parameter --name "/k8s/worker-join-command" --with-decryption --query "Parameter.Value" --output text --region $REGION 2>/dev/null)
        if [ $? -eq 0 ] && [ ! -z "$JOIN_COMMAND" ]; then
            echo "Successfully retrieved join command"
            return 0
        fi
        echo "Failed to retrieve join command. Retrying in $wait_time seconds... (Attempt $((counter+1)) of $retries)"
        sleep $wait_time
        ((counter++))
    done
    echo "Failed to retrieve join command after $retries attempts"
    return 1
}

# Retrieve and execute join command
echo "Retrieving join command from SSM..."
if get_join_command; then
    echo "Joining the Kubernetes cluster..."
    $JOIN_COMMAND
else
    echo "Failed to join the cluster. Unable to retrieve join command."
    exit 1
fi

echo "Worker node setup completed."