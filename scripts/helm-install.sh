#!/bin/bash

# Update the system
sudo yum update -y

# Install git
sudo yum install git -y

# Install Helm
curl -fsSL -o get_helm.sh https://raw.githubusercontent.com/helm/helm/master/scripts/get-helm-3
chmod 700 get_helm.sh
./get_helm.sh

# Add /usr/local/bin to PATH permanently
echo 'export PATH=$PATH:/usr/local/bin' >> ~/.bashrc
source ~/.bashrc

# Verify installations
git --version
helm version

echo "Installation complete. Please restart your shell or run 'source ~/.bashrc' to apply PATH changes."