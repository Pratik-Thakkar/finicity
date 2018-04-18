provider "aws" {
  region  = "${var.region}"
  profile = "${var.profile}"
}


# S3_Role

resource "iam_instance_profile" "s3_access_profile" {
  name = "s3_access"
  role = "${iam_role.s3_access_role.name}"
}

resource "iam_role_policy" "s3_access_policy" {
  name = "s3_access_policy"
  role = "${iam_role.s3_access_role.id}"

  policy = <<HEREDOC
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": "s3:*",
      "Resource": "*"
    }
  ]
}
HEREDOC
}

resource "iam_role" "s3_access_role" {
  name = "s3_access_role"

  assume_role_policy = <<HEREDOC
{
  "Version": "2012-10-17",
  "Statement": [
  {
      "Action": "sts:AssumeRole",
      "Principal": {
        "Service": "ec2.amazonaws.com"
  },
      "Effect": "Allow",
      "Sid": ""
      }
    ]
}
HEREDOC
}

# Creating VPC

resource "vpc" "vpc" {
  cidr_block           = "${var.vpc_cidr}"
  enable_dns_hostnames = true
  enable_dns_support   = true

  tags {
    Name = "vpc"
  }
}

# internet gateway

resource "internet_gateway" "internet_gateway" {
  vpc_id = "${vpc.vpc.id}"

  tags {
    Name = "igw"
  }
}

# Route tables

resource "route_table" "public_rt" {
  vpc_id = "${vpc.vpc.id}"

  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${internet_gateway.internet_gateway.id}"
  }

  tags {
    Name = "public"
  }
}

resource "default_route_table" "private_rt" {
  default_route_table_id = "${vpc.vpc.default_route_table_id}"

  tags {
    Name = "private"
  }
}

resource "subnet" "public1_subnet" {
  vpc_id                  = "${vpc.vpc.id}"
  cidr_block              = "${var.cidrs["public1"]}"
  map_public_ip_on_launch = true
  availability_zone       = "${data.availability_zones.available.names[0]}"

  tags {
    Name = "public1"
  }
}

resource "subnet" "public2_subnet" {
  vpc_id                  = "${vpc.vpc.id}"
  cidr_block              = "${var.cidrs["public2"]}"
  map_public_ip_on_launch = true
  availability_zone       = "${data.availability_zones.available.names[1]}"

  tags {
    Name = "public2"
  }
}

resource "subnet" "private1_subnet" {
  vpc_id                  = "${vpc.vpc.id}"
  cidr_block              = "${var.cidrs["private1"]}"
  map_public_ip_on_launch = false
  availability_zone       = "${data.availability_zones.available.names[0]}"

  tags {
    Name = "private1"
  }
}

resource "subnet" "private2_subnet" {
  vpc_id                  = "${vpc.vpc.id}"
  cidr_block              = "${var.cidrs["private2"]}"
  map_public_ip_on_launch = false
  availability_zone       = "${data.availability_zones.available.names[1]}"

  tags {
    Name = "private2"
  }
}

#create S3 VPC endpoint
resource "vpc_endpoint" "private-s3_endpoint" {
  vpc_id       = "${vpc.vpc.id}"
  service_name = "com.amazonaws.${var.region}.s3"

  route_table_ids = ["${vpc.vpc.main_route_table_id}",
    "${route_table.public_rt.id}",
  ]

  policy = <<POLICY
{
    "Statement": [
        {
            "Action": "*",
            "Effect": "Allow",
            "Resource": "*",
            "Principal": "*"
        }
    ]
}
POLICY
}

resource "subnet" "rds1_subnet" {
  vpc_id                  = "${vpc.vpc.id}"
  cidr_block              = "${var.cidrs["rds1"]}"
  map_public_ip_on_launch = false
  availability_zone       = "${data.availability_zones.available.names[0]}"

  tags {
    Name = "rds1"
  }
}

resource "subnet" "rds2_subnet" {
  vpc_id                  = "${vpc.vpc.id}"
  cidr_block              = "${var.cidrs["rds2"]}"
  map_public_ip_on_launch = false
  availability_zone       = "${data.availability_zones.available.names[1]}"

  tags {
    Name = "rds2"
  }
}

