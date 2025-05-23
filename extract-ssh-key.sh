#!/bin/bash
# Run this after Terraform creates your EC2 instance
# Execute in the directory where you ran terraform apply

echo "🔐 Extracting SSH private key from Terraform..."

# Extract the private key from Terraform output
terraform output -raw private_key_content > ec2-private-key.pem

# Set proper permissions
chmod 600 ec2-private-key.pem

echo "📁 Private key saved as: ec2-private-key.pem"

# Copy to Jenkins SSH directory
echo "📋 Setting up SSH key for Jenkins..."

# Copy key to Jenkins
sudo cp ec2-private-key.pem /var/lib/jenkins/.ssh/ec2-key.pem
sudo chown jenkins:jenkins /var/lib/jenkins/.ssh/ec2-key.pem
sudo chmod 600 /var/lib/jenkins/.ssh/ec2-key.pem

# Get EC2 IP for verification
EC2_IP=$(terraform output -raw ec2_public_ip)

echo "✅ SSH key setup complete!"
echo "🌐 EC2 Instance IP: $EC2_IP"
echo "🔐 SSH Key location: /var/lib/jenkins/.ssh/ec2-key.pem"

# Test SSH connection (optional)
echo "🧪 Testing SSH connection..."
sudo -u jenkins ssh -i /var/lib/jenkins/.ssh/ec2-key.pem -o StrictHostKeyChecking=no ec2-user@$EC2_IP "echo 'SSH connection successful!'"

echo "🎉 Setup complete! Jenkins can now deploy to EC2."