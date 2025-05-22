# Enhanced main.tf based on your working version with monitoring

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

# Variables
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

variable "docker_image_tag" {
  description = "Docker image tag to deploy"
  type        = string
  default     = "latest"
}

variable "allowed_cidr" {
  description = "CIDR blocks allowed to SSH (22). 0.0.0.0/0 to disable SSH lockdown, but NOT recommended."
  type        = list(string)
  default     = ["0.0.0.0/0"]
}

# Data sources
data "aws_vpc" "default" {
  default = true
}

data "aws_subnets" "default" {
  filter {
    name   = "vpc-id"
    values = [data.aws_vpc.default.id]
  }
}

data "aws_ssm_parameter" "al2023_minimal" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-minimal-kernel-default-x86_64"
}

data "aws_ssm_parameter" "al2023_std" {
  name = "/aws/service/ami-amazon-linux-latest/al2023-ami-kernel-default-x86_64"
}

# Random suffix for unique naming
resource "random_pet" "suffix" {}

# SSH Key Pair
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated" {
  key_name   = "tf-generated-${random_pet.suffix.id}"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/tf-ec2.pem"
  file_permission = "0600"
}

# Security Group for Web Application
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

  # Flask app metrics (optional)
  ingress {
    description     = "Application metrics"
    from_port       = 5000
    to_port         = 5000
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
    Name = "docker-web-sg-${random_pet.suffix.id}"
  }
}

# Security Group for Monitoring
resource "aws_security_group" "monitor" {
  name        = "tf-monitor-sg-${random_pet.suffix.id}"
  description = "Allow Prometheus & Grafana UI"
  vpc_id      = data.aws_vpc.default.id

  # SSH
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr
  }

  # Grafana Web UI
  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Prometheus Web UI
  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  # Outbound rule
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }

  tags = {
    Name = "monitor-sg-${random_pet.suffix.id}"
  }
}

# Web Application Instance
resource "aws_instance" "web" {
  ami                         = data.aws_ssm_parameter.al2023_minimal.value
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.generated.key_name

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  user_data = <<-EOF
              #!/bin/bash
              set -euxo pipefail

              # Log everything for debugging
              exec > >(tee /var/log/user-data.log)
              exec 2>&1

              echo "=== Starting Web Instance User Data Script ==="
              echo "Docker image tag: ${var.docker_image_tag}"

              # Update system
              yum update -y
              dnf install -y docker git mysql

              # Start Docker
              systemctl enable --now docker

              # Install docker-compose
              curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose

              # Add ec2-user to docker group
              usermod -aG docker ec2-user

              # Clone repository
              cd /home/ec2-user
              if [ -d "app" ]; then
                  cd app
                  git pull origin main
                  cd ..
              else
                  git clone https://github.com/MuniebA/SWE40006-Group-2.git app
              fi

              cd app
              chown -R ec2-user:ec2-user /home/ec2-user/app

              # Create environment file
              cat > .env << ENVEOF
              FLASK_APP=run.py
              FLASK_ENV=production
              SECRET_KEY=production-secret-key-change-this
              DATABASE_URL=mysql+pymysql://root:rootpassword@db:3306/testdb
              ENVEOF

              # Update docker-compose.yml to use specific image tag if not latest
              if [ "${var.docker_image_tag}" != "latest" ]; then
                  sed -i "s|munieb/student-registration:latest|munieb/student-registration:${var.docker_image_tag}|g" docker-compose.yml
              fi

              # Pull the latest images
              docker-compose pull

              # Start containers
              docker-compose up -d

              # Wait for database to be ready
              echo "Waiting for database to be ready..."
              sleep 30

              # Initialize database and run migrations
              echo "Initializing database..."
              docker-compose exec -T web python -c "
              from app import create_app, db
              app = create_app('production')
              with app.app_context():
                  db.create_all()
                  print('Database initialized successfully')
              " || echo "Database initialization failed"

              # Run database migrations if they exist
              echo "Running database migrations..."
              docker-compose exec -T web flask db upgrade || echo "No migrations to run"

              # Start Node Exporter for monitoring
              echo "Starting Node Exporter for monitoring..."
              docker run -d \
                --name=node-exporter \
                --restart=always \
                --net=host \
                --pid=host \
                -v /:/host:ro,rslave \
                quay.io/prometheus/node-exporter:latest \
                --path.rootfs=/host

              # Create health check script
              cat > /home/ec2-user/health_check.sh << 'HEALTH_EOF'
              #!/bin/bash
              echo "=== Application Health Check ==="
              echo "Timestamp: $(date)"

              # Check if containers are running
              echo "Docker containers status:"
              docker-compose ps

              # Check application response
              echo "Testing application response:"
              if curl -f -s http://localhost/ > /dev/null; then
                  echo "✅ Web application is responding"
              else
                  echo "❌ Web application is not responding"
                  echo "Container logs:"
                  docker-compose logs --tail=20
              fi
              HEALTH_EOF

              chmod +x /home/ec2-user/health_check.sh
              chown ec2-user:ec2-user /home/ec2-user/health_check.sh

              # Run initial health check
              sleep 10
              /home/ec2-user/health_check.sh

              echo "=== Web Instance User Data Script Completed ==="
        EOF

  tags = {
    Name        = "tf-docker-web-${var.docker_image_tag}"
    Environment = "production"
    ImageTag    = var.docker_image_tag
    Role        = "web-application"
  }
}

