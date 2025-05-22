#!/bin/bash
# Run this script in your Jenkins server (WSL2 Ubuntu)

echo "🔐 Setting up SSH access to EC2 from Jenkins..."

# Create SSH directory for jenkins user
sudo mkdir -p /var/lib/jenkins/.ssh
sudo chown jenkins:jenkins /var/lib/jenkins/.ssh
sudo chmod 700 /var/lib/jenkins/.ssh

# You need to get the EC2 private key from Terraform output
# This will be generated when Terraform creates the EC2 instance

echo "📋 Steps to complete SSH setup:"
echo "1. Run your Terraform to create EC2 instance"
echo "2. Copy the generated private key to Jenkins"
echo "3. Set proper permissions"

# Example commands after Terraform creates the key:
# sudo cp /path/to/terraform/tf-ec2.pem /var/lib/jenkins/.ssh/ec2-key.pem
# sudo chown jenkins:jenkins /var/lib/jenkins/.ssh/ec2-key.pem
# sudo chmod 600 /var/lib/jenkins/.ssh/ec2-key.pem

echo "✅ SSH directory prepared. You'll need to copy the EC2 private key here."