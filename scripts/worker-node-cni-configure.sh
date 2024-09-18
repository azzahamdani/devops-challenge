#!/bin/bash
set -ex

echo "Configuring kubelet for VPC CNI..."

# Function to calculate max pods
calculate_max_pods() {
    local instance_type=$1
    local max_pods

    # This is a simplified version and may not cover all instance types
    # For a complete list, refer to the official AWS documentation
    case $instance_type in
        t3.micro|t3.small|t3a.micro|t3a.small)
            max_pods=4
            ;;
        t3.medium|t3a.medium)
            max_pods=17
            ;;
        t3.large|t3a.large)
            max_pods=35
            ;;
        t3.xlarge|t3a.xlarge)
            max_pods=58
            ;;
        t3.2xlarge|t3a.2xlarge)
            max_pods=58
            ;;
        m5.large|m5a.large)
            max_pods=29
            ;;
        m5.xlarge|m5a.xlarge)
            max_pods=58
            ;;
        m5.2xlarge|m5a.2xlarge)
            max_pods=58
            ;;
        m5.4xlarge|m5a.4xlarge)
            max_pods=234
            ;;
        *)
            # Default to a safe value if instance type is not recognized
            max_pods=110
            ;;
    esac

    echo $max_pods
}

INSTANCE_ID=$(curl -s http://169.254.169.254/latest/meta-data/instance-id)
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
PRIVATE_IP=$(curl -s http://169.254.169.254/latest/meta-data/local-ipv4)
INSTANCE_TYPE=$(curl -s http://169.254.169.254/latest/meta-data/instance-type)

echo "Get instance type and calculate max pods"
MAX_PODS=$(calculate_max_pods $INSTANCE_TYPE)


echo "Instance type: $INSTANCE_TYPE, Max pods: $MAX_PODS, Private IP: $PRIVATE_IP, Region: $REGION"

echo "Update the kubelet configuration file"
cat <<EOF > /var/lib/kubelet/config.yaml
apiVersion: kubelet.config.k8s.io/v1beta1
kind: KubeletConfiguration
authentication:
  anonymous:
    enabled: false
  webhook:
    cacheTTL: 0s
    enabled: true
  x509:
    clientCAFile: /etc/kubernetes/pki/ca.crt
authorization:
  mode: Webhook
  webhook:
    cacheAuthorizedTTL: 0s
    cacheUnauthorizedTTL: 0s
cgroupDriver: systemd
clusterDNS:
- 10.96.0.10
clusterDomain: cluster.local
cpuManagerReconcilePeriod: 0s
evictionPressureTransitionPeriod: 0s
fileCheckFrequency: 0s
healthzBindAddress: 127.0.0.1
healthzPort: 10248
httpCheckFrequency: 0s
imageMinimumGCAge: 0s
logging:
  flushFrequency: 0
  options:
    json:
      infoBufferSize: "0"
  verbosity: 0
memorySwap: {}
nodeStatusReportFrequency: 0s
nodeStatusUpdateFrequency: 0s
rotateCertificates: true
runtimeRequestTimeout: 0s
shutdownGracePeriod: 0s
shutdownGracePeriodCriticalPods: 0s
staticPodPath: /etc/kubernetes/manifests
streamingConnectionIdleTimeout: 0s
syncFrequency: 0s
volumeStatsAggPeriod: 0s
maxPods: $MAX_PODS
address: $PRIVATE_IP
networkPlugin: "cni"
cniConfigDir: "/etc/cni/net.d"
cniBinDir: "/opt/cni/bin"
nodeIp: $PRIVATE_IP
EOF

echo "Update the kubelet service configuration (keep as is)"
cat <<EOF > /usr/lib/systemd/system/kubelet.service.d/10-kubeadm.conf
# Note: This dropin only works with kubeadm and kubelet v1.11+
[Service]
Environment="KUBELET_KUBECONFIG_ARGS=--bootstrap-kubeconfig=/etc/kubernetes/bootstrap-kubelet.conf --kubeconfig=/etc/kubernetes/kubelet.conf"
Environment="KUBELET_CONFIG_ARGS=--config=/var/lib/kubelet/config.yaml"
# This is a file that "kubeadm init" and "kubeadm join" generates at runtime, populating the KUBELET_KUBEADM_ARGS variable dynamically
EnvironmentFile=-/var/lib/kubelet/kubeadm-flags.env
# This is a file that the user can use for overrides of the kubelet args as a last resort. Preferably, the user should use
# the .NodeRegistration.KubeletExtraArgs object in the configuration files instead. KUBELET_EXTRA_ARGS should be sourced from this file.
EnvironmentFile=-/etc/sysconfig/kubelet
ExecStart=
ExecStart=/usr/bin/kubelet \$KUBELET_KUBECONFIG_ARGS \$KUBELET_CONFIG_ARGS \$KUBELET_KUBEADM_ARGS \$KUBELET_EXTRA_ARGS
EOF

echo "Reload systemd and restart kubelet"
systemctl daemon-reload
systemctl restart kubelet