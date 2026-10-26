variable "aws_region" {
  description = "AWS region to deploy into"
  type        = string
  default     = "eu-central-1" # Frankfurt
}

variable "project_name" {
  description = "Name prefix for all resources"
  type        = string
  default     = "iac-lab"
}

variable "instance_type" {
  description = "EC2 size. t3.micro is free-tier eligible in most regions (t2.micro in some older ones)."
  type        = string
  default     = "t3.micro"
}

variable "ssh_public_key" {
  description = "Contents of your SSH public key (e.g. the text of ~/.ssh/iac-lab.pub)"
  type        = string
}

variable "allowed_ssh_cidr" {
  description = "Only this IP range may SSH into the server. Use your own IP with /32, e.g. 203.0.113.10/32"
  type        = string
}