# Monitoring Instance (Using your working approach)
resource "aws_instance" "monitor" {
  ami                         = data.aws_ssm_parameter.al2023_std.value
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.monitor.id]
  associate_public_ip_address = true
  key_name                    = aws_key_pair.generated.key_name

  root_block_device {
    volume_size = 10
    volume_type = "gp3"
  }

  tags = { 
    Name = "tf-monitor-${random_pet.suffix.id}", 
    Environment = "production",
    Role = "monitoring"
  }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    
    # Log everything for debugging
    exec > >(tee /var/log/user-data-monitor.log)
    exec 2>&1
    
    echo "=== Starting Monitoring Instance User Data Script ==="
    
    dnf update -y
    dnf install -y docker git curl

    # Start Docker
    systemctl enable --now docker

    # Install Docker Compose
    curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
    chmod +x /usr/local/bin/docker-compose

    # Create monitoring stack directory
    mkdir -p /opt/prom-stack/provisioning/{datasources,dashboards}
    mkdir -p /var/lib/grafana/dashboards
    
    # Create Prometheus configuration with web instance target
    cat > /opt/prom-stack/prometheus.yml <<PROM
    global:
      scrape_interval: 15s
      evaluation_interval: 15s
    scrape_configs:
      # Node Exporter from web instance
      - job_name: node_exporter_web
        static_configs:
          - targets: ['${aws_instance.web.private_ip}:9100']
        scrape_interval: 15s
        metrics_path: /metrics
      
      # Flask application metrics (if available)
      - job_name: flask_app
        static_configs:
          - targets: ['${aws_instance.web.private_ip}:5000']
        scrape_interval: 30s
        metrics_path: /metrics
        scrape_timeout: 10s
      
      # Self-monitoring
      - job_name: prometheus
        static_configs:
          - targets: ['localhost:9090']
      
      # Monitor the monitoring instance itself
      - job_name: monitoring_node
        static_configs:
          - targets: ['localhost:9100']
    PROM

    # Create Docker Compose file
    cat > /opt/prom-stack/docker-compose.yml <<'COMPOSE'
    version: "3.8"
    services:
      prometheus:
        image: prom/prometheus:latest
        container_name: prometheus
        volumes:
          - ./prometheus.yml:/etc/prometheus/prometheus.yml:ro
          - prometheus-data:/prometheus
        command:
          - "--config.file=/etc/prometheus/prometheus.yml"
          - "--storage.tsdb.path=/prometheus"
          - "--web.console.libraries=/etc/prometheus/console_libraries"
          - "--web.console.templates=/etc/prometheus/consoles"
          - "--storage.tsdb.retention.time=200h"
          - "--web.enable-lifecycle"
        ports:
          - "9090:9090"
        restart: unless-stopped

      grafana:
        image: grafana/grafana:latest
        container_name: grafana
        ports:
          - "3000:3000"
        environment:
          - GF_SECURITY_ADMIN_PASSWORD=admin
          - GF_USERS_ALLOW_SIGN_UP=false
          - GF_SECURITY_ADMIN_USER=admin
        volumes:
          - grafana-data:/var/lib/grafana
          - ./provisioning:/etc/grafana/provisioning
        restart: unless-stopped

      node-exporter:
        image: quay.io/prometheus/node-exporter:latest
        container_name: node-exporter-monitoring
        ports:
          - "9100:9100"
        volumes:
          - /proc:/host/proc:ro
          - /sys:/host/sys:ro
          - /:/rootfs:ro
        command:
          - '--path.procfs=/host/proc'
          - '--path.rootfs=/rootfs'
          - '--path.sysfs=/host/sys'
          - '--collector.filesystem.mount-points-exclude=^/(sys|proc|dev|host|etc)($$|/)'
        restart: unless-stopped

    volumes:
      prometheus-data:
      grafana-data:
    COMPOSE

    # Create Grafana provisioning
    cat > /opt/prom-stack/provisioning/datasources/ds.yml <<'DS'
    apiVersion: 1
    datasources:
      - name: Prometheus
        type: prometheus
        access: proxy
        url: http://prometheus:9090
        isDefault: true
        jsonData:
          timeInterval: 5s
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
    
    # Download Node Exporter dashboard
    curl -sL https://grafana.com/api/dashboards/1860/revisions/32/download -o /var/lib/grafana/dashboards/node-exporter-full.json
    
    # Set proper permissions
    chown -R ec2-user:ec2-user /opt/prom-stack

    # Start the monitoring stack
    cd /opt/prom-stack
    docker-compose up -d
    
    # Wait for services to start
    sleep 30
    
    echo "=== Monitoring Instance Setup Complete ==="
  EOF
}

