provider "aws" {
  region = "us-east-1"  # You can change this to your preferred region
}

# DynamoDB Tables
resource "aws_dynamodb_table" "cloudmart_products" {
  name           = "cloudmart-products"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  attribute {
    name = "id"
    type = "S"
  }
  
  tags = {
    Name        = "cloudmart-products"
    Environment = "Development"
    Project     = "CloudMart"
  }
}

resource "aws_dynamodb_table" "cloudmart_orders" {
  name           = "cloudmart-orders"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  attribute {
    name = "id"
    type = "S"
  }
  
  tags = {
    Name        = "cloudmart-orders"
    Environment = "Development"
    Project     = "CloudMart"
  }
}

resource "aws_dynamodb_table" "cloudmart_tickets" {
  name           = "cloudmart-tickets"
  billing_mode   = "PAY_PER_REQUEST"
  hash_key       = "id"
  attribute {
    name = "id"
    type = "S"
  }
  
  tags = {
    Name        = "cloudmart-tickets"
    Environment = "Development"
    Project     = "CloudMart"
  }
}

# Get the latest Amazon Linux 2 AMI (free tier eligible)
data "aws_ami" "amazon_linux_2" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
}

# Create a security group for the EC2 instance
resource "aws_security_group" "workstation_sg" {
  name        = "workstation3-sg"
  description = "Security group for workstation3 EC2 instance"

  # SSH access
  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]  # Note: For production, restrict to your IP
    description = "SSH access"
  }

  # Port 5000 access
  ingress {
    from_port   = 5000
    to_port     = 5000
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Port 5000 access"
  }

  # Port 5001 access
  ingress {
    from_port   = 5001
    to_port     = 5001
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Port 5001 access"
  }

  # Allow all outbound traffic
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
    description = "Allow all outbound traffic"
  }

  tags = {
    Name = "workstation3-sg"
  }
}

# Get existing IAM role
data "aws_iam_role" "ec2_admin_role" {
  name = "EC2Admin"
}

# Create an instance profile with the IAM role
resource "aws_iam_instance_profile" "ec2_admin_profile" {
  name = "workstation3-profile"
  role = data.aws_iam_role.ec2_admin_role.name
}

