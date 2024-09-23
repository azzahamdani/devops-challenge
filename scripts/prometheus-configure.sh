#!/bin/bash

# Set variables
REGION="us-east-1"
DOMAIN=$(aws route53 list-hosted-zones --query 'HostedZones[0].Name' --output text | sed 's/\.$//')
echo "Domain: $DOMAIN"

# Fetch the ARN of the existing certificate
CERT_ARN=$(aws acm list-certificates --region $REGION --query "CertificateSummaryList[?DomainName=='$DOMAIN'].CertificateArn" --output text)
echo "Using Certificate ARN: $CERT_ARN"

# Update values.yaml for the Helm chart
cat <<EOF > values.yaml
## Using default values from https://github.com/grafana/helm-charts/blob/main/charts/grafana/values.yaml
##
grafana:
  enabled: true
  namespaceOverride: ""

  adminPassword: prom-operator

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
      alb.ingress.kubernetes.io/group.order: "1"
      alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
      alb.ingress.kubernetes.io/backend-protocol: HTTP
      alb.ingress.kubernetes.io/healthcheck-path: /login
      alb.ingress.kubernetes.io/healthcheck-port: "30080"
      alb.ingress.kubernetes.io/healthcheck-interval-seconds: "10"
      alb.ingress.kubernetes.io/healthcheck-timeout-seconds: "5"
      alb.ingress.kubernetes.io/success-codes: "200-399"
      alb.ingress.kubernetes.io/healthy-threshold-count: "2"
      alb.ingress.kubernetes.io/unhealthy-threshold-count: "2"
    hosts:
      - "grafana.${DOMAIN}"
    path: /
    pathType: Prefix

  serviceAccount:
    create: true
    autoMount: true

  service:
    type: NodePort
    port: 3000
    targetPort: 3000
    nodePort: 30080
    portName: http-web
    annotations:
      alb.ingress.kubernetes.io/target-type: instance

  # Ensure Grafana is accessible on /login for health checks
  grafana.ini:
    server:
      root_url: https://grafana.${DOMAIN}
    auth.anonymous:
      enabled: true
      org_role: Viewer
EOF

# Install Helm chart
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values values.yaml

# Function to check if ALB DNS is available
check_alb_dns() {
  kubectl get ingress -l app.kubernetes.io/name=grafana -n monitoring -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}' 2>/dev/null
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

aws route53 change-resource-record-sets \
    --hosted-zone-id $HOSTED_ZONE_ID \
    --change-batch '{
        "Changes": [
            {
                "Action": "UPSERT",
                "ResourceRecordSet": {
                    "Name": "grafana.'$DOMAIN'",
                    "Type": "CNAME",
                    "TTL": 300,
                    "ResourceRecords": [{"Value": "'$ALB_DNS'"}]
                }
            }
        ]
    }'

# Display Prometheus URL
echo "ArgoCD is now accessible at: https://grafana.${DOMAIN}"
echo "Deployment completed successfully!"