#!/bin/bash
set -e

# Function to patch a node with its provider ID
patch_node() {
    local node_name=$1
    local provider_id=$2
    
    echo "Patching node ${node_name} with provider ID ${provider_id}"
    kubectl patch node ${node_name} -p "{\"spec\":{\"providerID\":\"${provider_id}\"}}"
}

# Function to get the EC2 instance ID from the node name
get_instance_id() {
    local node_name=$1
    # Assuming the node name is the private DNS name of the EC2 instance
    aws ec2 describe-instances --region "us-east-1" --filters "Name=private-dns-name,Values=${node_name}" --query "Reservations[].Instances[].InstanceId" --output text
}


    
    # Get all nodes
    NODES=$(kubectl get nodes -o json | jq -r '.items[] | select(.spec.providerID == null) | .metadata.name')
    
    for NODE_NAME in $NODES; do
        echo "Processing node: ${NODE_NAME}"
        
        # Get instance ID
        INSTANCE_ID=$(get_instance_id $NODE_NAME)
        
        if [ -z "$INSTANCE_ID" ]; then
            echo "Could not find EC2 instance for node ${NODE_NAME}. Skipping."
            continue
        fi
        
        # Get instance details
        INSTANCE_DETAILS=$(aws ec2 describe-instances --region "us-east-1" --instance-ids $INSTANCE_ID --query "Reservations[].Instances[]" --output json)
        
        # Extract availability zone
        AZ=$(echo $INSTANCE_DETAILS | jq -r '.[].Placement.AvailabilityZone')
        
        if [ -z "$AZ" ]; then
            echo "Could not determine availability zone for instance ${INSTANCE_ID}. Skipping."
            continue
        fi
        
        # Patch the node
        patch_node $NODE_NAME "aws://${AZ}/${INSTANCE_ID}"
    done
    
    echo "Finished checking nodes..."
