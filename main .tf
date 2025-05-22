# Enhanced main.tf with Grafana & Prometheus monitoring infrastructure

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

# SSH Key Pair (shared between instances)
resource "tls_private_key" "ssh" {
  algorithm = "RSA"
  rsa_bits  = 4096
}

resource "aws_key_pair" "generated" {
  key_name   = "tf-generated-${random_pet.suffix.id}"
  public_key = tls_private_key.ssh.public_key_openssh
}

# Save SSH private key locally for access
resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/tf-ec2.pem"
  file_permission = "0600"
}

# Save SSH connection info for Jenkins
resource "local_file" "ssh_config" {
  content = templatefile("${path.module}/ssh_config.tpl", {
    web_ip = aws_instance.web.public_ip
    monitor_ip = aws_instance.monitor.public_ip
    key_file = "${path.module}/tf-ec2.pem"
    user = "ec2-user"
  })
  filename = "${path.module}/ssh_config"
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

  # Node Exporter for Prometheus monitoring
  ingress {
    description     = "Node-exporter"
    from_port       = 9100
    to_port         = 9100
    protocol        = "tcp"
    security_groups = [aws_security_group.monitor.id]  # Only allow from monitoring instance
  }

  # Flask app metrics endpoint (if implemented)
  ingress {
    description     = "Application metrics"
    from_port       = 8080
    to_port         = 8080
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

# Security Group for Monitoring Infrastructure
resource "aws_security_group" "monitor" {
  name        = "tf-monitor-sg-${random_pet.suffix.id}"
  description = "Allow Prometheus & Grafana UI"
  vpc_id      = data.aws_vpc.default.id

  # SSH access
  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr
  }

  # Grafana Web UI
  ingress {
    description = "Grafana Web UI"
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Public access to Grafana
  }

  # Prometheus Web UI (optional, can be restricted)
  ingress {
    description = "Prometheus Web UI"
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Public access to Prometheus
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

  user_data = templatefile("${path.module}/user_data_web.sh", {
    docker_image_tag = var.docker_image_tag
    monitor_ip = aws_instance.monitor.private_ip
  })

  tags = {
    Name        = "tf-docker-web-${var.docker_image_tag}"
    Environment = "production"
    ImageTag    = var.docker_image_tag
    Role        = "web-application"
  }
}

# Monitoring Instance (Prometheus + Grafana)
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

  user_data = templatefile("${path.module}/user_data_monitor.sh", {
    web_instance_ip = aws_instance.web.private_ip
  })

  tags = {
    Name        = "tf-monitor-${random_pet.suffix.id}"
    Environment = "production"
    Role        = "monitoring"
  }
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