# DevOps Challenge: Cloud Infrastructure and Custom Kubernetes Configuration

## Table of Contents

1. [Project Overview](#project-overview)
2. [Architecture Overview](#architecture-overview)
3. [Prerequisites](#prerequisites)
4. [Step-by-Step Guide](#step-by-step-guide)
   1. [Infrastructure Setup](#1-infrastructure-setup)
   2. [Accessing the Control Plane](#2-accessing-the-control-plane)
   3. [Cluster Configuration](#3-cluster-configuration)
   4. [Load Balancer Controller Installation](#4-load-balancer-controller-installation)
   5. [TLS Certificate Configuration](#5-tls-certificate-configuration)
   6. [Prometheus Observability Setup](#6-prometheus-observability-setup)
   7. [GitOps with ArgoCD](#7-gitops-with-argocd)
5. [Verification and Monitoring](#verification-and-monitoring)
6. [Troubleshooting](#troubleshooting)
7. [Security Considerations](#security-considerations)
8. [Scaling and Performance](#scaling-and-performance)
9. [Maintenance and Updates](#maintenance-and-updates)
10. [Conclusion](#conclusion)

## Project Overview

This DevOps challenge aims to demonstrate the setup and configuration of a robust, scalable, and secure cloud infrastructure on AWS. The project showcases the implementation of a custom Kubernetes cluster, along with essential components for networking, observability, and GitOps practices. This setup provides a solid foundation for deploying and managing containerized applications in a production-like environment.

Key features of this project include:
- Custom Kubernetes cluster provisioned on EC2 instances
- Networking configuration with CNI and Load Balancer
- Observability stack with Prometheus and Grafana
- GitOps workflow using ArgoCD
- Secure communication with TLS certificates

## Architecture Overview

Our infrastructure consists of the following components:

1. **Cloud Infrastructure**:
   - AWS VPC with public and private subnets
   - Security groups and IAM roles for EC2 instances

2. **Kubernetes Cluster**:
   - Custom K8s cluster provisioned on EC2 instances
   - Master Node: Single EC2 instance serving as the control plane
   - Worker Nodes: EC2 Auto Scaling group with 3 initial instances

3. **Networking**:
   - Container Network Interface (CNI) plugin for pod networking
   - AWS Load Balancer Controller for managing ALBs/NLBs

4. **Observability**:
   - Prometheus for metrics collection
   - Grafana for visualization and dashboards

5. **GitOps**:
   - ArgoCD for declarative, Git-based delivery of Kubernetes resources

6. **Security**:
   - TLS certificates managed by AWS Certificate Manager (ACM)
   - Secure communication between components and external access

## Prerequisites

Before starting this project, ensure you have the following:

- AWS account with appropriate permissions
- AWS CLI configured with your credentials
- Terraform installed (version 0.14 or later)
- kubectl installed
- Helm installed (version 3.x)
- Git client

## Step-by-Step Guide

### 1. Infrastructure Setup

This step uses Terraform to provision the foundational AWS infrastructure.

```bash
cd terraform
terraform init
terraform validate
terraform plan
terraform apply
```

Key resources created:
- VPC with public and private subnets
- Security groups
- IAM roles and policies
- EC2 instances for Kubernetes nodes

### 2. Accessing the Control Plane

Access the master node (control plane) using AWS Systems Manager (SSM) for cluster management.

```bash
# List instances with SSM capability
aws ssm describe-instance-information --query 'InstanceInformationList[*].[InstanceId, PingStatus]'

# Start SSM session (replace with your instance ID)
aws ssm start-session --target i-1234567890abcdef0
```

Verify cluster access:
```bash
kubectl get nodes
```

Source bashrc

### 3. Cluster Configuration

Configure the Kubernetes cluster with CNI and set up worker nodes.

```bash
git clone https://github.com/azzahamdani/devops-challenge.git
cd devops-challenge/scripts

# Configure CNI
chmod +x ./control-plane-cni.sh
./control-plane-cni.sh

# Configure worker nodes
chmod +x nodes-configure.sh
./nodes-configure.sh
```

This step ensures proper network configuration and node registration within the cluster.

### 4. Load Balancer Controller Installation

Install the AWS Load Balancer Controller to manage ALB/NLB resources.

```bash
chmod +x alb-controller-configure.sh
./alb-controller-configure.sh
```

This controller allows Kubernetes to interact with AWS load balancing services, enabling external access to services.

### 5. TLS Certificate Configuration

Set up TLS certificates using AWS Certificate Manager (ACM) for secure communications.

```bash
chmod +x certificate-configure.sh
./certificate-configure.sh
```

This step ensures encrypted traffic between clients and the cluster services.

### 6. Prometheus Observability Setup

Install and configure Prometheus and Grafana for cluster monitoring and visualization.

```bash
chmod +x prometheus-configure.sh
./prometheus-configure.sh
```

This observability stack provides insights into cluster performance, resource utilization, and application metrics.

### 7. GitOps with ArgoCD

Set up ArgoCD to implement GitOps practices for managing Kubernetes resources.

```bash
chmod +x argocd-configure.sh
./argocd-configure.sh
```

ArgoCD enables declarative, version-controlled application deployment and management.

## Verification and Monitoring

After completing the setup, verify the deployment:

1. Check node status: `kubectl get nodes`
2. Verify pod status: `kubectl get pods --all-namespaces`
3. Access Grafana dashboards for cluster metrics
4. Log into ArgoCD UI to manage application deployments

## Troubleshooting

Common issues and their solutions:

- **Node Registration Issues**: 
  - Verify CNI configuration
  - Check node labels and taints
- **Load Balancer Problems**:
  - Ensure correct annotations on services
  - Verify AWS Load Balancer Controller logs
- **TLS Certificate Errors**:
  - Double-check domain configurations in ACM
  - Verify certificate ARNs in Kubernetes resources

## Security Considerations

- Regularly update and patch all components
- Implement network policies to control pod-to-pod communication
- Use RBAC to manage access to Kubernetes resources
- Enable audit logging for cluster activities
- Implement secrets management (e.g., AWS Secrets Manager or HashiCorp Vault)

## Scaling and Performance

- Monitor node resource utilization and adjust Auto Scaling group as needed
- Implement Horizontal Pod Autoscaler (HPA) for application workloads
- Consider using Cluster Autoscaler for automatic node scaling
- Optimize etcd performance and backups

## Maintenance and Updates

- Regularly update Kubernetes and all installed components
- Plan for zero-downtime upgrades of the cluster
- Implement a robust backup and disaster recovery strategy
- Continuously review and update security policies

## Conclusion

This project demonstrates a comprehensive approach to setting up a production-ready Kubernetes environment on AWS. By following these steps and best practices, you've created a scalable, observable, and manageable infrastructure suitable for hosting containerized applications.

Remember to continually monitor, optimize, and update your infrastructure to maintain its efficiency and security. As your needs evolve, consider exploring advanced topics such as service mesh implementation, advanced networking policies, or multi-cluster deployments.
