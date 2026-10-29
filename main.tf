
data "aws_ami" "app_ami" {
  most_recent = true
  owners      = ["amazon"]

  filter {
    name   = "name"
    values = ["amzn2-ami-hvm-*-x86_64-gp2"]
  }

  filter {
    name   = "state"
    values = ["available"]
  }
}

module "blog_vpc" {
  source = "terraform-aws-modules/vpc/aws"

  name = "dev"
  cidr = "10.0.0.0/16"

  azs             = ["us-west-2a", "us-west-2b", "us-west-2c"]
  private_subnets = ["10.0.1.0/24", "10.0.2.0/24", "10.0.3.0/24"]
  public_subnets  = ["10.0.101.0/24", "10.0.102.0/24", "10.0.103.0/24"]

  enable_nat_gateway = true

  tags = {
    Terraform = "true"
    Environment = "dev"
  }
}

module "blog_sg" {
  source  = "terraform-aws-modules/security-group/aws"
  version = "6.0.0"
  name = "blog_new"

  vpc_id = module.blog_vpc.vpc_id

  ingress_rules = {
    http = {
      from_port   = 80
      to_port     = 80
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow HTTP"
    }

    https = {
      from_port   = 443
      to_port     = 443
      ip_protocol = "tcp"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow HTTPS"
    }
  }

  egress_rules = {
    all = {
      ip_protocol = "-1"
      cidr_ipv4   = "0.0.0.0/0"
      description = "Allow all outbound traffic"
    }
  }
}

module "blog_alb" {
  source  = "terraform-aws-modules/alb/aws"
  version = "~> 9.0"

  name               = "blog-alb"
  load_balancer_type = "application"

  vpc_id  = module.blog_vpc.vpc_id
  subnets = module.blog_vpc.public_subnets

  security_groups = [module.blog_sg.id]

  target_groups = {
    blog = {
      name_prefix      = "blog-"
      protocol         = "HTTP"
      port             = 80
      target_type      = "instance"
      create_attachment = false
    }
  }

  listeners = {
    blog-http = {
      port     = 80
      protocol = "HTTP"

      forward = {
        target_group_key = "blog"
      }
    }
  }

  tags = {
    Environment = "dev"
  }
}

resource "aws_lb_target_group" "blog" {
  name     = "blog"
  port     = 80
  protocol = "HTTP"
  vpc_id   = module.blog_vpc.vpc_id
}

resource "aws_lb_target_group_attachment" "blog" {
  target_group_arn = aws_lb_target_group.blog.arn
  target_id        = aws_instance.blog.id
  port             = 80
}

module "blog_autoscaling" {
  source  = "terraform-aws-modules/autoscaling/aws"
  version = "9.3.2"

  name = "blog"

  min_size = 1
  max_size = 2

  vpc_zone_identifier = module.blog_vpc.public_subnets

  launch_template_name = "blog"
  security_groups = [module.blog_sg.id]
  instance_type = var.instance_type
  image_id = data.aws_ami.app_ami.id

  traffic_source_attachments = {
    blog_alb = {
      traffic_source_indetifier = aws_lb_target_group.blog.arn
    }
  }
}