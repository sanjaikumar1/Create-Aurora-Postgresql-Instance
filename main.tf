# --------------------------------------
# VPC and Networking
# --------------------------------------
resource "aws_vpc" "main" {
  cidr_block           = "10.0.0.0/16"
  enable_dns_support   = true
  enable_dns_hostnames = true
  tags = {
    Name = "demo-vpc"
  }
}

resource "aws_internet_gateway" "igw" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "demo-igw"
  }
}

resource "aws_subnet" "public" {
  vpc_id                  = aws_vpc.main.id
  cidr_block              = "10.0.1.0/24"
  availability_zone       = "${var.region}a"
  map_public_ip_on_launch = true
  tags = {
    Name = "public-subnet"
  }
}

resource "aws_subnet" "private_b" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.2.0/24"
  availability_zone = "${var.region}b"
  tags = {
    Name = "private-subnet-b"
  }
}

resource "aws_subnet" "private_c" {
  vpc_id            = aws_vpc.main.id
  cidr_block        = "10.0.3.0/24"
  availability_zone = "${var.region}c"
  tags = {
    Name = "private-subnet-c"
  }
}

resource "aws_eip" "nat_eip" {
  depends_on = [aws_internet_gateway.igw]
}

resource "aws_nat_gateway" "nat" {
  allocation_id = aws_eip.nat_eip.id
  subnet_id     = aws_subnet.public.id
  tags = {
    Name = "nat-gateway"
  }
}


resource "aws_route_table" "public" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "public-rt"
  }
}

resource "aws_route" "public_internet_access" {
  route_table_id         = aws_route_table.public.id
  destination_cidr_block = "0.0.0.0/0"
  gateway_id             = aws_internet_gateway.igw.id
}

resource "aws_route_table_association" "public_assoc" {
  subnet_id      = aws_subnet.public.id
  route_table_id = aws_route_table.public.id
}

resource "aws_route_table" "private" {
  vpc_id = aws_vpc.main.id
  tags = {
    Name = "private-rt"
  }
}


resource "aws_route" "private_nat_route" {
  route_table_id         = aws_route_table.private.id
  destination_cidr_block = "0.0.0.0/0"
  nat_gateway_id         = aws_nat_gateway.nat.id
}

resource "aws_route_table_association" "private_assoc_b" {
  subnet_id      = aws_subnet.private_b.id
  route_table_id = aws_route_table.private.id
}

resource "aws_route_table_association" "private_assoc_c" {
  subnet_id      = aws_subnet.private_c.id
  route_table_id = aws_route_table.private.id
}

# --------------------------------------
# Security Groups
# --------------------------------------
resource "aws_security_group" "bastion_sg" {
  name        = "bastion-sg"
  description = "Allow SSH from your IP"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = [var.my_ip]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "lambda_sg" {
  name        = "lambda-sg"
  description = "Allow outbound from Lambda to RDS"
  vpc_id      = aws_vpc.main.id

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}


resource "aws_security_group" "aurora_sg" {
  name        = "aurora-sg"
  description = "Allow PostgreSQL from Bastion"
  vpc_id      = aws_vpc.main.id

  ingress {
    from_port       = 5432
    to_port         = 5432
    protocol        = "tcp"
    security_groups = [aws_security_group.bastion_sg.id, aws_security_group.lambda_sg.id]
  }

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# --------------------------------------
# Bastion Host
# --------------------------------------
data "aws_ssm_parameter" "amzn2" {
  name = "/aws/service/ami-amazon-linux-latest/amzn2-ami-hvm-x86_64-gp2"
}

resource "aws_instance" "bastion" {
  ami                         = data.aws_ssm_parameter.amzn2.value
  instance_type              = "t2.micro"
  subnet_id                  = aws_subnet.public.id
  vpc_security_group_ids     = [aws_security_group.bastion_sg.id]
  key_name                   = var.key_name

  tags = {
    Name = "bastion-host"
  }
}

# --------------------------------------
# Aurora PostgreSQL Cluster
# --------------------------------------
resource "aws_db_subnet_group" "private_subnets" {
  name       = "aurora-private-subnet-group"
  subnet_ids = [aws_subnet.private_b.id, aws_subnet.private_c.id]
  tags = {
    Name = "aurora-private-subnet-group"
  }
}

resource "aws_rds_cluster" "pg_devdb" {
  cluster_identifier      = "pg-devdb"
  engine                  = "aurora-postgresql"
  engine_version          = "15.4"
  master_username         = var.db_user
  master_password         = var.db_password
  db_subnet_group_name    = aws_db_subnet_group.private_subnets.name
  vpc_security_group_ids  = [aws_security_group.aurora_sg.id]
  skip_final_snapshot     = true
  tags = {
    Name = "pg-devdb"
  }
}

resource "aws_rds_cluster_instance" "pg_devdb_instance" {
  identifier              = "pg-devdb-instance-1"
  cluster_identifier      = aws_rds_cluster.pg_devdb.id
  instance_class          = "db.t3.medium"
  engine                  = "aurora-postgresql"
  publicly_accessible     = false
  db_subnet_group_name    = aws_db_subnet_group.private_subnets.name
  tags = {
    Name = "pg-devdb-instance"
  }
}
