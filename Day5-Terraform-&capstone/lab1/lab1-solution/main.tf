# Provider Configuration
# Specifies which cloud provider to use and in which region
provider "aws" {
  region = "ap-south-1"

}

# EC2 Instance Resource
# Creates a single EC2 instance in AWS
resource "aws_instance" "my_first_instance" {

  # AMI (Amazon Machine Image) - Amazon Linux 2023 for ap-south-1
  ami = "ami-067ec7f9e54a67559"
  # Challenge: use latest LTS AMI id from Amazon using data sources (data-ami.tf)
  # ami = data.aws_ami.amazon_linux_2023.id

  instance_type = "t3.micro"

  tags = {
    Name = "userX"
  }
}
