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
  # Credentials are picked up automatically from one of:
  # • Environment vars: AWS_ACCESS_KEY_ID / AWS_SECRET_ACCESS_KEY (/ AWS_SESSION_TOKEN)
  # • AWS shared‑credentials file (~/.aws/credentials)
  # • IAM role if running in CI or on an EC2 instance with an instance‑profile
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


# Grab the latest Amazon Linux 2023 AMI (x86_64) in the chosen region.
data "aws_ami" "al2023" {
  most_recent = true
  owners      = ["amazon"]
  filter {
    name   = "name"
    values = ["al2023-ami-*-x86_64"]
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

  # SSH 22 (optional lockdown)
  ingress {
    description = "Allow SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = var.allowed_cidr
  }

  ingress {
  description = "Node-exporter"
  from_port   = 9100
  to_port     = 9100
  protocol    = "tcp"
  security_groups = [aws_security_group.monitor.id]  # safer than 0.0.0.0/0
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
    volume_size = 8 # Adjust as needed; must be >= minimal AMI's snapshot size
    volume_type = "gp3"
  }

  # Installs & starts Docker at first boot
  user_data = <<-EOF
              #!/bin/bash
              set -euxo pipefail

              yum update -y
              dnf install -y docker git
              systemctl enable --now docker

              # Install docker-compose
              curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
              chmod +x /usr/local/bin/docker-compose

              # Clone repo (only for the docker-copmose and init.sql)
              git clone https://github.com/RafidAlJawad1/test.git /home/ec2-user/app
              cd /home/ec2-user/app


              # Start containers
              docker-compose up -d

              # Wait and optionally initialize DB
              sleep 30
              docker-compose exec web flask init-db || true

              # ---- monitoring ----
              docker run -d \
                --name=node-exporter \
                --restart=always \
                --net=host \
                quay.io/prometheus/node-exporter:latest

        EOF




  tags = {
    Name        = "tf-docker-web"
    Environment = "demo"
  }
}


output "ec2_public_ip" {
  value       = aws_instance.web.public_ip
  description = "Public IPv4 address of the EC2 instance"
}

output "ec2_public_dns" {
  value       = aws_instance.web.public_dns
  description = "Public DNS name (useful for browser test)"
}


resource "aws_security_group" "monitor" {
  name        = "tf-monitor-sg-${random_pet.suffix.id}"
  description = "Allow Prometheus & Grafana UI"
  vpc_id      = data.aws_vpc.default.id

  # -------- Inbound rules --------
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # SSH
  }

  ingress {
    from_port   = 3000
    to_port     = 3000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Grafana
  }

  ingress {
    from_port   = 9090
    to_port     = 9090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Prometheus UI (optional)
  }

  # -------- Outbound rule --------
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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

  tags = { Name = "tf-monitor", Environment = "demo" }

  user_data = <<-EOF
    #!/bin/bash
    set -euxo pipefail
    dnf update -y
    dnf install -y docker git
    systemctl enable --now docker

    # Install Docker Compose v1 plugin (Amazon Linux 2023)
    # mkdir -p /usr/libexec/docker/cli-plugins
    sudo curl -L "https://github.com/docker/compose/releases/latest/download/docker-compose-$(uname -s)-$(uname -m)" \
    -o /usr/local/bin/docker-compose
    sudo chmod +x /usr/local/bin/docker-compose

    # --- Prometheus + Grafana stack ---
    mkdir -p /opt/prom-stack/provisioning/{datasources,dashboards}
    mkdir -p /var/lib/grafana/dashboards
    
    cat > /opt/prom-stack/prometheus.yml <<PROM
    global:
      scrape_interval: 15s
    scrape_configs:
      - job_name: node_exporter
        static_configs:
          - targets: ['${aws_instance.web.private_ip}:9100']
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
        ports:
          - "9090:9090"

      grafana:
        image: grafana/grafana:latest
        ports:
          - "3000:3000"
        environment:
          - GF_SECURITY_ADMIN_PASSWORD=admin #GF_SECURITY_ADMIN_PASSWORD=$${GRAFANA_ADMIN_PASSWORD:-ChangeMe!}
        volumes:
          - grafana-data:/var/lib/grafana
          - ./provisioning:/etc/grafana/provisioning

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

    
    curl -sL https://grafana.com/api/dashboards/1860/revisions/32/download \
      -o /var/lib/grafana/dashboards/node-exporter-full.json

    cd /opt/prom-stack
    sudo docker-compose up -d


    
  EOF
}

output "grafana_url" {
  description = "Login Grafana with admin / admin"
  value       = "http://${aws_instance.monitor.public_ip}:3000"
}

output "prometheus_url" {
  value = "http://${aws_instance.monitor.public_ip}:9090"
}
