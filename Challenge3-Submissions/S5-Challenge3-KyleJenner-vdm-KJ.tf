# Variables
variable "region" {
    description = "Used for ECS launch control."
    default = "eu-west-1"
}

variable "amis" {
    description = "Which AMI to spawn. Defaults to the AWS ECS optimized images."
    default = {
        eu-west-1 = "ami-809f84e6"
    }
}

# Configure AWS Provider
provider "aws" {
  region     = "eu-west-1"
  access_key = ""
  secret_key = ""
}

# Define a vpc
resource "aws_vpc" "vdmVPC" {
  cidr_block = "200.0.0.0/16"
  tags {
    Name = "vdmVPC"
  }
}

# Internet gateway for the public subnet
resource "aws_internet_gateway" "vdmIG" {
  vpc_id = "${aws_vpc.vdmVPC.id}"
  tags {
    Name = "ecsvdmIG"
  }
}

# Public subnet
resource "aws_subnet" "vdmPubSN0-0" {
  vpc_id = "${aws_vpc.vdmVPC.id}"
  cidr_block = "200.0.0.0/24"
  availability_zone = "eu-west-1a"
  tags {
    Name = "ecsvdmPubSN0-0-0"
  }
}

# Routing table for public subnet
resource "aws_route_table" "vdmPubSN0-0RT" {
  vpc_id = "${aws_vpc.vdmVPC.id}"
  route {
    cidr_block = "0.0.0.0/0"
    gateway_id = "${aws_internet_gateway.vdmIG.id}"
  }
  tags {
    Name = "vdmPubSN0-0RT"
  }
}

# Associate the routing table to public subnet
resource "aws_route_table_association" "vdmPubSN0-0RTAssn" {
  subnet_id = "${aws_subnet.vdmPubSN0-0.id}"
  route_table_id = "${aws_route_table.vdmPubSN0-0RT.id}"
}

resource "aws_security_group" "vdm_load_balancers" {
    name = "vdm_load_balancers"
    description = "Allows all traffic"
    vpc_id = "${aws_vpc.vdmVPC.id}"

    # configure ports
    ingress {
        from_port = 0
        to_port = 65535
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    # configure ports.
    egress {
        from_port = 0
        to_port = 65535
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}

resource "aws_security_group" "humanlink_ecs" {
    name = "humanlink_ecs"
    description = "Allows all traffic"
    vpc_id = "${aws_vpc.vdmVPC.id}"

    ingress {
        from_port = 0
        to_port = 65535
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }

    ingress {
        from_port = 0
        to_port = 65535
        protocol = "tcp"
        security_groups = ["${aws_security_group.vdm_load_balancers.id}"]
    }

    egress {
        from_port = 0
        to_port = 65535
        protocol = "tcp"
        cidr_blocks = ["0.0.0.0/0"]
    }
}
resource "aws_ecs_cluster" "vdm-main" {
    name = "vdm-ecs"
}

resource "aws_autoscaling_group" "vdm-ecs-cluster" {
    availability_zones = ["eu-west-1a"]
    name = "vdm-ecs-as"
    min_size = 2
    max_size = 5
    desired_capacity = 4
    health_check_type = "EC2"
    launch_configuration = "${aws_launch_configuration.vdm-ecs-lc.name}"
    vpc_zone_identifier = ["${aws_subnet.vdmPubSN0-0.id}"]
}

resource "aws_launch_configuration" "vdm-ecs-lc" {
    name = "esc-lc"
    image_id = "${lookup(var.amis, var.region)}"
    instance_type = "t2.micro"
    security_groups = ["${aws_security_group.humanlink_ecs.id}"]
    iam_instance_profile = "${aws_iam_instance_profile.ecs_ip.name}"
    associate_public_ip_address = true
    user_data = "#!/bin/bash\necho ECS_CLUSTER=vdm-ecs > /etc/ecs/ecs.config"
}

resource "aws_iam_instance_profile" "ecs_ip" {
    name = "ecs-instance-profile"
    roles = ["${aws_iam_role.ecs_instance_role.name}"]
}

resource "aws_iam_role" "ecs_instance_role" {
    name = "ecs-instance-role"
    path = "/"
    assume_role_policy = <<EOF
{
  "Version": "2008-10-17",
  "Statement": [
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ec2.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    },
    {
      "Sid": "",
      "Effect": "Allow",
      "Principal": {
        "Service": "ecs.amazonaws.com"
      },
      "Action": "sts:AssumeRole"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_instance_role" {
    name = "ecs-instance-role"
    role = "${aws_iam_role.ecs_instance_role.id}"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ecs:CreateCluster",
        "ecs:DeregisterContainerInstance",
        "ecs:DiscoverPollEndpoint",
        "ecs:Poll",
        "ecs:RegisterContainerInstance",
        "ecs:StartTelemetrySession",
        "ecs:Submit*"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

resource "aws_iam_role_policy" "ecs_scheduler_role" {
    name = "ecs-scheduler-role"
    role = "${aws_iam_role.ecs_instance_role.id}"
    policy = <<EOF
{
  "Version": "2012-10-17",
  "Statement": [
    {
      "Effect": "Allow",
      "Action": [
        "ec2:AuthorizeSecurityGroupIngress",
        "ec2:Describe*",
        "elasticloadbalancing:DeregisterInstancesFromLoadBalancer",
        "elasticloadbalancing:Describe*",
        "elasticloadbalancing:RegisterInstancesWithLoadBalancer"
      ],
      "Resource": "*"
    }
  ]
}
EOF
}

data "aws_ecs_task_definition" "helloworld" {
  task_definition = "${aws_ecs_task_definition.helloworldcontainer.family}"
}

resource "aws_ecs_task_definition" "helloworldcontainer" {
  family = "helloworldcontainer"

  container_definitions = <<DEFINITION
[
  {
    "cpu": 128,
    "portMappings": [
      {
        "containerPort": 5000,
        "hostPort": 80
      }
    ],
    "essential": true,
    "image": "training/webapp:latest",
    "memory": 128,
    "memoryReservation": 64,
    "name": "helloworld"
  }
]
DEFINITION
}

resource "aws_ecs_service" "helloworld" {
  name          = "helloworld"
  cluster       = "${aws_ecs_cluster.vdm-main.id}"
  desired_count = 4
  task_definition = "helloworldcontainer"

}