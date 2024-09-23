Here’s the updated README with an additional step for SSM into the control plane before the CNI configuration:

---

# DevOps Challenge: Cloud Infrastructure and Kubernetes Configuration

## Table of Contents

1. [Application Architecture Overview](#application-architecture-overview)
2. [Step 1: Infrastructure Setup](#step-1-infrastructure-setup)
3. [Step 2: Accessing the Control Plane](#step-2-accessing-the-control-plane)
4. [Step 3: Cluster Configuration with CNI and Node Setup](#step-3-cluster-configuration-with-cni-and-node-setup)
5. [Step 4: Installing Application Load Balancer Controller](#step-4-installing-application-load-balancer-controller)
6. [Step 5: Configuring TLS Certificates](#step-5-configuring-tls-certificates)
7. [Step 6: Configuring Prometheus Observability](#step-6-configuring-prometheus-observability)
8. [Step 7: Configuring GitOps with ArgoCD](#step-7-configuring-gitops-with-argocd)
9. [Screenshots](#screenshots)
10. [Troubleshooting and Known Issues](#troubleshooting-and-known-issues)
11. [Conclusion](#conclusion)

## Application Architecture Overview

This challenge aims to build and configure a secure, highly available cloud infrastructure on AWS using Terraform. We will then deploy a Kubernetes cluster, configure it with CNI, Load Balancer, Prometheus, and ArgoCD for observability and GitOps. Finally, we will configure TLS certificates to secure the setup.

### Architecture Components:

1. **Cloud Infrastructure**: AWS VPC, public/private subnets, EKS cluster.
2. **Kubernetes Cluster**: EKS cluster with CNI plugin and Load Balancer Controller.
3. **Observability**: Prometheus and Grafana.
4. **GitOps**: ArgoCD for managing Kubernetes resources.
5. **TLS**: ACM certificates for secure access to services.

## Step 1: Infrastructure Setup

Set up the foundational infrastructure using Terraform.

### Commands

```bash
terraform init 
terraform validate
terraform plan 
terraform apply 
```

### Expected Output

```
Apply complete! Resources: 80 added, 0 changed, 0 destroyed.

Outputs:

private_subnets = [
  "subnet-00319a94683a625aa",
  "subnet-0128304fb4819130e",
  "subnet-056e47be12d1edb29",
]
public_subnets = [
  "subnet-0909d03fc581e5b6d",
  "subnet-0a216a372c9bdbd04",
  "subnet-0b12aeadba1f22abb",
]
vpc_cidr_block = "10.0.0.0/16"
vpc_id = "vpc-0697610217117fd52"
```

## Step 2: Accessing the Control Plane

In this step, you will access the control plane instance using AWS Systems Manager (SSM) to perform operational tasks and monitor the cluster. This instance acts as the operations center for your infrastructure.

### Commands

1. **List Running Instances with SSM Capability:**

   ```bash
   aws ssm describe-instance-information --query 'InstanceInformationList[*].[InstanceId, PingStatus]'
   ```

   This command will list all instances in your account that have the SSM agent running and are accessible via SSM.

2. **SSM into the Control Plane Instance:**

   Replace `instance-id` with the actual instance ID of the control plane.

   ```bash
   aws ssm start-session --target instance-id
   ```

   This command initiates an SSM session into the control plane instance. You can use this session to perform administrative tasks on the control plane.

3. **Verify Control Plane Access:**

   Once inside the instance, verify access by checking the Kubernetes cluster status.

   ```bash
   kubectl get nodes
   ```

   You should see a list of nodes connected to the EKS cluster, indicating that the control plane has access to manage the cluster.

### Expected Output

```
Starting session with SessionId: my-session-id
```

You are now connected to the control plane instance, which acts as the operations center for managing your infrastructure.

## Step 3: Cluster Configuration with CNI and Node Setup

### Prerequisites

Ensure you have access to the control plane instance as described in Step 2.

### Commands

```bash
git clone https://github.com/azzahamdani/devops-challenge.git
cd devops-challenge/scripts

chmod +x ./control-plane-cni.sh 
./control-plane-cni.sh

chmod +x nodes-configure.sh 
./nodes-configure.sh
```

### Expected Output

```
Processing node: ip-10-0-1-100.ec2.internal
Patching node ip-10-0-1-100.ec2.internal with provider ID aws://us-east-1a/i-000307ea1010bad1c
node/ip-10-0-1-100.ec2.internal patched
...
Finished checking nodes..
```

This step configures the CNI and prepares the nodes in the EKS cluster.

## Step 4: Installing Application Load Balancer Controller

### Commands

```bash
chmod +x alb-controller-configure.sh
./alb-controller-configure.sh
```

### Expected Output

```
AWS Load Balancer controller installed!
+ kubectl get deployment -n kube-system aws-load-balancer-controller
NAME                           READY   UP-TO-DATE   AVAILABLE   AGE
aws-load-balancer-controller   0/2     2            0           0s
```

This script installs the AWS Load Balancer Controller in your Kubernetes cluster.

## Step 5: Configuring TLS Certificates

### Commands

```bash
chmod +x certificate-configure.sh
./certificate-configure.sh
```

### Expected Output

```
Certificate validated successfully!
```

This step configures ACM certificates for secure communication with your services. Certificates will be used in subsequent steps.

## Step 6: Configuring Prometheus Observability

### Commands

```bash
chmod +x prometheus-configure.sh
./prometheus-configure.sh
```

### Expected Output

```
kube-prometheus-stack has been installed. Check its status by running:
  kubectl --namespace monitoring get pods -l "release=prometheus"
...
Deployment completed successfully!
```

This script installs Prometheus using Helm and configures observability for the Kubernetes cluster.

## Step 7: Configuring GitOps with ArgoCD

### Commands

```bash
chmod +x argocd-configure.sh
./argocd-configure.sh
```

### Expected Output

```
ArgoCD deployment completed successfully!
ArgoCD is now accessible at: https://argocd.767398115325.realhandsonlabs.net
```

This script installs ArgoCD, adds Helm repositories, and configures ArgoCD for GitOps, leveraging the certificates configured in Step 5.

## Screenshots

Include screenshots of the following components:

1. **Load Balancer**: ALB with DNS.
2. **Grafana**: Grafana dashboard.
3. **ArgoCD**: ArgoCD dashboard.

## Troubleshooting and Known Issues

- **Issue**: Nodes not registering correctly.
  - **Solution**: Ensure the CNI plugin is correctly configured and nodes are patched with the right provider ID.
  
- **Issue**: TLS certificate validation failure.
  - **Solution**: Double-check the domain names and CNAME records in Route53.

## Conclusion

Congratulations! You have successfully set up a robust cloud infrastructure with Kubernetes, observability, and GitOps. Feel free to explore and enhance this setup further.

---

Let me know if you'd like to include any additional details or modifications!