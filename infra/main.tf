provider "aws" {
  region = "us-east-1"
}

output "ips" {
  value = aws_instance.nodes.*.public_ip
}

output "private_ips" {
  value = aws_instance.nodes.*.private_ip
}

variable "instance_type" {
  default     = "t3.micro"
  description = "aws instance type"
  type        = string
}

variable "shared_volume_device_name" {
  default = "/dev/sdf"
}

variable "ssh_key_name" {
  description = "SSH key name under your aws account"
  type        = string
}

data "aws_ami" "ubuntu" {
  most_recent = true
  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }

  filter {
    name   = "virtualization-type"
    values = ["hvm"]
  }
  owners = ["099720109477"] // my boi canonical
}

data "aws_availability_zones" "availability_zone" {
  filter {
    name   = "region-name"
    values = ["us-east-1"]
  }

  state = "available"
}

resource "aws_security_group" "firewall-thingy" {
  name = "moleculer-sg"
  
  egress {
    to_port = 0
    from_port = 0
    protocol = "-1"
    cidr_blocks = [ "0.0.0.0/0" ]
  }
  ingress {
    description = "for moluculer processes"
    from_port   = 8080
    to_port     = 8090
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_ebs_volume" "ec2-shared-db" {
  availability_zone    = aws_instance.nodes[0].availability_zone
  size                 = 10
  multi_attach_enabled = true
  type                 = "io1"
  iops                 = 500
}

resource "aws_volume_attachment" "attach_shared_volume" {
  device_name = var.shared_volume_device_name
  volume_id   = aws_ebs_volume.ec2-shared-db.id
  instance_id = aws_instance.nodes[0].id
}

resource "aws_volume_attachment" "attach_shared_volume1" {
  device_name = var.shared_volume_device_name
  volume_id   = aws_ebs_volume.ec2-shared-db.id
  instance_id = aws_instance.nodes[1].id
}

resource "aws_launch_template" "instance_template" {
  name = "ec2-moleculer"
  placement {
    availability_zone = data.aws_availability_zones.availability_zone.names[0]
  }
  block_device_mappings {
    device_name = tolist(data.aws_ami.ubuntu.block_device_mappings)[0].device_name
    ebs {
      volume_size           = 30
      delete_on_termination = true
    }
  }
  # vpc_security_group_ids = [aws_security_group.firewall-thingy.id]
  image_id      = data.aws_ami.ubuntu.image_id
  key_name      = var.ssh_key_name
  instance_type = var.instance_type
  network_interfaces {
    associate_public_ip_address = true
    security_groups             = [aws_security_group.firewall-thingy.id]
  }
}

resource "aws_instance" "nodes" {
  launch_template {
    id = aws_launch_template.instance_template.id
  }
  count = 2
}
