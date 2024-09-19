#!/bin/bash

set -ex

# Set variables
REGION="us-east-1"
DOMAIN=$(aws route53 list-hosted-zones --query 'HostedZones[0].Name' --output text | sed 's/\.$//')
echo "Domain: $DOMAIN"

# Fetch the ARN of the existing certificate
CERT_ARN=$(aws acm list-certificates --region $REGION --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" --output text)
echo "Using Certificate ARN: $CERT_ARN"

# Update values.yaml for the Helm chart
cat <<EOF > values.yaml
global:
  environment: bird-challenge

birdAPI:
  enabled: true
  replicaCount: 2
  image:
    repository: hediabed/bird-api
    tag: latest
    pullPolicy: IfNotPresent
  service:
    type: ClusterIP
    port: 4201
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

birdImageService:
  enabled: true
  replicaCount: 2
  image:
    repository: hediabed/bird-image-service
    tag: latest
    pullPolicy: IfNotPresent
  service:
    type: ClusterIP
    port: 4200
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

ingress:
  enabled: true
  className: alb
  annotations:
    kubernetes.io/ingress.class: alb
    alb.ingress.kubernetes.io/scheme: internet-facing
    alb.ingress.kubernetes.io/target-type: ip
    alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
    alb.ingress.kubernetes.io/ssl-redirect: "443"
    alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
    alb.ingress.kubernetes.io/group.name=shared-alb
  hosts:
    - host: bird-service.${DOMAIN}
      paths:
        - path: /api
          pathType: Prefix
          service: bird-api
        - path: /image
          pathType: Prefix
          service: bird-image-service
EOF

# Install Helm chart
helm repo add devops-challenge https://raw.githubusercontent.com/azzahamdani/devops-challenge/main/charts
helm repo update
kubectl create ns bird-app
helm upgrade --install app devops-challenge/bird-services -f values.yaml -n bird-app

echo "Waiting for ALB to be provisioned..."
sleep 60  # Wait for ALB to be provisioned

# Get the ALB DNS name
ALB_DNS=$(kubectl get ingress -l app.kubernetes.io/name=bird-services -n bird-app -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

# Create Route53 record
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name $DOMAIN --query 'HostedZones[0].Id' --output text)

aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch '{
        "Changes": [
            {
                "Action": "UPSERT",
                "ResourceRecordSet": {
                    "Name": "bird-service.'$DOMAIN'",
                    "Type": "CNAME",
                    "TTL": 300,
                    "ResourceRecords": [{"Value": "'$ALB_DNS'"}]
                }
            }
        ]
    }'

echo "Deployment completed successfully!"