resource "subnet" "rds3_subnet" {
  vpc_id                  = "${vpc.vpc.id}"
  cidr_block              = "${var.cidrs["rds3"]}"
  map_public_ip_on_launch = false
  availability_zone       = "${data.availability_zones.available.names[2]}"

  tags {
    Name = "rds3"
  }
}

# Subnet Associations

resource "route_table_association" "public_assoc" {
  subnet_id      = "${subnet.public1_subnet.id}"
  route_table_id = "${route_table.public_rt.id}"
}

resource "route_table_association" "public2_assoc" {
  subnet_id      = "${subnet.public2_subnet.id}"
  route_table_id = "${route_table.public_rt.id}"
}

resource "route_table_association" "private1_assoc" {
  subnet_id      = "${subnet.private1_subnet.id}"
  route_table_id = "${default_route_table.private_rt.id}"
}

resource "route_table_association" "private2_assoc" {
  subnet_id      = "${subnet.private2_subnet.id}"
  route_table_id = "${default_route_table.private_rt.id}"
}

resource "db_subnet_group" "rds_subnetgroup" {
  name = "rds_subnetgroup"

  subnet_ids = ["${subnet.rds1_subnet.id}",
    "${subnet.rds2_subnet.id}",
    "${subnet.rds3_subnet.id}",
  ]

  tags {
    Name = "rds_sng"
  }
}

# Security groups

