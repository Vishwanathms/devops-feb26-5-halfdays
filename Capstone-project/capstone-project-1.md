Below is a **clean way to add a Terraform job** that:

* **Creates an Ubuntu VM (AWS EC2)**
* **Installs Docker (user_data)**
* **Opens port 8080 (and 22 for SSH)**
* **Then GitHub Actions SSH’s into the VM and runs your pushed Docker image**

You’ll have 3 parts:

1. ✅ Updated **GitHub Actions workflow** (adds Terraform + deploy-to-VM)
2. ✅ **Terraform code** (EC2 + SG + Docker install)
3. ✅ **Required GitHub Secrets**

---

## 1) Updated GitHub Actions Workflow (adds Terraform + deploy on VM)

Save as: `.github/workflows/ci-docker-terraform.yml`

```yaml
name: First GitHub Actions Workflow

on:
  push:
    branches: ["main"]
  pull_request:
    branches: ["main"]

jobs:
  CI-Part:
    runs-on: ubuntu-latest
    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Set up Docker Buildx
        uses: docker/setup-buildx-action@v3

      - name: Check if docker is present
        run: |
          echo "Checking Docker version..."
          docker --version

          echo "Checking Docker info..."
          docker info

          echo "Listing current directory..."
          ls -la

          echo "Checking OS details..."
          uname -a

      # -------------------------
      # Stage 2 — Build with commit ID as TAG
      # -------------------------
      - name: Set image tag
        run: echo "IMAGE_TAG=${GITHUB_SHA::7}" >> $GITHUB_ENV

      - name: Build image
        run: |
          docker build -t ${{ secrets.DOCKERHUB_USERNAME }}/python-gha-lab:${{ env.IMAGE_TAG }} .
          docker images

      # -------------------------
      # Stage 3 — Push to Docker Hub
      # -------------------------
      - name: Login to Docker Hub
        run: echo "${{ secrets.DOCKERHUB_TOKEN }}" | docker login -u "${{ secrets.DOCKERHUB_USERNAME }}" --password-stdin

      - name: Push Docker image
        run: |
          docker push ${{ secrets.DOCKERHUB_USERNAME }}/python-gha-lab:${{ env.IMAGE_TAG }}

  # ----------------------------------------
  # Terraform: Plan on PR, Apply on main push
  # ----------------------------------------
  terraform:
    name: Terraform - Provision VM (Docker + 8080 open)
    runs-on: ubuntu-latest
    needs: CI-Part

    steps:
      - name: Checkout code
        uses: actions/checkout@v4

      - name: Setup Terraform
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.7.5

      - name: Terraform Init
        working-directory: terraform
        run: terraform init

      - name: Terraform Format
        working-directory: terraform
        run: terraform fmt -check

      # Plan on PRs and pushes
      - name: Terraform Plan
        working-directory: terraform
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          AWS_REGION: ${{ secrets.AWS_REGION }}
        run: |
          terraform plan \
            -var "aws_region=${AWS_REGION}" \
            -var "ssh_public_key=${{ secrets.VM_SSH_PUBLIC_KEY }}" \
            -out tfplan

      # Apply only on push to main (not on PR)
      - name: Terraform Apply
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        working-directory: terraform
        env:
          AWS_ACCESS_KEY_ID: ${{ secrets.AWS_ACCESS_KEY_ID }}
          AWS_SECRET_ACCESS_KEY: ${{ secrets.AWS_SECRET_ACCESS_KEY }}
          AWS_REGION: ${{ secrets.AWS_REGION }}
        run: terraform apply -auto-approve tfplan

      - name: Export VM Public IP
        if: github.event_name == 'push' && github.ref == 'refs/heads/main'
        working-directory: terraform
        run: |
          VM_IP=$(terraform output -raw vm_public_ip)
          echo "VM_IP=$VM_IP" >> $GITHUB_ENV
          echo "VM Public IP: $VM_IP"

  # ------------------------------------------------
  # Deploy on VM: pull the pushed image and run it
  # ------------------------------------------------
  deploy_on_vm:
    name: Deploy on VM - Run container on port 8080
    runs-on: ubuntu-latest
    needs: terraform
    if: github.event_name == 'push' && github.ref == 'refs/heads/main'

    steps:
      - name: Set image tag (same as build job)
        run: echo "IMAGE_TAG=${GITHUB_SHA::7}" >> $GITHUB_ENV

      - name: Get VM IP from Terraform outputs (re-run output)
        uses: hashicorp/setup-terraform@v3
        with:
          terraform_version: 1.7.5

      - name: Checkout code (for terraform folder)
        uses: actions/checkout@v4

      - name: Terraform Init (for output)
        working-directory: terraform
        run: terraform init

      - name: Read VM Public IP
        working-directory: terraform
        run: |
          VM_IP=$(terraform output -raw vm_public_ip)
          echo "VM_IP=$VM_IP" >> $GITHUB_ENV
          echo "VM Public IP: $VM_IP"

      - name: Wait for SSH to be ready
        run: |
          set -e
          for i in {1..30}; do
            if nc -zv ${{ env.VM_IP }} 22; then
              echo "✅ SSH is reachable"
              exit 0
            fi
            echo "SSH not ready yet... retry $i/30"
            sleep 5
          done
          echo "❌ SSH not reachable"
          exit 1

      - name: SSH deploy (pull + run container)
        uses: appleboy/ssh-action@v1.0.3
        with:
          host: ${{ env.VM_IP }}
          username: ubuntu
          key: ${{ secrets.VM_SSH_PRIVATE_KEY }}
          script: |
            set -e

            echo "Docker version:"
            docker --version

            echo "Login to Docker Hub (optional if public repo):"
            echo "${{ secrets.DOCKERHUB_TOKEN }}" | docker login -u "${{ secrets.DOCKERHUB_USERNAME }}" --password-stdin

            IMAGE="${{ secrets.DOCKERHUB_USERNAME }}/python-gha-lab:${{ env.IMAGE_TAG }}"
            echo "Pulling image: $IMAGE"
            docker pull "$IMAGE"

            echo "Stopping old container (if any)..."
            docker rm -f python-gha-lab || true

            echo "Running container on port 8080..."
            docker run -d --name python-gha-lab -p 8080:8080 -e APP_ENV=vm "$IMAGE"

            echo "Containers:"
            docker ps -a

      - name: Verify app from GitHub runner (curl VM:8080)
        run: |
          set -e
          echo "Testing http://${{ env.VM_IP }}:8080/"
          for i in {1..20}; do
            if curl -fsS "http://${{ env.VM_IP }}:8080/"; then
              echo ""
              echo "✅ App is reachable on VM"
              exit 0
            fi
            echo "Not ready yet... retry $i/20"
            sleep 3
          done
          echo "❌ App not reachable in time"
          exit 1
```

