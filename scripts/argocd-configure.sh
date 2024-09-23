#!/bin/bash

# Set variables
REGION="us-east-1"
DOMAIN=$(aws route53 list-hosted-zones --query 'HostedZones[0].Name' --output text | sed 's/\.$//')
echo "Domain: $DOMAIN"

# Fetch the ARN of the existing certificate
CERT_ARN=$(aws acm list-certificates --region $REGION --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" --output text)
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
      alb.ingress.kubernetes.io/healthcheck-path: /login
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
helm repo add argo https://argoproj.github.io/argo-helm
helm repo update
helm install argocd argo/argo-cd \
  --namespace argocd \
  --create-namespace \
  --values values.yaml

# Get the ALB DNS name
ALB_DNS=$(kubectl get ingress -n argocd -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

# Create Route53 record
HOSTED_ZONE_ID=$(aws route53 list-hosted-zones-by-name --dns-name $DOMAIN --query 'HostedZones[0].Id' --output text)
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