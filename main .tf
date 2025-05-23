# Required versions & provider
terraform {
  required_version = ">= 1.12.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.0.0-beta1"
    }
    tls = {
      source  = "hashicorp/tls"
      version = ">= 3.0.0"
    }
    local = {
      source  = "hashicorp/local"
      version = ">= 2.0.0"
    }
    random = {
      source  = "hashicorp/random"
      version = ">=3.0.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "ap-southeast-1"
}

variable "instance_type" {
  description = "EC2 instance class"
  type        = string
  default     = "t3.micro"
}

variable "allowed_cidr" {
  description = "CIDR blocks allowed to SSH (22). 0.0.0.0/0 to disable SSH lockdown, but NOT recommended."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

resource "aws_security_group" "web" {
  name   = "tf-web-sg-${random_pet.suffix.id}"
  vpc_id = data.aws_vpc.default.id

  # HTTP 80
  ingress {
    description = "Allow HTTP"
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # HTTPS 443
  ingress {
    description = "Allow HTTPS"
    from_port   = 443
    to_port     = 443
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # SSH 22
  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr
  }

  # Node-exporter for monitoring
  ingress {
    description     = "Node-exporter"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.monitor.id]
  }

  # Default egress (all traffic out)
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "docker-web-sg"
  }
}

resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "random_pet" "suffix" {}

resource "aws_key_pair" "generated" {
  key_name   = "tf-generated-${random_pet.suffix.id}"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/tf-ec2.pem"
  file_permission = "0600"
}

data "aws_ssm_parameter" "al2023_minimal" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64"
}

resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023_minimal.value
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.generated.key_name

  root_block_device {
    volume_size = 12
    volume_type = "gp3"
  }

  # SIMPLIFIED USER_DATA - Based on your working version but updated
  user_data = <<-EOF
              #!/bin/bash
              set -euxo pipefail

              # Log everything for debugging
              exec > >(tee /var/log/user-data.log)
              exec 2>&1

              echo "=== Starting EC2 User Data Script ==="
              echo "Timestamp: $(date)"

              # Update system first
              echo "Updating system packages..."
              yum update -y

              # Install Docker and Git directly (Amazon Linux 2023 approach)
              echo "Installing Docker and Git..."
              dnf install -y docker git curl

              # Start and enable Docker
              echo "Starting Docker service..."
              systemctl enable docker
              systemctl start docker

              # Wait for Docker to be ready
              echo "Waiting for Docker to be ready..."
              for i in {1..30}; do
                if systemctl is-active --quiet docker && docker info >/dev/null 2>&1; then
                  echo "✅ Docker is ready!"
                  break
                fi
                echo "⏳ Waiting for Docker... attempt $i/30"
                sleep 5
              done

              # Add ec2-user to docker group
              usermod -aG docker ec2-user

              # Install docker-compose
              echo "Installing docker-compose..."
              curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose

              # Verify docker-compose installation
              /usr/local/bin/docker-compose --version

              # Clone your repository
              echo "Cloning repository..."
              cd /home/ec2-user
              git clone https://github.com/MuniebA/SWE40006-Group-2.git app
              cd app
              chown -R ec2-user:ec2-user /home/ec2-user/app

              # Pull the latest Docker image
              echo "Pulling latest Docker image..."
              docker pull munieb/student-registration:latest

              # Create production docker-compose configuration
              echo "Creating production docker-compose configuration..."
              cat > docker-compose.prod.yml << 'COMPOSE_EOF'
version: '3.8'

services:
  web:
    image: munieb/student-registration:latest
    ports:
      - "80:5000"
    environment:
      - FLASK_ENV=production
      - FLASK_CONFIG=production
      - DATABASE_URL=mysql+pymysql://testuser:testpass@db:3306/testdb
    depends_on:
      db:
        condition: service_healthy
    volumes:
      - .:/app
    networks:
      - app-network
    restart: always

  db:
    image: mysql:8.0
    environment:
      - MYSQL_ROOT_PASSWORD=rootpassword
      - MYSQL_DATABASE=testdb
      - MYSQL_USER=testuser
      - MYSQL_PASSWORD=testpass
    volumes:
      - mysql-data:/var/lib/mysql
      - ./init.sql:/docker-entrypoint-initdb.d/init.sql
    networks:
      - app-network
    restart: always
    healthcheck:
      test: ["CMD", "mysqladmin", "ping", "-h", "localhost", "-u", "testuser", "-ptestpass"]
      interval: 15s
      timeout: 10s
      retries: 10
      start_period: 60s

volumes:
  mysql-data:

networks:
  app-network:
    driver: bridge
COMPOSE_EOF

              # Start containers using production compose
              echo "Starting production containers..."
              docker-compose -f docker-compose.prod.yml up -d

              # Wait for services to be ready
              echo "Waiting for services to start..."
              sleep 60

              # Initialize database if needed
              echo "Checking database initialization..."
              docker-compose -f docker-compose.prod.yml exec -T web flask db upgrade 2>/dev/null || {
                echo "Database migration not available or failed"
              }

              # Start node-exporter for monitoring
              echo "Starting Node Exporter for monitoring..."
              docker run -d \
                --name=node-exporter \
                --restart=always \
                --net=host \
                --pid=host \
                -v "/:/host:ro,rslave" \
                quay.io/prometheus/node-exporter:latest \
                --path.rootfs=/host

              # Final health check
              echo "Performing final health check..."
              sleep 30
              if curl -f http://localhost/ >/dev/null 2>&1; then
                echo "✅ Application is running successfully!"
              else
                echo "⚠️ Application may not be ready yet"
                echo "Container status:"
                docker ps -a
                echo "Recent logs:"
                docker-compose -f docker-compose.prod.yml logs --tail=20
              fi

              # Create completion marker - IMPORTANT for Jenkins
              echo "Creating completion marker..."
              touch /var/log/user-data-complete

              echo "=== User Data Script Completed ==="
              echo "Timestamp: $(date)"
        EOF

  tags = {
    Name        = "tf-docker-web"
    Environment = "production"
    Project     = "student-registration-system"
  }
}

