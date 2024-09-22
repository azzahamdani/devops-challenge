# scripts/configure-worker.sh
#!/bin/bash
set -e

echo "Starting worker node configuration..."

# Function to retrieve join command from SSM with retries
get_join_command() {
    local retries=10
    local wait_time=30
    local counter=0
    while [ $counter -lt $retries ]; do
        REGION=$(curl -s http://169.254.169.254/latest/meta-data/placement/region)
        JOIN_COMMAND=$(aws ssm get-parameter --name "/k8s/worker-join-command" --with-decryption --query "Parameter.Value" --output text --region $REGION 2>/dev/null)
        if [ $? -eq 0 ] && [ ! -z "$JOIN_COMMAND" ]; then
            echo "Successfully retrieved join command"
            return 0
        fi
        echo "Failed to retrieve join command. Retrying in $wait_time seconds... (Attempt $((counter+1)) of $retries)"
        sleep $wait_time
        ((counter++))
    done
    echo "Failed to retrieve join command after $retries attempts"
    return 1
}

# Retrieve and execute join command
echo "Retrieving join command from SSM..."
if get_join_command; then
    echo "Joining the Kubernetes cluster..."
    $JOIN_COMMAND
else
    echo "Failed to join the cluster. Unable to retrieve join command."
    exit 1
fi

echo "Worker node configuration completed."