resource "aws_security_group" "postgres_database_sg" {
  name        = "postgres_database_sg"
  description = "Allow access by my Public IP Address and AWS Lambda"
}

resource "aws_vpc_security_group_ingress_rule" "my_public_ip" {
  security_group_id = aws_security_group.postgres_database_sg.id
  description       = "Access Postgres from my public IP"
  from_port         = 5432
  to_port           = 5432
  ip_protocol       = "tcp"
  cidr_ipv4         = "${var.my_public_ip}/32"
}

resource "aws_db_parameter_group" "postgres" {
  name        = "${var.postgres_database}-database"
  family      = "postgres15"
  description = "Postgres Database Replication Parameter Group"

  # AWS DMS config
  parameter {
    name         = "log_min_duration_statement"
    value        = "10000"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "log_statement"
    value        = "ddl"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "rds.logical_replication"
    value        = "1"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "wal_sender_timeout"
    value        = "0"
    apply_method = "pending-reboot"
  }

  parameter {
    name         = "rds.force_ssl"
    value        = "0"
    apply_method = "pending-reboot"
  }
}

resource "aws_db_instance" "rds_postgres" {
  allocated_storage       = 20
  db_name                 = var.postgres_database
  identifier              = var.postgres_database
  multi_az                = false
  engine                  = "postgres"
  engine_version          = "15.3"
  parameter_group_name    = aws_db_parameter_group.postgres.id
  instance_class          = "db.t3.micro"
  username                = var.postgres_root_user
  password                = var.postgres_root_password
  storage_type            = "gp2"
  backup_retention_period = 0
  publicly_accessible     = true 
  skip_final_snapshot    = true
  vpc_security_group_ids = [aws_security_group.postgres_database_sg.id]
}

resource "null_resource" "postgres_database_setup" {
  depends_on = [aws_db_instance.rds_postgres]
  provisioner "local-exec" {
    command = "psql -h ${aws_db_instance.rds_postgres.address} -p ${aws_db_instance.rds_postgres.port} -U ${var.postgres_root_user} -d ${var.postgres_database} -f ./../src/transactional_database/prepare_database/terraform_prepare_database.sql -v user=${var.postgres_first_user} -v password='${var.postgres_first_user_password}'"
    environment = {
      PGPASSWORD = var.postgres_root_password
    }
  }
}

resource "null_resource" "postgres_replication_setup" {
  provisioner "local-exec" {
    command = "psql -h ${aws_db_instance.rds_postgres.address} -p ${aws_db_instance.rds_postgres.port} -U ${var.postgres_root_user} -d ${var.postgres_database} -f ./modules/rds/postgres/configure_replication.sql -v user=${var.postgres_first_user} -v password='${var.postgres_first_user_password}'"
    environment = {
      PGPASSWORD = var.postgres_root_password
    }
  }
}