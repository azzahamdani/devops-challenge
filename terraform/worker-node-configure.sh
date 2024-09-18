#!/bin/bash
set -ex

# Redirect output to both console and log file
# exec > >(tee /var/log/user-data-configure.log|logger -t user-data -s 2>/dev/console) 2>&1

echo "Starting worker node configuration..."

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
    local retries=20
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
    $JOIN_COMMAND || { echo "Failed to join the cluster"; exit 1; }
else
    echo "Failed to join the cluster. Unable to retrieve join command."
    exit 1
fi

echo "Worker node configuration completed."