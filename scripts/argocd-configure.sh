#!/bin/bash

# Exit immediately if a command exits with a non-zero status
set -e

# Set variables
REGION="us-east-1"
DOMAIN=$(aws route53 list-hosted-zones --query 'HostedZones[0].Name' --output text | sed 's/\.$//')
echo "Domain: $DOMAIN"

# Check if kubectl is installed
if ! command -v kubectl &> /dev/null; then
    echo "kubectl is not installed. Please install kubectl and try again."
    exit 1
fi

# Check if helm is installed
if ! command -v helm &> /dev/null; then
    echo "helm is not installed. Please install helm and try again."
    exit 1
fi

# Check if AWS CLI is installed
if ! command -v aws &> /dev/null; then
    echo "AWS CLI is not installed. Please install AWS CLI and configure it with appropriate credentials."
    exit 1
fi

# Verify AWS CLI is configured
if ! aws sts get-caller-identity &> /dev/null; then
    echo "AWS CLI is not configured properly. Please run 'aws configure' to set up your credentials."
    exit 1
fi

# Fetch the ARN of the existing certificate
CERT_ARN=$(aws acm list-certificates --region $REGION --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" --output text)
if [ -z "$CERT_ARN" ]; then
    echo "No certificate found for domain $DOMAIN. Please create a certificate in ACM and try again."
    exit 1
fi
echo "Using Certificate ARN: $CERT_ARN"

# Create values.yaml for the Helm chart
cat <<EOF > values.yaml
global:
  domain: argocd.${DOMAIN}
server:
  ingress:
    enabled: true
    ingressClassName: alb
    annotations:
      alb.ingress.kubernetes.io/scheme: internet-facing
      alb.ingress.kubernetes.io/target-type: instance
      alb.ingress.kubernetes.io/load-balancer-name: alb
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: "443"
      alb.ingress.kubernetes.io/group.name: shared-alb
      alb.ingress.kubernetes.io/group.order: "2"
      alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/healthcheck-path: /healthz
      alb.ingress.kubernetes.io/healthcheck-port: "30180"
      alb.ingress.kubernetes.io/healthcheck-interval-seconds: "10"
      alb.ingress.kubernetes.io/healthcheck-timeout-seconds: "5"
      alb.ingress.kubernetes.io/success-codes: "200-399"
      alb.ingress.kubernetes.io/healthy-threshold-count: "2"
      alb.ingress.kubernetes.io/unhealthy-threshold-count: "2"
    hostname: argocd.${DOMAIN}
    paths:
      - /
    pathType: Prefix
  extraArgs:
    - --insecure
  service:
    type: NodePort
    nodePortHttp: 30180
    nodePortHttps: 30443
    annotations:
      alb.ingress.kubernetes.io/target-type: instance
   
redis:
  enabled: true
applicationSet:
  enabled: true
configs:
  params:
    server.insecure: true
  cm:
    admin.enabled: 'true'
    exec.enabled: 'true'
    accounts.admin: 'apiKey, login'
    accounts.admin.enabled: 'true'
    accounts.admin.tokens.enabled: 'true'
    ui.config: |
      {
        "cluster.add": true,
        "token.create": true
      }
  rbac:
    create: true
    policy.csv: |
      p, role:admin, *, *, *, allow
notifications:
  enabled: true
EOF

# Install Helm chart
echo "Adding Argo Helm repository..."
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update

echo "Installing ArgoCD..."
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values values.yaml

# Wait for ArgoCD to be ready
echo "Waiting for ArgoCD pods to be ready..."
kubectl wait --for=condition=ready pod -l app.kubernetes.io/name=argocd-server -n argocd --timeout=300s

# Function to check if ALB DNS is available
check_alb_dns() {
  kubectl get ingress -n argocd -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null
}

# Wait for ALB DNS to be available (timeout after 10 minutes)
echo "Waiting for ALB DNS to be available..."
TIMEOUT=600
ELAPSED=0
while [ -z "$(check_alb_dns)" ] && [ $ELAPSED -lt $TIMEOUT ]; do
  sleep 10
  ELAPSED=$((ELAPSED+10))
  echo "Still waiting... (${ELAPSED}s elapsed)"
done

if [ $ELAPSED -ge $TIMEOUT ]; then
  echo "Timeout waiting for ALB DNS. Exiting."
  exit 1
fi

# Get the ALB DNS name
ALB_DNS=$(check_alb_dns)
echo "ALB DNS is available: $ALB_DNS"

# Create Route53 record
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name $DOMAIN --query 'HostedZones[0].Id' --output text)
echo "Creating Route53 record..."
aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch '{
        "Changes": [
            {
                "Action": "UPSERT",
                "ResourceRecordSet": {
                    "Name": "argocd.'$DOMAIN'",
                    "Type": "CNAME",
                    "TTL": 300,
                    "ResourceRecords": [{"Value": "'$ALB_DNS'"}]
                }
            }
        ]
    }'

echo "ArgoCD deployment completed successfully!"

# Fetch and display the initial admin password
ARGO_PASSWORD=$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath="{.data.password}" | base64 -d)
echo "ArgoCD initial admin password: $ARGO_PASSWORD"
echo "Please change this password after your first login."

# Display ArgoCD URL
echo "ArgoCD is now accessible at: https://argocd.${DOMAIN}"
echo "Setup complete. You can now log in to ArgoCD and start managing your applications."