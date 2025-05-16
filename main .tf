# Required versions & provider
terraform {
  required_version = ">= 1.12.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "6.0.0-beta1"
    }
    tls = {
        source = "hashicorp/tls"
        version = ">= 3.0.0"
    }
    local = {
        source = "hashicorp/local"
        version = ">= 2.0.0"
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
  name   = "tf-web-sg"
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


resource "aws_key_pair" "generated" {
  key_name   = "tf-generated-key"
  public_key = tls_private_key.ssh.public_key_openssh
}

resource "local_file" "private_key" {
  content         = tls_private_key.ssh.private_key_pem
  filename        = "${path.module}/tf-ec2.pem"
  file_permission = "0600"
}



resource "aws_instance" "web" {
  ami                         = data.aws_ami.al2023.id
  instance_type               = var.instance_type
  subnet_id                   = data.aws_subnets.default.ids[0]
  vpc_security_group_ids      = [aws_security_group.web.id]
  associate_public_ip_address = true

  key_name = aws_key_pair.generated.key_name

  root_block_device {
    volume_size = 4
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
        EOF




  tags = {
    Name = "tf-docker-web"
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