resource "security_group" "dev_sg" {
  name        = "dev_sg"
  description = "Used for access to the dev instance"
  vpc_id      = "${vpc.vpc.id}"

  #SSH

  ingress {
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["${var.localip}"]
  }

  #HTTP

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["${var.localip}"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Public Security group

resource "security_group" "public_sg" {
  name        = "public_sg"
  description = "Used for public and private instances for load balancer access"
  vpc_id      = "${vpc.vpc.id}"

  #HTTP 

  ingress {
    from_port   = 80
    to_port     = 80
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  #Outbound internet access

  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# Private Security Group

resource "security_group" "private_sg" {
  name        = "private_sg"
  description = "Used for private instances"
  vpc_id      = "${vpc.vpc.id}"

  # Access from other security groups

  ingress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["${var.vpc_cidr}"]
  }
  egress {
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

# RDS Security Group
resource "security_group" "rds_sg" {
  name        = "rds_sg"
  description = "Used for DB instances"
  vpc_id      = "${vpc.vpc.id}"

  # SQL access from public/private security group

  ingress {
    from_port = 3306
    to_port   = 3306
    protocol  = "tcp"

    security_groups = ["${security_group.dev_sg.id}",
      "${security_group.public_sg.id}",
      "${security_group.private_sg.id}",
    ]
  }
}

# S3 code bucket

resource "random_id" "code_bucket" {
  byte_length = 2
}

resource "s3_bucket" "code" {
  bucket        = "${var.domain_name}-${random_id.code_bucket.dec}"
  acl           = "private"
  force_destroy = true

  tags {
    Name = "code bucket"
  }
}

# Creat EC2

resource "db_instance" "db" {
  allocated_storage      = 10
  engine                 = "mysql"
  engine_version         = "5.6.27"
  instance_class         = "${var.db_instance_class}"
  name                   = "${var.dbname}"
  username               = "${var.dbuser}"
  password               = "${var.dbpassword}"
  db_subnet_group_name   = "${db_subnet_group.rds_subnetgroup.name}"
  vpc_security_group_ids = ["${security_group.rds_sg.id}"]
  skip_final_snapshot    = true
}

# key pair

resource "key_pair" "auth" {
  key_name   = "${var.key_name}"
  public_key = "${file(var.public_key_path)}"
}

# dev server

resource "instance" "dev" {
  instance_type = "${var.dev_instance_type}"
  ami           = "${var.dev_ami}"

  tags {
    Name = "dev"
  }

  key_name               = "${key_pair.auth.id}"
  vpc_security_group_ids = ["${security_group.dev_sg.id}"]
  iam_instance_profile   = "${iam_instance_profile.s3_access_profile.id}"
  subnet_id              = "${subnet.public1_subnet.id}"

  provisioner "local-exec" {
    command = <<EOD
cat <<HEREDOC > hosts 
[dev] 
${instance.dev.public_ip} 
[dev:vars] 
s3code=${s3_bucket.code.bucket}
domain=${var.domain_name} 
HEREDOC
EOD
  }

  provisioner "local-exec" {
    command = "aws ec2 wait instance-status-ok --instance-ids ${instance.dev.id} --profile cloud"
  }
}

# load balancer

resource "elb" "elb" {
  name = "${var.domain_name}-elb"

  subnets = ["${subnet.public1_subnet.id}",
    "${subnet.public2_subnet.id}",
  ]

  security_groups = ["${security_group.public_sg.id}"]

  listener {
    instance_port     = 80
    instance_protocol = "http"
    lb_port           = 80
    lb_protocol       = "http"
  }

  health_check {
    healthy_threshold   = "${var.elb_healthy_threshold}"
    unhealthy_threshold = "${var.elb_unhealthy_threshold}"
    timeout             = "${var.elb_timeout}"
    target              = "TCP:80"
    interval            = "${var.elb_interval}"
  }

  cross_zone_load_balancing   = true
  idle_timeout                = 400
  connection_draining         = true
  connection_draining_timeout = 400

  tags {
    Name = "${var.domain_name}-elb"
  }
}

# AMI 

resource "random_id" "golden_ami" {
  byte_length = 8
}

resource "ami_from_instance" "golden" {
  name               = "ami-${random_id.golden_ami.b64}"
  source_instance_id = "${instance.dev.id}"

  provisioner "local-exec" {
    command = <<EOT
cat <<HEREDOC > userdata
#!/bin/bash
/usr/bin/aws s3 sync s3://${s3_bucket.code.bucket} /var/www/html/
/bin/touch /var/spool/cron/root
sudo /bin/echo '*/5 * * * * aws s3 sync s3://${s3_bucket.code.bucket} /var/www/html/' >> /var/spool/cron/root
HEREDOC
EOT
  }
}

# launch configuration

resource "launch_configuration" "lc" {
  name_prefix          = "lc-"
  image_id             = "${ami_from_instance.golden.id}"
  instance_type        = "${var.lc_instance_type}"
  security_groups      = ["${security_group.private_sg.id}"]
  iam_instance_profile = "${iam_instance_profile.s3_access_profile.id}"
  key_name             = "${key_pair.auth.id}"
  user_data            = "${file("userdata")}"

  lifecycle {
    create_before_destroy = true
  }
}

# ASG 

#resource "random_id" "rand_asg" {
# byte_length = 8
#}

resource "autoscaling_group" "asg" {
  name                      = "asg-${launch_configuration.lc.id}"
  max_size                  = "${var.asg_max}"
  min_size                  = "${var.asg_min}"
  health_check_grace_period = "${var.asg_grace}"
  health_check_type         = "${var.asg_hct}"
  desired_capacity          = "${var.asg_cap}"
  force_delete              = true
  load_balancers            = ["${elb.elb.id}"]

  vpc_zone_identifier = ["${subnet.private1_subnet.id}",
    "${subnet.private2_subnet.id}",
  ]

  launch_configuration = "${launch_configuration.lc.name}"

  tag {
    key                 = "Name"
    value               = "asg-instance"
    propagate_at_launch = true
  }

  lifecycle {
    create_before_destroy = true
  }
}

# Route53

# primary zone

resource "route53_zone" "primary" {
  name              = "${var.domain_name}.com"
  delegation_set_id = "${var.delegation_set}"
}

# www 

resource "route53_record" "www" {
  zone_id = "${route53_zone.primary.zone_id}"
  name    = "www.${var.domain_name}.com"
  type    = "A"

  alias {
    name                   = "${elb.elb.dns_name}"
    zone_id                = "${elb.elb.zone_id}"
    evaluate_target_health = false
  }
}

# dev 

resource "route53_record" "dev" {
  zone_id = "${route53_zone.primary.zone_id}"
  name    = "dev.${var.domain_name}.com"
  type    = "A"
  ttl     = "300"
  records = ["${instance.dev.public_ip}"]
}

# secondary zone

resource "route53_zone" "secondary" {
  name   = "${var.domain_name}.com"
  vpc_id = "${vpc.vpc.id}"
}

# db 

resource "route53_record" "db" {
  zone_id = "${route53_zone.secondary.zone_id}"
  name    = "db.${var.domain_name}.com"
  type    = "CNAME"
  ttl     = "300"
  records = ["${db_instance.db.address}"]
}