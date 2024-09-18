### Step 1: AWS Infrastructure & Kubernetes Bootstrapping with `kubeadm` (using SSM)

---

#### Infrastructure Overview

This project provisions an AWS infrastructure to bootstrap a Kubernetes cluster using `kubeadm`. The core components of this infrastructure include:

- **Amazon EC2 Instances**: For both control plane and worker nodes.
- **Amazon VPC**: A custom Virtual Private Cloud to host the EC2 instances with proper subnet, route table, internet gateway, and security group configurations.
- **Security Groups**: Defined to allow necessary traffic between control plane and worker nodes.
- **SSM Parameter Store**: Used for securely storing the Kubernetes join command for worker nodes.
- **AWS Systems Manager (SSM)**: Used to securely connect to EC2 instances without SSH.
- **Kubernetes Cluster**: Bootstrapped on EC2 instances using `kubeadm`.

The infrastructure uses AWS services with Terraform to automate provisioning. This includes configuration and installation scripts that handle the setup of the Kubernetes control plane and worker nodes.

---

#### Prerequisites

Before running the project, ensure the following:

1. **AWS Account**: You need an active AWS account with programmatic access.
2. **AWS CLI**: AWS CLI must be installed and configured with appropriate credentials.
3. **Terraform CLI**: Terraform should be installed locally.
4. **IAM Role**: Ensure the EC2 instances have an IAM role with appropriate permissions to use SSM.

---

#### Project Structure

- **`main.tf`**: Defines the core resources such as EC2 instances, security groups, and networking.
- **`variables.tf`**: Contains variable definitions to customize infrastructure parameters.
- **`output.tf`**: Outputs important values such as instance IDs and Kubernetes join command.
- **`control-plane-install-dependencies.sh`**: Installs necessary dependencies for the control plane.
- **`control-plane-configure.sh`**: Configures the control plane node.
- **`worker-node-install-dependencies.sh`**: Installs necessary dependencies for worker nodes.
- **`worker-node-configure.sh`**: Configures worker nodes to join the cluster.
- **`control-plane-cloud-init.yaml` and `worker-node-cloud-init.yaml`**: Cloud-init scripts for bootstrapping instances.

---

#### Important Notes

1. **CNI and Add-Ons Installation**:
   - The cloud-init functionality provided in this project **only bootstraps the Kubernetes cluster**. It does not install the Container Network Interface (CNI) or any other add-ons required to run workloads in the cluster.
   - Installation of the CNI (e.g., Calico, Weave, etc.) and any other add-ons will be handled **via shell scripts** after the initial setup. This separation ensures **better practice** by keeping configuration management separate from the Infrastructure as Code (IaC) provisioning process.

2. **Node Configuration via SSM**:
   - There is a **possibility** that one of the nodes may not fully configure due to potential bootstrapping issues. However, these nodes are **SSM-accessible** (without the need for SSH), and the necessary configuration scripts are located under the `/root` directory on each node. You can connect to the node using SSM and manually run the configuration script if needed.

---

#### How to Run the Project

Follow these steps to provision the infrastructure and bootstrap the Kubernetes cluster:

1. **Clone the Repository**:
   - Clone the repository containing the Terraform code and necessary scripts to your local machine.

2. **Set Up AWS Credentials**:
   - Ensure you have your AWS credentials set up locally. You can configure this using the AWS CLI:

   ```bash
   aws configure
   ```

   This will prompt you to provide your AWS Access Key, Secret Access Key, region, and output format.

3. **Initialize Terraform**:
   - Initialize Terraform in the project directory to download provider plugins and set up the backend:

   ```bash
   terraform init
   ```

4. **Customize Variables**:
   - Review and update variables in `variables.tf` as needed for your environment, such as the EC2 instance type, key pair, and VPC details.

5. **Plan the Infrastructure**:
   - Run the Terraform `plan` command to preview the changes that will be applied to your AWS environment:

   ```bash
   terraform plan
   ```

6. **Apply the Configuration**:
   - Once satisfied with the plan, apply the Terraform configuration to create the infrastructure:

   ```bash
   terraform apply
   ```

   Confirm the action when prompted.

7. **Access Control Plane via SSM**:
   - Once the infrastructure is provisioned, you can connect to the control plane node using AWS Systems Manager (SSM) without needing to SSH into the instance. Ensure the instance is correctly tagged and has the required IAM permissions to use SSM.
   
   To connect to the control plane node using SSM, use the following AWS CLI command:

   ```bash
   aws ssm start-session --target <control-plane-instance-id>
   ```

   Replace `<control-plane-instance-id>` with the instance ID of the control plane, which can be retrieved from the Terraform output.

8. **Worker Node Configuration**:
   - The worker nodes will automatically retrieve the Kubernetes join command from the AWS SSM Parameter Store and join the cluster.

9. **Verify the Cluster**:
   - After the worker nodes have joined, you can verify the Kubernetes cluster from the control plane node via SSM:

   ```bash
   kubectl get nodes
   ```

---

By following these steps, you will have a functional Kubernetes cluster provisioned on AWS EC2 instances, with control over add-on installations and the ability to manage node configurations via SSM if needed.