# Create SSH config file for easy access
resource "local_file" "ssh_config" {
  content = <<-EOT
# SSH Configuration for AWS Instances
# Usage: ssh -F ssh_config web OR ssh -F ssh_config monitor

Host web
    HostName ${aws_instance.web.public_ip}
    User ec2-user
    IdentityFile ${path.module}/tf-ec2.pem
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null

Host monitor
    HostName ${aws_instance.monitor.public_ip}
    User ec2-user
    IdentityFile ${path.module}/tf-ec2.pem
    StrictHostKeyChecking no
    UserKnownHostsFile /dev/null
  EOT
  filename = "${path.module}/ssh_config"
  file_permission = "0600"
}

# Outputs
output "ec2_public_ip" {
  value       = aws_instance.web.public_ip
  description = "Public IPv4 address of the web instance"
}

output "instance_ip" {
  value       = aws_instance.web.public_ip
  description = "Public IP for compatibility"
}

output "ec2_public_dns" {
  value       = aws_instance.web.public_dns
  description = "Public DNS name of web instance"
}

output "website_url" {
  value       = "http://${aws_instance.web.public_ip}/"
  description = "Website URL"
}

output "grafana_url" {
  description = "Grafana Dashboard URL (login: admin/admin)"
  value       = "http://${aws_instance.monitor.public_ip}:3000"
}

output "prometheus_url" {
  description = "Prometheus Web UI URL"
  value       = "http://${aws_instance.monitor.public_ip}:9090"
}

output "monitoring_instance_ip" {
  value       = aws_instance.monitor.public_ip
  description = "Public IP of monitoring instance"
}

output "ssh_connection_info" {
  description = "SSH connection information"
  value = {
    web_instance = "ssh -i tf-ec2.pem ec2-user@${aws_instance.web.public_ip}"
    monitor_instance = "ssh -i tf-ec2.pem ec2-user@${aws_instance.monitor.public_ip}"
    private_key_location = "${path.module}/tf-ec2.pem"
  }
  sensitive = false
}

output "deployment_summary" {
  description = "Complete deployment information"
  value = {
    web_application = "http://${aws_instance.web.public_ip}/"
    grafana_dashboard = "http://${aws_instance.monitor.public_ip}:3000"
    prometheus_metrics = "http://${aws_instance.monitor.public_ip}:9090"
    ssh_key_file = "${path.module}/tf-ec2.pem"
  }
}