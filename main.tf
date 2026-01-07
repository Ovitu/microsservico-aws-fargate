# 1. PROVIDER - Configuração da AWS
terraform {
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = "us-east-1" # Região definida no seu onboarding
}

# 2. VPC - Rede isolada
resource "aws_vpc" "desafio_vpc" {
  cidr_block = "10.0.0.0/16"
  tags       = { Name = "desafioo-vpc" }
}

# 3. SUBNETS - Alta Disponibilidade (Multi-AZ)
resource "aws_subnet" "public_sub" {
  vpc_id                  = aws_vpc.desafio_vpc.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "us-east-1a"
  map_public_ip_on_launch = true
  tags = { Name = "public-subnet-fargate" }
}

resource "aws_subnet" "private_sub" {
  vpc_id            = aws_vpc.desafio_vpc.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "us-east-1b"
  tags = { Name = "private-subnet-rds" }
}

# 4. GATEWAY E ROTAS - Acesso à Internet
resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.desafio_vpc.id
}

resource "aws_route_table" "public_rt" {
  vpc_id = aws_vpc.desafio_vpc.id
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = aws_internet_gateway.igw.id
  }
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public_sub.id
  route_table_id = aws_route_table.public_rt.id
}

# 5. SECURITY GROUPS - Firewalls
resource "aws_security_group" "alb_sg" {
  name   = "alb-sg"
  vpc_id = aws_vpc.desafio_vpc.id

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # Acesso público ao Load Balancer
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_security_group" "rds_security" {
  name   = "rds-sg"
  vpc_id = aws_vpc.desafio_vpc.id

  ingress {
    from_port   = 5432
    to_port     = 5432
    protocol    = "tcp"
    cidr_blocks = ["10.0.0.0/16"] # Apenas tráfego interno da VPC
  }
}

# 6. BANCO DE DADOS RDS (PostgreSQL)
resource "aws_db_subnet_group" "rds_sg_group" {
  name       = "rds-subnet-group"
  subnet_ids = [aws_subnet.private_sub.id, aws_subnet.public_sub.id]
}

resource "aws_db_instance" "postgres_db" {
  allocated_storage      = 20
  db_name                = "meubanco"
  engine                 = "postgres"
  engine_version         = "15"
  instance_class         = "db.t3.micro"
  username               = "postgres"
  password               = "SenhaSegura123" # Importante: remover antes de commit real
  db_subnet_group_name   = aws_db_subnet_group.rds_sg_group.name
  vpc_security_group_ids = [aws_security_group.rds_security.id]
  skip_final_snapshot    = true
  publicly_accessible    = false
}

# 7. LOAD BALANCER (ALB)
resource "aws_lb" "meu_alb" {
  name               = "alb-fargate-desafio"
  internal           = false
  load_balancer_type = "application"
  security_groups    = [aws_security_group.alb_sg.id]
  subnets            = [aws_subnet.public_sub.id, aws_subnet.private_sub.id]
}

resource "aws_lb_target_group" "ecs_tg" {
  name        = "ecs-target-group"
  port        = 80
  protocol    = "HTTP"
  vpc_id      = aws_vpc.desafio_vpc.id
  target_type = "ip"
}

resource "aws_lb_listener" "front_end" {
  load_balancer_arn = aws_lb.meu_alb.arn
  port              = "80"
  protocol          = "HTTP"

  default_action {
    type             = "forward"
    target_group_arn = aws_lb_target_group.ecs_tg.arn
  }
}

# 8. ECS CLUSTER & REPOSITÓRIO ECR
resource "aws_ecr_repository" "meu_app_repo" {
  name = "repositorio-desafio"
}

resource "aws_ecs_cluster" "meu_cluster" {
  name = "cluster-fargate-desafio"
}

