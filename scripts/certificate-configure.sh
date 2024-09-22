#!/bin/bash

# Set variables
REGION="us-east-1"
DOMAIN=$(aws route53 list-hosted-zones --query 'HostedZones[0].Name' --output text | sed 's/\.$//')
echo "Domain: $DOMAIN"./

# Step 1: Create ACM Certificate
echo "Creating ACM Certificate..."
CERT_ARN=$(aws acm request-certificate \
    --domain-name $DOMAIN \
    --subject-alternative-names "bird-service.$DOMAIN" "argocd.$DOMAIN" grafana.$DOMAIN \
    --validation-method DNS \
    --idempotency-token 1234 \
    --region $REGION \
    --output text \
    --query 'CertificateArn')

echo "Certificate ARN: $CERT_ARN"

# Add a delay to allow the certificate to propagate
echo "Waiting for 30 seconds to allow the certificate to propagate..."
sleep 30

# Step 2: Validate the Certificate
echo "Validating Certificate..."

describe_certificate() {
    aws acm describe-certificate --certificate-arn $CERT_ARN --region $REGION --query 'Certificate.DomainValidationOptions[].ResourceRecord' --output json
}

validate_certificate() {
    aws acm describe-certificate --certificate-arn $CERT_ARN --region $REGION --query 'Certificate.Status' --output text
}

create_route53_records() {
    local max_attempts=5
    local attempt=1
    local records=""
    
    while [ $attempt -le $max_attempts ]; do
        records=$(describe_certificate)
        echo "Debug: ACM describe-certificate output (attempt $attempt):"
        echo "$records"
        
        if [ "$records" != "[]" ]; then
            break
        fi
        
        echo "Certificate details not available yet. Waiting 30 seconds before retry..."
        sleep 30
        ((attempt++))
    done
    
    if [ "$records" == "[]" ]; then
        echo "Error: Unable to retrieve certificate details after $max_attempts attempts."
        exit 1
    fi
    
    echo $records | jq -c '.[]' | while read -r record; do
        name=$(echo $record | jq -r '.Name')
        type=$(echo $record | jq -r '.Type')
        value=$(echo $record | jq -r '.Value')
        
        echo "Debug: Creating Route53 record - Name: $name, Type: $type, Value: $value"
        
        aws route53 change-resource-record-sets \
            --hosted-zone-id $(aws route53 list-hosted-zones-by-name --dns-name $DOMAIN --query 'HostedZones[0].Id' --output text) \
            --change-batch '{
                "Changes": [{
                    "Action": "UPSERT",
                    "ResourceRecordSet": {
                        "Name": "'"$name"'",
                        "Type": "'"$type"'",
                        "TTL": 300,
                        "ResourceRecords": [{"Value": "'"$value"'"}]
                    }
                }]
            }'
    done
}

create_route53_records

while [ "$(validate_certificate)" != "ISSUED" ]; do
    echo "Certificate status: $(validate_certificate). Waiting 30 seconds..."
    sleep 30
done

echo "Certificate validated successfully!"