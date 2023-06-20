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
  default     = "t2.medium"
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

resource "aws_security_group" "mongodb" {
  name = "mongodb"

  egress {
    to_port     = 0
    from_port   = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
  ingress {
    description = "ssh"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "db"
    from_port   = 27017
    to_port     = 27017
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }
  lifecycle {
    create_before_destroy = false
  }
}

resource "aws_security_group" "firewall-thingy" {
  name = "moleculer-sg"

  egress {
    to_port     = 0
    from_port   = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
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

  ingress {
    description = "rocketchat"
    from_port   = 3000
    to_port     = 3010
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  ingress {
    description = "nats"
    from_port   = 4222
    to_port     = 4222
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  lifecycle {
    create_before_destroy = false
  }
}

# resource "aws_ebs_volume" "ec2-shared-db" {
#   availability_zone    = aws_instance.nodes[0].availability_zone
#   size                 = 10
#   multi_attach_enabled = true
#   type                 = "io1"
#   iops                 = 500
# }
#
# resource "aws_volume_attachment" "attach_shared_volume" {
#   device_name = var.shared_volume_device_name
#   volume_id   = aws_ebs_volume.ec2-shared-db.id
#   instance_id = aws_instance.nodes[0].id
# }
#
# resource "aws_volume_attachment" "attach_shared_volume1" {
#   device_name = var.shared_volume_device_name
#   volume_id   = aws_ebs_volume.ec2-shared-db.id
#   instance_id = aws_instance.nodes[1].id
# }

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

resource "aws_launch_template" "db_template" {
  name = "mongodb"
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
    security_groups             = [aws_security_group.mongodb.id]
  }
}

resource "aws_instance" "db" {
  launch_template {
    id = aws_launch_template.db_template.id
  }
  provisioner "file" {
    content = <<COMPOSE
volumes: { mongodb_data: { driver: local } }
services:
  mongodb:
    image: docker.io/bitnami/mongodb:5.0
    restart: always
    volumes:
      - mongodb_data:/bitnami/mongodb
    environment:
      MONGODB_REPLICA_SET_MODE: primary
      MONGODB_REPLICA_SET_NAME: rs0
      MONGODB_PORT_NUMBER: 27017
      MONGODB_INITIAL_PRIMARY_HOST: ${self.private_ip}
      MONGODB_INITIAL_PRIMARY_PORT_NUMBER: 27017
      MONGODB_ADVERTISED_HOSTNAME: ${self.private_ip}
      ALLOW_EMPTY_PASSWORD: "yes"
    ports: [27017:27017]
COMPOSE
    connection {
      type  = "ssh"
      user  = "ubuntu"
      agent = true
      host  = self.public_ip
    }
    destination = "/home/ubuntu/compose.yml"
  }

  provisioner "remote-exec" {
    inline = ["sleep 10; curl -L get.docker.com | bash", "cd /home/ubuntu && sudo docker compose up -d"]
    connection {
      type  = "ssh"
      user  = "ubuntu"
      agent = true
      host  = self.public_ip
    }
  }
}

resource "aws_instance" "nodes" {
  launch_template {
    id = aws_launch_template.instance_template.id
  }
  count = 10
  provisioner "file" {
    content = templatefile("${path.module}/compose.yml.tftpl", {
      mongo_url       = "mongodb://${aws_instance.db.private_ip}:27017/rocketchat?replicaSet=rs0",
      mongo_oplog_url = "mongodb://${aws_instance.db.private_ip}:27017/local?replicaSet=rs0 "
      instance_ip     = self.private_ip
      public_ip       = self.public_ip
    })
    destination = "/home/ubuntu/compose.yml"
    connection {
      type = "ssh"
      user = "ubuntu"
      # private_key = file("/Users/debdut/.ssh/rocket.chat")
      agent = true
      host  = self.public_ip
    }
  }

  provisioner "remote-exec" {
    inline = ["sleep 10; curl -L get.docker.com | bash", "cd /home/ubuntu && sudo docker compose up -d"]
    connection {
      type  = "ssh"
      user  = "ubuntu"
      agent = true
      host  = self.public_ip
    }
  }
}