resource "aws_security_group" "monitor" {
  name        = "tf-monitor-sg-${random_pet.suffix.id}"
  description = "Allow Prometheus & Grafana UI"
  vpc_id      = data.aws_vpc.default.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Grafana
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus UI
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "monitor-sg"
  }
}

data "aws_ssm_parameter" "al2023_std" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

resource "aws_instance" "monitor" {
  ami                         = data.aws_ssm_parameter.al2023_std.value
  instance_type               = "t3.micro"
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.monitor.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.generated.key_name

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  tags = { 
    Name = "tf-monitor"
    Environment = "production"
    Project = "student-registration-system"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail

    # Log everything
    exec > >(tee /var/log/user-data-monitor.log)
    exec 2>&1

    echo "=== Starting Monitoring Instance User Data Script ==="

    # Update system
    dnf update -y

    # Install packages
    dnf install -y docker git curl

    # Start Docker
    systemctl enable --now docker

    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # Create monitoring stack directory
    mkdir -p /opt/prom-stack/provisioning/{datasources,dashboards}
    mkdir -p /var/lib/grafana/dashboards
    
    cat > /opt/prom-stack/prometheus.yml <<PROM
global:
  scrape_interval: 15s
scrape_configs:
  - job_name: node_exporter
    static_configs:
      - targets: ['${aws_instance.web.private_ip}:9100']
  - job_name: student_app
    static_configs:
      - targets: ['${aws_instance.web.private_ip}:80']
    metrics_path: /metrics
PROM

    cat > /opt/prom-stack/docker-compose.yml <<'COMPOSE'
version: "3.8"
services:
  prometheus:
    image: prom/prometheus:latest
    volumes:
      - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
    command:
      - "--config.file=/etc/prometheus/prometheus.yml"
      - "--storage.tsdb.path=/prometheus"
      - "--web.console.libraries=/etc/prometheus/console_libraries"
      - "--web.console.templates=/etc/prometheus/consoles"
      - "--storage.tsdb.retention.time=200h"
      - "--web.enable-lifecycle"
    ports:
      - "9090:9090"
    restart: always

  grafana:
    image: grafana/grafana:latest
    ports:
      - "3000:3000"
    environment:
      - GF_SECURITY_ADMIN_PASSWORD=admin
    volumes:
      - grafana-data:/var/lib/grafana
      - ./provisioning:/etc/grafana/provisioning
    restart: always

volumes:
  grafana-data:
COMPOSE

    cat > /opt/prom-stack/provisioning/datasources/ds.yml <<'DS'
apiVersion: 1
datasources:
  - name: Prometheus
    type: prometheus
    access: proxy
    url: http://prometheus:9090
    isDefault: true
DS

    cat > /opt/prom-stack/provisioning/dashboards/node.yml <<'DB'
apiVersion: 1
providers:
  - name: Default
    type: file
    updateIntervalSeconds: 30
    options:
      path: /var/lib/grafana/dashboards
DB
    
    # Download node exporter dashboard
    curl -sL https://grafana.com/api/dashboards/1860/revisions/32/download \
      -o /var/lib/grafana/dashboards/node-exporter-full.json || echo "Dashboard download failed"

    cd /opt/prom-stack
    docker-compose up -d

    echo "=== Monitoring Instance Setup Complete ==="
  EOF
}

# ============================================================================
# OUTPUTS - Essential for CI/CD Integration
# ============================================================================

output "ec2_public_ip" {
  value       = aws_instance.web.public_ip
  description = "Public IPv4 address of the EC2 instance"
}

output "ec2_public_dns" {
  value       = aws_instance.web.public_dns
  description = "Public DNS name of the EC2 instance"
}

output "ec2_instance_id" {
  value       = aws_instance.web.id
  description = "EC2 Instance ID"
}

output "ec2_private_ip" {
  value       = aws_instance.web.private_ip
  description = "Private IP address of the EC2 instance"
}

output "private_key_content" {
  value       = tls_private_key.ssh.private_key_pem
  sensitive   = true
  description = "Private key for SSH access to EC2 (sensitive)"
}

output "key_pair_name" {
  value       = aws_key_pair.generated.key_name
  description = "Name of the generated key pair"
}

output "grafana_url" {
  description = "Grafana dashboard URL (admin/admin)"
  value       = "http://${aws_instance.monitor.public_ip}:3000"
}

output "prometheus_url" {
  value       = "http://${aws_instance.monitor.public_ip}:9090"
  description = "Prometheus UI URL"
}

output "application_url" {
  value       = "http://${aws_instance.web.public_ip}/"
  description = "Student Registration System Application URL"
}

output "security_group_web_id" {
  value       = aws_security_group.web.id
  description = "Security group ID for the web server"
}

output "security_group_monitor_id" {
  value       = aws_security_group.monitor.id
  description = "Security group ID for the monitoring server"
}

# Summary output for easy reference
output "deployment_summary" {
  value = {
    application_url = "http://${aws_instance.web.public_ip}/"
    grafana_url     = "http://${aws_instance.monitor.public_ip}:3000"
    prometheus_url  = "http://${aws_instance.monitor.public_ip}:9090"
    ssh_command     = "ssh -i tf-ec2.pem ec2-user@${aws_instance.web.public_ip}"
    docker_image    = "munieb/student-registration:latest"
  }
  description = "Summary of all deployment URLs and access information"
}