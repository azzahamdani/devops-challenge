#!/bin/bash
set -ex

# Redirect output to both console and log file
# exec > >(tee /var/log/user-data-configure.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting control plane configuration..."

# Check and log the executing user
EXECUTING_USER=$(whoami)
echo "Script is being executed by user: $EXECUTING_USER"

# Ensure we're running as root
if [ "$EXECUTING_USER" != "root" ]; then
    echo "This script must be run as root. Current user is $EXECUTING_USER. Exiting."
    exit 1
fi

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
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)

echo "Initializing single-node Kubernetes cluster..."
kubeadm init --pod-network-cidr=192.168.0.0/16 --kubernetes-version=1.30.4 --apiserver-advertise-address=$PRIVATE_IP || { echo "kubeadm init failed"; exit 1; }

echo "Setting up kubectl for the root user..."
mkdir -p /root/.kube
cp -i /etc/kubernetes/admin.conf /root/.kube/config
chown root:root /root/.kube/config

echo "Create a system-wide kubectl config"
mkdir -p /etc/kubernetes/kubectl
cp -i /etc/kubernetes/admin.conf /etc/kubernetes/kubectl/config
chmod 644 /etc/kubernetes/kubectl/config

echo "Set KUBECONFIG environment variable system-wide"
echo "export KUBECONFIG=/etc/kubernetes/kubectl/config" | tee -a /etc/profile.d/kubeconfig.sh

echo "Source the new environment variable"
source /etc/profile.d/kubeconfig.sh

# Create a script to set up kubectl for SSM user on first login
cat <<EOF > /usr/local/bin/setup-ssm-kubectl.sh
#!/bin/bash
if [ ! -d /home/ssm-user/.kube ]; then
    mkdir -p /home/ssm-user/.kube
    cp /etc/kubernetes/kubectl/config /home/ssm-user/.kube/config
    chown -R ssm-user:ssm-user /home/ssm-user/.kube
    chmod 600 /home/ssm-user/.kube/config
fi
EOF

chmod +x /usr/local/bin/setup-ssm-kubectl.sh

# Add the setup script to ssm-user's .bashrc
echo "/usr/local/bin/setup-ssm-kubectl.sh" >> /etc/ssm-user-profile.sh

echo "Verifying kubectl configuration..."
kubectl config view
kubectl cluster-info

echo "Waiting for API server to be ready..."
timeout=300
elapsed=0
while ! kubectl get --raw='/readyz' &>/dev/null; do
    sleep 5
    elapsed=$((elapsed+5))
    if [ "$elapsed" -ge "$timeout" ]; then
        echo "Timeout waiting for API server to become ready"
        break
    fi
    echo "Waiting for API server... ($elapsed seconds elapsed)"
done

echo "Remove the taint on the control-plane node to allow pod scheduling"
kubectl taint nodes --all node-role.kubernetes.io/control-plane- || true

echo "Generating join command and storing in SSM..."
JOIN_COMMAND=$(kubeadm token create --print-join-command)
aws ssm put-parameter --name "/k8s/worker-join-command" --value "$JOIN_COMMAND" --type SecureString --overwrite --region $REGION

echo "Verify the parameter was created"
aws ssm get-parameter --name "/k8s/worker-join-command" --with-decryption --region $REGION

echo "Join command stored in SSM Parameter Store"

