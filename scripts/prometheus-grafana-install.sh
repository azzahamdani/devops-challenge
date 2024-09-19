

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
      alb.ingress.kubernetes.io/target-type: ip
      alb.ingress.kubernetes.io/load-balancer-name: alb # Use the same ALB name
      alb.ingress.kubernetes.io/listen-ports: '[{"HTTPS":443}]'
      alb.ingress.kubernetes.io/ssl-redirect: "443"
      alb.ingress.kubernetes.io/group.name: shared-alb # Add this line
      alb.ingress.kubernetes.io/group.order: "2" # Add this line
      alb.ingress.kubernetes.io/certificate-arn: ${CERT_ARN}
    hosts:
      - "grafana.${DOMAIN}" # Replace ${DOMAIN} with your actual domain
    path: /
    pathType: Prefix

  serviceAccount:
    create: true
    autoMount: true

  service:
    portName: http-web
    ipFamilies: []
    ipFamilyPolicy: ""
EOF


# Install Helm chart
helm repo add prometheus-community https://prometheus-community.github.io/helm-charts
helm repo update

helm install prometheus prometheus-community/kube-prometheus-stack \
  --namespace monitoring \
  --create-namespace \
  --values values.yaml


# Get the ALB DNS name
ALB_DNS=$(kubectl get ingress -l app.kubernetes.io/name=grafana -n monitoring -o jsonpath='{.items[0].status.loadBalancer.ingress[0].hostname}')

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

echo "Deployment completed successfully!"