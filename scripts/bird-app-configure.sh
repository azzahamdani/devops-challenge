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

# Verify kubectl is configured with the correct context
echo "Current Kubernetes context:"
kubectl config current-context


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
  environment: bird-challenge
  domain: ${DOMAIN}
birdAPI:
  enabled: true
  replicaCount: 2
  image:
    repository: zoeid/bird-api
    tag: latest
    pullPolicy: IfNotPresent
  service:
    annotations:
      alb.ingress.kubernetes.io/target-type: instance
    type: NodePort
    port: 4201
    nodePort: 30201
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 250m
      memory: 256Mi
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 80
  podDisruptionBudget:
    minAvailable: 1
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  networkPolicy:
    enabled: true
birdImageService:
  enabled: true
  replicaCount: 2
  image:
    repository: zoeid/bird-image-service
    tag: latest
    pullPolicy: IfNotPresent
  service:
    annotations:
      alb.ingress.kubernetes.io/target-type: instance
    type: NodePort
    port: 4200
    nodePort: 30200
  resources:
    limits:
      cpu: 500m
      memory: 512Mi
    requests:
      cpu: 250m
      memory: 256Mi
  autoscaling:
    enabled: true
    minReplicas: 2
    maxReplicas: 10
    targetCPUUtilizationPercentage: 80
  podDisruptionBudget:
    minAvailable: 1
  securityContext:
    runAsNonRoot: true
    runAsUser: 1000
  networkPolicy:
    enabled: true
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
    alb.ingress.kubernetes.io/group.order: "3"
    alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
    alb.ingress.kubernetes.io/backend-protocol: HTTP
    alb.ingress.kubernetes.io/healthcheck-path: /
    alb.ingress.kubernetes.io/healthcheck-port: "30201"
    alb.ingress.kubernetes.io/healthcheck-interval-seconds: "10"
    alb.ingress.kubernetes.io/healthcheck-timeout-seconds: "5"
    alb.ingress.kubernetes.io/success-codes: "200-399"
    alb.ingress.kubernetes.io/healthy-threshold-count: "2"
    alb.ingress.kubernetes.io/unhealthy-threshold-count: "2"
  hosts:
    - host: bird-services.${DOMAIN}
      paths:
        - path: /
          pathType: Prefix
          backend:
            service:
              name: bird-api
              port:
                number: 4201
EOF

# Create ArgoCD application manifest
cat <<EOF > bird-services-app.yaml
apiVersion: argoproj.io/v1alpha1
kind: Application
metadata:
  name: bird-services
  namespace: argocd
spec:
  project: default
  source:
    repoURL: https://github.com/azzahamdani/devops-challenge
    targetRevision: HEAD
    path: helm
    helm:
      values: |
$(cat values.yaml | sed 's/^/        /')
  destination:
    server: https://kubernetes.default.svc
    namespace: bird-services
  syncPolicy:
    automated:
      prune: true
      selfHeal: true
    syncOptions:
      - CreateNamespace=true
EOF

# Apply the ArgoCD application
echo "Applying ArgoCD application manifest..."
kubectl apply -f bird-services-app.yaml

echo "Bird Services application has been created in ArgoCD."
echo "ArgoCD will now manage the deployment of your application."
echo "You can check the status of your application in the ArgoCD UI or by running:"
echo "kubectl get applications -n argocd bird-services"
echo "Bird Services application has been created in ArgoCD."
echo "ArgoCD will now manage the deployment of your application."
echo "You can check the status of your application in the ArgoCD UI or by running:"
echo "kubectl get applications -n argocd bird-services"

# Function to check if ALB DNS is available
check_alb_dns() {
  kubectl get ingress -n bird-services -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null
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
                    "Name": "bird-services.'$DOMAIN'",
                    "Type": "CNAME",
                    "TTL": 300,
                    "ResourceRecords": [{"Value": "'$ALB_DNS'"}]
                }
            }
        ]
    }'

echo "Deployment process completed."
echo "You can access your application at: https://bird-services.${DOMAIN}/api and https://bird-services.${DOMAIN}/image"
echo "Bird Services deployment completed successfully!"