---

## 2) Terraform Code (AWS EC2 + SG 8080 + Docker install)

Create a folder: `terraform/`

### `terraform/main.tf`

```hcl
terraform {
  required_version = ">= 1.5.0"
  required_providers {
    aws = {
      source  = "hashicorp/aws"
      version = "~> 5.0"
    }
  }
}

provider "aws" {
  region = var.aws_region
}

# Latest Ubuntu 22.04 LTS AMI
data "aws_ami" "ubuntu" {
  most_recent = true
  owners      = ["099720109477"] # Canonical

  filter {
    name   = "name"
    values = ["ubuntu/images/hvm-ssd/ubuntu-jammy-22.04-amd64-server-*"]
  }
}

resource "aws_key_pair" "vm_key" {
  key_name   = "gha-vm-key"
  public_key = var.ssh_public_key
}

resource "aws_security_group" "vm_sg" {
  name        = "gha-vm-sg"
  description = "Allow SSH and 8080"

  ingress {
    description = "SSH"
    from_port   = 22
    to_port     = 22
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"] # tighten later if you can
  }

  ingress {
    description = "App Port"
    from_port   = 8080
    to_port     = 8080
    protocol    = "tcp"
    cidr_blocks = ["0.0.0.0/0"]
  }

  egress {
    description = "All outbound"
    from_port   = 0
    to_port     = 0
    protocol    = "-1"
    cidr_blocks = ["0.0.0.0/0"]
  }
}

resource "aws_instance" "vm" {
  ami                    = data.aws_ami.ubuntu.id
  instance_type          = var.instance_type
  key_name               = aws_key_pair.vm_key.key_name
  vpc_security_group_ids = [aws_security_group.vm_sg.id]

  user_data = file("${path.module}/user_data.sh")

  tags = {
    Name = "gha-docker-vm"
  }
}
```

### `terraform/variables.tf`

```hcl
variable "aws_region" {
  type        = string
  description = "AWS region"
}

variable "instance_type" {
  type        = string
  description = "EC2 instance type"
  default     = "t3.micro"
}

variable "ssh_public_key" {
  type        = string
  description = "Public key content for SSH access"
}
```

### `terraform/outputs.tf`

```hcl
output "vm_public_ip" {
  value = aws_instance.vm.public_ip
}
```

### `terraform/user_data.sh`

```bash
#!/bin/bash
set -eux

# Basic updates
apt-get update -y

# Install Docker
apt-get install -y ca-certificates curl gnupg lsb-release

install -m 0755 -d /etc/apt/keyrings
curl -fsSL https://download.docker.com/linux/ubuntu/gpg | gpg --dearmor -o /etc/apt/keyrings/docker.gpg
chmod a+r /etc/apt/keyrings/docker.gpg

echo \
  "deb [arch=$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
  $(. /etc/os-release && echo "$VERSION_CODENAME") stable" \
  > /etc/apt/sources.list.d/docker.list

apt-get update -y
apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin

# Allow ubuntu user to run docker without sudo
usermod -aG docker ubuntu

systemctl enable docker
systemctl start docker
```

---

## 3) GitHub Secrets You Must Add

Go to **Repo → Settings → Secrets and variables → Actions → New repository secret**

### AWS

* `AWS_ACCESS_KEY_ID`
* `AWS_SECRET_ACCESS_KEY`
* `AWS_REGION` (example: `us-east-1`)

### Docker Hub (you already have)

* `DOCKERHUB_USERNAME`
* `DOCKERHUB_TOKEN`

### VM SSH

You need an SSH keypair.

* `VM_SSH_PRIVATE_KEY`  ✅ (private key contents)
* `VM_SSH_PUBLIC_KEY`   ✅ (public key contents, **single line**, starts with `ssh-rsa` or `ssh-ed25519`)

Example generate (your laptop):

```bash
ssh-keygen -t ed25519 -C "gha-vm" -f gha-vm-key
# public:  gha-vm-key.pub
# private: gha-vm-key
```

Put:

* contents of `gha-vm-key` into `VM_SSH_PRIVATE_KEY`
* contents of `gha-vm-key.pub` into `VM_SSH_PUBLIC_KEY`