# User data script to set up the EC2 instance
locals {
  user_data = <<-EOF
    #!/bin/bash
    # Update system packages
    yum update -y
    
    # Install yum-utils
    sudo yum install -y yum-utils
    
    # Add HashiCorp repository
    sudo yum-config-manager --add-repo https://rpm.releases.hashicorp.com/AmazonLinux/hashicorp.repo
    
    # Install Terraform
    sudo yum -y install terraform
    terraform version
    
    # Install Git
    sudo yum install -y git
    git --version
    
    # Clone repository
    git clone https://github.com/jrmreis/cloudmart.git
    
    # Update system again
    sudo yum update -y
    
    # Install and configure Docker
    sudo yum install docker -y
    sudo systemctl start docker
    sudo systemctl enable docker
    sudo docker run hello-world
    
    # Add current user to docker group
    sudo usermod -a -G docker ec2-user
    
    # Create directory structure and download project files for backend
    mkdir -p /home/ec2-user/challenge-day2/backend
    cd /home/ec2-user/challenge-day2/backend
    wget https://tcb-public-events.s3.amazonaws.com/mdac/resources/day2/cloudmart-backend.zip
    unzip cloudmart-backend.zip
    
    # Create directory structure and download project files for frontend
    mkdir -p /home/ec2-user/challenge-day2/frontend
    cd /home/ec2-user/challenge-day2/frontend
    wget https://tcb-public-events.s3.amazonaws.com/mdac/resources/day2/cloudmart-frontend.zip
    unzip cloudmart-frontend.zip
    
    # Create .env file with environment variables
    cat > /home/ec2-user/challenge-day2/backend/.env << EOF2
PORT=5000
AWS_REGION=us-east-1
BEDROCK_AGENT_ID=<seu-bedrock-agent-id>
BEDROCK_AGENT_ALIAS_ID=<seu-bedrock-agent-alias-id>
OPENAI_API_KEY=<sua-chave-api-openai>
OPENAI_ASSISTANT_ID=<seu-id-assistente-openai>
EOF2
    
    # Set proper permissions for .env file
    chmod 600 /home/ec2-user/challenge-day2/backend/.env
    chown ec2-user:ec2-user /home/ec2-user/challenge-day2/backend/.env
    
    # Create Dockerfile for backend
    cat > /home/ec2-user/challenge-day2/backend/Dockerfile << EOF2
FROM node:18
WORKDIR /usr/src/app
COPY package*.json ./
RUN npm install
COPY . .
EXPOSE 5000
CMD ["npm", "start"]
EOF2
    
    # Set proper permissions for Dockerfile
    chmod 644 /home/ec2-user/challenge-day2/backend/Dockerfile
    chown ec2-user:ec2-user /home/ec2-user/challenge-day2/backend/Dockerfile
    
    # Get instance public IP
    EC2_PUBLIC_IP=$(curl -s http://169.254.169.254/latest/meta-data/public-ipv4)
    
    # Create frontend .env file with environment variables
    cat > /home/ec2-user/challenge-day2/frontend/.env << EOF2
VITE_API_BASE_URL=http://$EC2_PUBLIC_IP:5000/api
EOF2

    # Create frontend Dockerfile
    cat > /home/ec2-user/challenge-day2/frontend/Dockerfile << EOF2
FROM node:16-alpine as build
WORKDIR /app
COPY package*.json ./
RUN npm ci
COPY . .
RUN npm run build
FROM node:16-alpine
WORKDIR /app
RUN npm install -g serve
COPY --from=build /app/dist /app
ENV PORT=5001
ENV NODE_ENV=production
EXPOSE 5001
CMD ["serve", "-s", ".", "-l", "5001"]
EOF2

    # Set proper ownership
    chown -R ec2-user:ec2-user /home/ec2-user/challenge-day2
    chown -R ec2-user:ec2-user /home/ec2-user/cloudmart
    
    # Build and run backend Docker container
    cd /home/ec2-user/challenge-day2/backend
    docker build -t cloudmart-backend .
    docker run -d -p 5000:5000 --env-file .env cloudmart-backend
    
    # Build and run frontend Docker container
    cd /home/ec2-user/challenge-day2/frontend
    docker build -t cloudmart-frontend .
    docker run -d -p 5001:5001 cloudmart-frontend
    
    # Log Docker status
    echo "Setup completed at $(date)" > /home/ec2-user/setup-complete.log
    echo "Docker container status:" >> /home/ec2-user/setup-complete.log
    docker ps >> /home/ec2-user/setup-complete.log
  EOF
}

# Create the EC2 instance
resource "aws_instance" "workstation" {
  ami                    = data.aws_ami.amazon_linux_2.id
  instance_type          = "t2.micro"  # Free tier eligible
  iam_instance_profile   = aws_iam_instance_profile.ec2_admin_profile.name
  vpc_security_group_ids = [aws_security_group.workstation_sg.id]
  user_data              = local.user_data
  user_data_replace_on_change = true
  
  # You can add a key pair for SSH access
  # key_name = "your-key-pair-name"
  
  root_block_device {
    volume_size = 20  # Increased from 8 GB to ensure enough space for Docker and applications
    volume_type = "gp3"  # Using gp3 for better performance and still eligible for free tier
    encrypted   = true
  }
  
  tags = {
    Name        = "workstation3"
    Environment = "Development"
    Provisioner = "Terraform"
  }

  # Add a dependency to ensure the IAM role is available before the instance is created
  depends_on = [aws_iam_instance_profile.ec2_admin_profile]

  # Enable termination protection
  disable_api_termination = false  # Set to true in production to prevent accidental termination
  
  # Enable detailed monitoring (note: not free tier eligible)
  monitoring = false
}

# Elastic IP for fixed address
resource "aws_eip" "workstation_eip" {
  instance = aws_instance.workstation.id
  domain   = "vpc"
  
  tags = {
    Name = "workstation3-eip"
  }
}

# Output the public IP of the instance
output "public_ip" {
  value = aws_eip.workstation_eip.public_ip
}

# Output the public DNS of the instance
output "public_dns" {
  value = aws_instance.workstation.public_dns
}

# Output when setup is complete
output "setup_instructions" {
  value = "Connect via SSH using: ssh ec2-user@${aws_eip.workstation_eip.public_ip}. Setup will be completed when /home/ec2-user/setup-complete.log exists."
}
