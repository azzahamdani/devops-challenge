#!/bin/bash

set -ex

# Set the cluster name
CLUSTER_NAME=ex-terraform

# Get the AWS region
REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)

# Get the VPC ID
VPC_ID=$(curl -s http://169.254.169.254/latest/meta-data/network/interfaces/macs/$(curl -s http://169.254.169.254/latest/meta-data/mac)/vpc-id)

# Print the values (for verification)
echo "Cluster Name: $CLUSTER_NAME"
echo "AWS Region: $REGION"
echo "VPC ID: $VPC_ID"

kubectl create serviceaccount aws-load-balancer-controller -n kube-system

# Get the role ARN using sts get-caller-identity
FULL_ARN=$(aws sts get-caller-identity --query 'Arn' --output text)

# Extract the role name and account ID from the ARN
ROLE_NAME=$(echo $FULL_ARN | cut -d'/' -f2)
ACCOUNT_ID=$(echo $FULL_ARN | cut -d':' -f5)

# Construct the role ARN
ROLE_ARN="arn:aws:iam::${ACCOUNT_ID}:role/${ROLE_NAME}"

# Apply the annotation with the constructed role ARN
kubectl annotate serviceaccount -n kube-system aws-load-balancer-controller \
    eks.amazonaws.com/role-arn=$ROLE_ARN

echo "Annotation applied with ARN: $ROLE_ARN"

# Add the EKS chart repo to Helm
helm repo add eks https://aws.github.io/eks-charts
helm repo update

# Install the AWS Load Balancer Controller
helm install aws-load-balancer-controller eks/aws-load-balancer-controller \
  -n kube-system \
  --set clusterName=$CLUSTER_NAME \
  --set serviceAccount.create=false \
  --set serviceAccount.name=aws-load-balancer-controller \
  --set region=$REGION \
  --set vpcId=$VPC_ID \
  --set podDisruptionBudget.maxUnavailable=1 \
  --set enableServiceMutatorWebhook=true \
  --set enableEndpointSlices=true \
  --set controllerConfig.featureGates.SubnetsClusterTagCheck=false

# Check the status of the deployment
kubectl get deployment -n kube-system aws-load-balancer-controller

