#!/bin/bash
set -ex

# Redirect output to both console and log file
# exec > >(tee /var/log/user-data-dependencies.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting control plane dependencies installation..."

# Check if script is run with root privileges
if [ "$(id -u)" -ne 0 ]; then
    echo "This script must be run as root. Please use sudo."
    exit 1
fi

# Function to check network connectivity
check_network() {
    for i in {1..60}; do
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

echo "Cleaning yum cache..."
yum clean all

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

echo "Installing yq..."
YQ_VERSION="v4.40.5"
YQ_BINARY="yq_linux_amd64"
retry_command "wget https://github.com/mikefarah/yq/releases/latest/download/yq_linux_amd64 -O /usr/bin/yq"
chmod +x /usr/bin/yq

echo "Verifying yq installation..."
yq --version

echo "Adding Helm to PATH permanently..."
echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc

echo "Downloading Helm installation script..."
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/main/scripts/get-helm-3

echo "Making the installation script executable..."
chmod 700 get_helm.sh

echo "Running Helm installation script..."
./get_helm.sh

echo "Helm installation completed successfully!"

echo "To use Helm in your current shell session, please run the following command:"
echo "    export PATH=\$PATH:/usr/local/bin"
echo "Alternatively, you can start a new shell session or run 'source ~/.bashrc'."
echo "For future sessions, the PATH will be set automatically when you log in."

echo "Control plane dependencies installation completed."